//
//  SteamLibrary.swift
//
//  只读取本机 Steam 客户端已经写下的库记录，用来区分「已安装 / 已在库 / 未入库」。
//  启动和下载都交给官方 steam:// 协议或容器里的 steam.exe，不改游戏文件。
//

import Foundation

enum SteamCatalogStatus: Equatable, Sendable {
    case installed
    case inLibrary
    case absent
}

nonisolated enum SteamLibrary {
    private static let lock = NSLock()
    private static var cache: [String: (Date, SteamCatalogStatus)] = [:]
    private static let cacheInterval: TimeInterval = 4

    static func status(appID: String?, bottleName: String?) -> SteamCatalogStatus {
        let id = (appID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return .absent }
        let key = id + "|" + (bottleName ?? "")
        let now = Date()
        lock.lock()
        if let cached = cache[key], now.timeIntervalSince(cached.0) < cacheInterval {
            lock.unlock()
            return cached.1
        }
        lock.unlock()

        let resolved = scan(appID: id, bottleName: bottleName)
        lock.lock()
        cache[key] = (now, resolved)
        lock.unlock()
        return resolved
    }

    /// 下载结束后清掉缓存，让详情页立刻重新读取清单和本地文件。
    static func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// 容器 C 盘里的官方 Steam 客户端。找到才返回 Windows 路径，供协议参数启动。
    static func bottleSteamExecutable(bottleName: String?) -> String? {
        let name = bottleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let candidates = [
            ("Program Files (x86)/Steam/steam.exe", "C:\\Program Files (x86)\\Steam\\steam.exe"),
            ("Program Files/Steam/steam.exe", "C:\\Program Files\\Steam\\steam.exe")
        ]
        for root in AppLauncher.driveRoots(named: name) {
            for (relative, windowsPath) in candidates {
                let file = root.appendingPathComponent(relative)
                if FileManager.default.fileExists(atPath: file.path) {
                    return windowsPath
                }
            }
        }
        return nil
    }

    static func macSteamAppExists() -> Bool {
        let homes = ["/Applications/Steam.app", NSHomeDirectory() + "/Applications/Steam.app"]
        return homes.contains { FileManager.default.fileExists(atPath: $0) }
    }

    static func runURL(appID: String) -> URL? {
        protocolURL(command: "run", appID: appID)
    }

    static func installURL(appID: String) -> URL? {
        protocolURL(command: "install", appID: appID)
    }

    static func storeURL(appID: String) -> URL? {
        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return URL(string: "https://store.steampowered.com/app/\(id)")
    }

    private static func protocolURL(command: String, appID: String) -> URL? {
        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "steam://\(command)/\(id)")
    }

    private static func scan(appID: String, bottleName: String?) -> SteamCatalogStatus {
        var owned = false
        for root in steamRoots(bottleName: bottleName) {
            for library in libraryRoots(steamRoot: root) {
                let manifest = library.appendingPathComponent("steamapps/appmanifest_\(appID).acf")
                if let text = readText(at: manifest, limit: 64_000) {
                    owned = true
                    if isFullyInstalled(text) {
                        return .installed
                    }
                }
                if textContainsAppID(readText(at: library.appendingPathComponent("steamapps/libraryfolders.vdf"), limit: 512_000), appID) {
                    owned = true
                }
            }
            if userDataContains(appID, steamRoot: root) {
                owned = true
            }
        }
        return owned ? .inLibrary : .absent
    }

    private static func steamRoots(bottleName: String?) -> [URL] {
        var roots = [
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/Steam")
        ]
        let name = bottleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return roots }
        for drive in AppLauncher.driveRoots(named: name) {
            roots.append(drive.appendingPathComponent("Program Files (x86)/Steam"))
            roots.append(drive.appendingPathComponent("Program Files/Steam"))
        }
        return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// libraryfolders.vdf 里登记的库目录。路径不存在就跳过。
    private static func libraryRoots(steamRoot: URL) -> [URL] {
        var roots = [steamRoot]
        guard let text = readText(at: steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf"), limit: 512_000) else {
            return roots
        }
        let pattern = #""path"\s+"([^"]+)""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return roots }
        let range = NSRange(text.startIndex..., in: text)
        for match in expression.matches(in: text, range: range) {
            guard let slice = Range(match.range(at: 1), in: text) else { continue }
            let raw = text[slice]
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\", with: "/")
            if raw.contains(":") && !raw.hasPrefix("/") {
                continue
            }
            let url = URL(fileURLWithPath: raw)
            if FileManager.default.fileExists(atPath: url.path), !roots.contains(url) {
                roots.append(url)
            }
        }
        return roots
    }

    private static func userDataContains(_ appID: String, steamRoot: URL) -> Bool {
        let userdata = steamRoot.appendingPathComponent("userdata")
        guard let accounts = try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil) else {
            return false
        }
        for account in accounts {
            let files = [
                account.appendingPathComponent("config/localconfig.vdf"),
                account.appendingPathComponent("7/remote/sharedconfig.vdf")
            ]
            for file in files {
                if textContainsAppID(readText(at: file, limit: 2_000_000), appID) {
                    return true
                }
            }
        }
        return false
    }

    private static func isFullyInstalled(_ manifest: String) -> Bool {
        guard let flags = stateFlags(in: manifest) else { return false }
        return flags & 4 != 0
    }

    private static func stateFlags(in text: String) -> Int? {
        guard let marker = text.range(of: "\"StateFlags\"") else { return nil }
        let tail = text[marker.upperBound...]
        let digits = tail.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func textContainsAppID(_ text: String?, _ appID: String) -> Bool {
        guard let text else { return false }
        return text.contains("\"\(appID)\"")
    }

    /// 二进制 VDF 不解析，避免把无关数字当成入库记录。
    private static func readText(at url: URL, limit: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: limit)
        guard !data.isEmpty, !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// 列表在首帧之外解析安装状态，避免启动时在布局过程里扫描容器目录。
nonisolated func resolvedLibraryStatus(platform: AppPlatform, path: String, bottle: String?, steamAppID: String?) -> SteamCatalogStatus {
    if steamAppID == "753", SteamLibrary.macSteamAppExists() {
        return .installed
    }
    if AppLauncher.isInstalled(platform: platform, path: path, bottleName: bottle) {
        return .installed
    }
    return SteamLibrary.status(appID: steamAppID, bottleName: bottle)
}
