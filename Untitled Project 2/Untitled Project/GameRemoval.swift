//
//  GameRemoval.swift
//
//  从游戏库移除一款游戏，并只删除容器里属于这款游戏的安装目录。
//  不删除共用的 Gaming / Office 容器，也不删除系统目录。
//

import Foundation

nonisolated enum GameRemoval {
    private static let hiddenKey = "Vesta.removedCatalogKeys"
    private static let lock = NSLock()

    static func isBlocked(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if folded.contains("valorant") || folded.contains("无畏契约") || folded.contains("瓦罗兰特") {
            return true
        }
        return false
    }

    static func isHidden(_ playtimeKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let keys = UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []
        return keys.contains(playtimeKey)
    }

    static func hide(playtimeKey: String) {
        lock.lock()
        defer { lock.unlock() }
        var keys = UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []
        if !keys.contains(playtimeKey) {
            keys.append(playtimeKey)
            UserDefaults.standard.set(keys, forKey: hiddenKey)
        }
    }

    /// 只检查 Vesta 自己的容器，删除名称明确属于无畏契约的安装目录。
    static func purgeBlockedRemnants() {
        for drive in existingDrives() {
            removeBlockedChildren(in: drive)
        }
    }

    /// 删除这款游戏在已有容器里的安装目录。目录不存在时不算失败。
    static func removeInstalledFiles(installPath: String, absolutePath: String, bottleName: String) -> Bool {
        var removed = false
        var failed = false
        for drive in existingDrives(bottleName: bottleName) {
            for folder in installFolders(installPath: installPath, absolutePath: absolutePath, drive: drive) {
                switch deleteIfSafe(folder, inside: drive) {
                case .removed:
                    removed = true
                case .failed:
                    failed = true
                case .missing, .rejected:
                    break
                }
            }
        }
        return !failed
    }

    private enum DeleteOutcome {
        case removed
        case missing
        case rejected
        case failed
    }

    private static func existingDrives(bottleName: String = "") -> [URL] {
        var drives: [URL] = []
        func append(root: URL) {
            let drive = root.lastPathComponent == "drive_c" ? root : root.appendingPathComponent("drive_c", isDirectory: true)
            let path = drive.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path) else { return }
            if !drives.contains(where: { $0.standardizedFileURL.path == path }) {
                drives.append(drive.standardizedFileURL)
            }
        }

        let saved = UserDefaults.standard.string(forKey: WinePrefixStore.defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefixPath = saved.isEmpty ? WinePrefixStore.desktopDefault.path : (saved as NSString).expandingTildeInPath
        append(root: URL(fileURLWithPath: prefixPath, isDirectory: true))

        let trimmed = bottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let token = trimmed.replacingOccurrences(of: "/", with: "-")
            let bottle = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/MyApp/Bottles", isDirectory: true)
                .appendingPathComponent(token, isDirectory: true)
            append(root: bottle)
        }
        return drives
    }

    private static func installFolders(installPath: String, absolutePath: String, drive: URL) -> [URL] {
        var folders: [URL] = []
        let relative = windowsRelative(installPath)
        if let folder = gameFolder(relative: relative) {
            folders.append(drive.appendingPathComponent(folder, isDirectory: true))
        }
        let absolute = (absolutePath as NSString).expandingTildeInPath
        if absolute.hasPrefix("/") {
            folders.append(URL(fileURLWithPath: absolute, isDirectory: false).deletingLastPathComponent())
        }
        return folders
    }

    private static func windowsRelative(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
        if let colon = value.firstIndex(of: ":"), value.distance(from: value.startIndex, to: colon) == 1 {
            value = String(value[value.index(after: colon)...])
        }
        while value.hasPrefix("/") {
            value.removeFirst()
        }
        return value
    }

    /// 停在游戏目录，不把 Program Files、Steam 或整个 Riot Games 目录当成删除目标。
    private static func gameFolder(relative: String) -> String? {
        let parts = relative.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard parts.count >= 2 else { return nil }
        let roots: Set<String> = ["program files", "program files (x86)", "windows", "users", "programdata"]
        let generic: Set<String> = ["live", "bin", "binaries", "win64", "win32", "x64", "x86", "game", "engine", "client"]
        var end = parts.count - 1
        while end > 0, generic.contains(parts[end - 1].lowercased()) {
            end -= 1
        }
        guard end > 0 else { return nil }
        let folder = parts.prefix(end).joined(separator: "/")
        let top = parts[0].lowercased()
        if roots.contains(top), end <= 1 { return nil }
        if roots.contains(folder.lowercased()) { return nil }
        return folder
    }

    private static func deleteIfSafe(_ folder: URL, inside drive: URL) -> DeleteOutcome {
        let drivePath = drive.standardizedFileURL.path
        let target = folder.standardizedFileURL.path
        guard target.hasPrefix(drivePath + "/") else { return .rejected }
        let relative = String(target.dropFirst(drivePath.count + 1))
        let top = relative.split(separator: "/").first.map(String.init)?.lowercased() ?? ""
        let protected: Set<String> = ["windows", "users", "programdata"]
        if protected.contains(top) || relative.isEmpty { return .rejected }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory) else { return .missing }
        guard isDirectory.boolValue else { return .rejected }
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: target, isDirectory: true))
            print("[GameRemoval] 已删除 \(target)")
            return .removed
        } catch {
            print("[GameRemoval] 删除失败 \(target)：\(error.localizedDescription)")
            return .failed
        }
    }

    private static func removeBlockedChildren(in drive: URL) {
        let roots = ["Program Files", "Program Files (x86)", "Riot Games", "Program Files/Riot Games", "Program Files (x86)/Riot Games", "Program Files/Vesta Imports"]
        for root in roots {
            let folder = drive.appendingPathComponent(root, isDirectory: true)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children where isBlocked(child.lastPathComponent) {
                _ = deleteIfSafe(child, inside: drive)
            }
        }
        let direct = [
            "Program Files/无畏契约",
            "Program Files (x86)/无畏契约",
            "Riot Games/VALORANT",
            "Program Files/Riot Games/VALORANT",
            "Program Files (x86)/Riot Games/VALORANT"
        ]
        for relative in direct {
            _ = deleteIfSafe(drive.appendingPathComponent(relative, isDirectory: true), inside: drive)
        }
    }
}
