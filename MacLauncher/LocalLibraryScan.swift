//
//  LocalLibraryScan.swift
//
//  在常见安装目录里查找游戏和软件，找到后把列表里的路径改成真实文件。
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct LibraryScanTarget: Sendable {
    let id: UUID
    let installPath: String
    let isMacApp: Bool
}

struct LibraryScanUpdate: Sendable {
    let id: UUID
    let installPath: String
    let isInstalled: Bool
}

nonisolated enum LocalLibraryScan {
    static func scan(_ apps: [LibraryScanTarget]) -> [LibraryScanUpdate] {
        let roots = searchRoots()
        let applications = applicationRoots()
        return apps.map { app in
            if let found = locate(app.installPath, isMacApp: app.isMacApp, roots: roots, applications: applications) {
                return LibraryScanUpdate(id: app.id, installPath: found, isInstalled: true)
            }
            return LibraryScanUpdate(id: app.id, installPath: app.installPath, isInstalled: false)
        }
    }

    private static func locate(_ installPath: String, isMacApp: Bool, roots: [URL], applications: [URL]) -> String? {
        let trimmed = installPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = existingLocalFile(trimmed) {
            return existing
        }
        if let resolved = AppLauncher.resolvedMacAppPath(trimmed) {
            return resolved
        }

        let fileName = expectedFileName(trimmed)
        guard !fileName.isEmpty else { return nil }
        if let app = matchApplication(named: fileName, in: applications) {
            return app
        }
        if isMacApp {
            return nil
        }
        for root in roots {
            if let match = find(fileName: fileName, under: root, maxDepth: 6) {
                return match
            }
        }
        return nil
    }

    /// `/Applications` 和 `~/Applications` 只看顶层和下一层，并忽略大小写。
    private static func matchApplication(named fileName: String, in roots: [URL]) -> String? {
        let appName = fileName.lowercased().hasSuffix(".app")
            ? fileName
            : (fileName as NSString).deletingPathExtension + ".app"
        for root in roots {
            let direct = root.appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct.path
            }
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }
            for child in children {
                if brokenSymlink(child) { continue }
                if child.lastPathComponent.compare(appName, options: .caseInsensitive) == .orderedSame,
                   FileManager.default.fileExists(atPath: child.path) {
                    return child.path
                }
                let nested = child.appendingPathComponent(appName)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return nested.path
                }
            }
        }
        return nil
    }

    private static func existingLocalFile(_ path: String) -> String? {
        guard !path.isEmpty, !path.contains("\\"), !path.contains(":") || path.hasPrefix("/") else {
            return nil
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return expanded
    }

    private static func expectedFileName(_ path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return URL(fileURLWithPath: normalized).lastPathComponent
    }

    private static func searchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots = [
            home.appendingPathComponent("Library/Application Support/Steam/steamapps/common"),
            home.appendingPathComponent("Library/Application Support/Steam/steamapps")
        ]
        roots.append(contentsOf: applicationRoots())
        roots.append(contentsOf: bottleDrives())
        return roots.filter(usableDirectory)
    }

    private static func applicationRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ].filter(usableDirectory)
    }

    private static func bottleDrives() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let parents = [
            home.appendingPathComponent("Library/Application Support/CrossOver/Bottles"),
            home.appendingPathComponent("Library/Application Support/MyApp/Bottles")
        ]
        var drives: [URL] = []
        let prefix = StorageMeasure.currentPrefix().appendingPathComponent("drive_c")
        if usableDirectory(prefix) {
            drives.append(prefix)
        }
        for parent in parents where usableDirectory(parent) {
            let bottles: [URL]
            do {
                bottles = try FileManager.default.contentsOfDirectory(
                    at: parent,
                    includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]
                )
            } catch {
                print("[Scan] 读不到容器目录 \(parent.path)：\(error.localizedDescription)")
                continue
            }
            for bottle in bottles {
                if brokenSymlink(bottle) { continue }
                let drive = bottle.appendingPathComponent("drive_c")
                if usableDirectory(drive) {
                    drives.append(drive)
                }
            }
        }
        return drives
    }

    private static func usableDirectory(_ url: URL) -> Bool {
        guard !brokenSymlink(url) else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func brokenSymlink(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink == true else { return false }
        let destination = url.resolvingSymlinksInPath()
        return !FileManager.default.fileExists(atPath: destination.path)
    }

    private static func find(fileName: String, under root: URL, maxDepth: Int) -> String? {
        guard usableDirectory(root) else { return nil }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        let target = fileName.lowercased()
        let rootCount = root.pathComponents.count
        var seen = Set<String>()
        if let rootPath = resolvedPath(root) {
            seen.insert(rootPath)
        }
        while let item = enumerator.nextObject() as? URL {
            let depth = item.pathComponents.count - rootCount
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if brokenSymlink(item) {
                enumerator.skipDescendants()
                continue
            }
            if let resolved = resolvedPath(item), !seen.insert(resolved).inserted {
                enumerator.skipDescendants()
                continue
            }
            if item.lastPathComponent.lowercased() == target, FileManager.default.fileExists(atPath: item.path) {
                return item.path
            }
        }
        return nil
    }

    private static func resolvedPath(_ url: URL) -> String? {
        let path = url.resolvingSymlinksInPath().path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
}

enum MacAppPicker {
    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = L10n.string(.bindLocalApp, language: L10n.savedLanguage())
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard url.pathExtension.lowercased() == "app" else { return nil }
        return url
    }
}
