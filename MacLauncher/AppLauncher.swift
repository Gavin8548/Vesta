//
//  AppLauncher.swift
//
//  把详情页的「运行 (Run)」变成真正的启动：
//  macOS 程序用 NSWorkspace 或 Process。.exe 放进 Vesta 自己的 Wine 容器后，用 wine 启动。
//  启动过程写到 Xcode 控制台，并以通知告诉界面进程何时退出。
//

import AppKit
import Darwin

nonisolated extension Notification.Name {
    /// userInfo["id"] 是 WindowsApp.ID。进程退出或无法结束时都会发出。
    static let windowsAppDidExit = Notification.Name("windowsAppDidExit")
    static let vestaLibraryRestored = Notification.Name("VestaLibraryRestored")
}

nonisolated struct LaunchRequest: Sendable {
    let appID: UUID
    let name: String
    let installPath: String
    let bottleName: String
    let enablesDXVK: Bool
    let enablesMetal3: Bool
    let enablesEsync: Bool
    /// 应用内的容器列表里已经有同名或同 id 的瓶子。
    let bottleIsKnown: Bool
    /// macOS 原生应用直接用 NSWorkspace 打开，不检查容器。
    let isMacApp: Bool
    /// 追加在可执行文件后面的参数。本地容器直接运行时会丢掉 steam:// 链接。
    var extraArguments: [String] = []
    /// 启动成功时显示的说明。留空则使用引擎默认文案。
    var successMessage: String = ""
    /// 为 true 时只把游戏 .exe 交给 wine64，不打开 Steam 主界面。
    var directExecutable: Bool = false
    /// 为 true 时先打开 1920×1080 的虚拟桌面，避免游戏改分辨率把画面撑坏。
    var usesVirtualDesktop: Bool = false
    /// 和 apps.json 里的时长键一致。退出时如果进程还在，用它把这一段时间写回去。
    var playtimeKey: String = ""
    /// CrossOver 的 D3DMetal 才认识。打开后写入 D3DM_ENABLE_METALFX。
    var enablesMetalFX: Bool = false
    /// 仅当 wineserver 里真有 FSync 实现时才会写成 WINEFSYNC。
    var enablesFsync: Bool = false
}

nonisolated struct LaunchResult: Sendable {
    let succeeded: Bool
    let message: String
    var needsRebuild: Bool = false
}

/// 查找本机 wine64。先看记住的路径和已安装的引擎目录，再看 Homebrew、PATH、Whisky。
nonisolated enum WineLocator {
    static let defaultsKey = "WineEnginePath"

    static var engineRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vesta/Engine", isDirectory: true)
    }

    static func search() -> URL? {
        if let saved = savedEngineIfPresent() {
            return saved
        }
        return bundledEngine()
    }

    /// 启动时先认 UserDefaults。文件还在硬盘上就直接用，不再下载。
    static func savedEngineIfPresent() -> URL? {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        print("当前读取到的 Wine 路径: \(saved ?? "nil")")
        guard let saved else { return nil }
        let expanded = (saved as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            print("【Wine 引擎】已保存路径不在硬盘上：\(expanded)")
            return nil
        }
        print("【Wine 引擎】本地文件存在，跳过下载：\(expanded)")
        return URL(fileURLWithPath: expanded)
    }

    /// 没有已保存的引擎时，才看 Whisky 自带的 wine64。
    private static func bundledEngine() -> URL? {
        let home = NSHomeDirectory()
        let bundled = [
            "/Applications/Whisky.app/Contents/Resources/Wine/bin/wine64",
            home + "/Applications/Whisky.app/Contents/Resources/Wine/bin/wine64",
            "/Applications/Whisky.app/Contents/Resources/wine/bin/wine64"
        ]
        for path in bundled where existingFile(path) {
            remember(path)
            print("【Wine 引擎】已锁定 Whisky：\(path)")
            return URL(fileURLWithPath: path)
        }
        if let libraries = whiskyWine64() {
            remember(libraries)
            print("【Wine 引擎】已锁定 Whisky Libraries：\(libraries)")
            return URL(fileURLWithPath: libraries)
        }
        return nil
    }

    /// 只排除 WineHQ 5.0 那份 `Engine/usr` 旧包。Whisky 运行时解压在 `Engine/Libraries`，可以继续用。
    static func isRetiredDownload(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        let legacy = engineRoot.appendingPathComponent("usr", isDirectory: true).standardizedFileURL.path
        return expanded == legacy || expanded.hasPrefix(legacy + "/")
    }

    private static func existingFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    /// 全深度查找。`.app` 会再单独遍历一次，避免包目录被跳过。
    static func findWine64(in root: URL) -> String? {
        findAllWine64(in: root).first { path in
            URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent == "bin"
        } ?? findAllWine64(in: root).first
    }

    /// 用 enumerator 找出解压目录里每一个名为 wine64 的文件。
    static func findAllWine64(in root: URL) -> [String] {
        findAllNamed("wine64", in: root)
    }

    /// 先找 wine64。Wine 11 起官方只提供 `wine`，这时在同目录建立名为 wine64 的链接。
    static func resolveWine64(in root: URL) -> String? {
        if let found = findWine64(in: root) {
            return found
        }
        guard let wine = findNamed("wine", in: root) else { return nil }
        let link = URL(fileURLWithPath: wine).deletingLastPathComponent().appendingPathComponent("wine64")
        if !FileManager.default.fileExists(atPath: link.path) {
            do {
                try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "wine")
                print("[WineEngine] 官方包的加载器是 wine，已链接为 \(link.path)")
            } catch {
                print("[WineEngine] 无法建立 wine64 链接：\(error)")
                return wine
            }
        }
        return link.path
    }

    private static func findNamed(_ name: String, in root: URL) -> String? {
        let matches = findAllNamed(name, in: root)
        if let preferred = matches.first(where: {
            URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent == "bin"
        }) {
            return preferred
        }
        return matches.first
    }

    private static func findAllNamed(_ name: String, in root: URL) -> [String] {
        var matches: [String] = []
        var pending = [root]
        var seen = Set<String>()
        while let directory = pending.popLast() {
            let key = directory.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [],
                errorHandler: { url, error in
                    print("[WineEngine] 遍历 \(url.path) 失败：\(error.localizedDescription)")
                    return true
                }
            ) else { continue }
            for case let url as URL in enumerator {
                if url.lastPathComponent == name {
                    var itemIsDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &itemIsDirectory), !itemIsDirectory.boolValue {
                        matches.append(url.path)
                    }
                }
                if url.pathExtension == "app" {
                    pending.append(url)
                }
            }
        }
        return matches
    }

    static func remember(_ path: String) {
        UserDefaults.standard.set(path, forKey: "WineEnginePath")
        print("成功保存 Wine 路径: \(path)")
    }

    private static func whiskyWine64() -> String? {
        let homes = [
            NSHomeDirectory() + "/Library/Application Support/com.isaacmarovitz.Whisky/Libraries",
            NSHomeDirectory() + "/Library/Containers/com.isaacmarovitz.Whisky/Data/Library/Application Support/com.isaacmarovitz.Whisky/Libraries"
        ]
        for item in homes {
            let root = URL(fileURLWithPath: item, isDirectory: true)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            if let path = findWine64(in: root) {
                return path
            }
        }
        return nil
    }
}

/// 本机的标准 Wine。只认 Homebrew、/usr/local 和用户选定的 wine64。
nonisolated enum HostEngine: String, CaseIterable, Identifiable, Sendable {
    case wine
    case crossover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wine: return "Wine"
        case .crossover: return "CrossOver"
        }
    }

    private static let storageKey = "MyApp.hostEngine"

    static func remembered() -> HostEngine? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        return HostEngine(rawValue: raw)
    }

    static func remember(_ engine: HostEngine) {
        UserDefaults.standard.set(engine.rawValue, forKey: storageKey)
    }

    static func installed() -> [HostEngine] {
        allCases.filter(\.isInstalled)
    }

    var isInstalled: Bool {
        executableURL() != nil
    }

    /// 仍可用的上次选择；否则用已安装列表里的第一个，Wine Stable 排在最前。
    static func resolved() -> HostEngine? {
        if let saved = remembered(), saved.isInstalled {
            return saved
        }
        return installed().first
    }

    func executableURL() -> URL? {
        switch self {
        case .wine: return WineLocator.search()
        case .crossover: return Self.firstExecutable(Self.crossoverCandidates)
        }
    }

    /// 运行游戏时只用标准 wine64。CrossOver 不参与这条命令。
    static func standardWineBinary() -> URL? {
        WineLocator.search()
    }

    /// CrossOver 用 --bottle。标准 wine64 只接收 exe 路径，并另设 WINEPREFIX。
    func launchLeading(bottleName: String, prefix: URL) -> [String] {
        guard self == .crossover else { return [] }
        let bottle = bottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bottle.isEmpty, prefix.lastPathComponent.caseInsensitiveCompare(bottle) == .orderedSame else {
            return []
        }
        return ["--bottle", bottle]
    }

    private static func firstExecutable(_ paths: [String]) -> URL? {
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static var crossoverCandidates: [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []
        for root in ["/Applications", home + "/Applications"] {
            for name in ["wine", "cxstart"] {
                paths.append(root + "/CrossOver.app/Contents/SharedSupport/CrossOver/bin/" + name)
            }
        }
        return paths
    }
}

/// 记住文件选择器的授权，启动时重新打开导入的 exe。
nonisolated enum ImportedFileAccess {
    private static let lock = NSLock()
    private static var retained: [UUID: [URL]] = [:]

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// 返回还能读到的本机路径。找不到时返回 nil，调用方再提示未安装。
    static func prepare(bookmark: Data?, fallback: String, id: UUID) -> String? {
        if let bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                retain(url, id: id)
                retain(url.deletingLastPathComponent(), id: id)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url.path
                }
            }
        }
        let expanded = (fallback as NSString).expandingTildeInPath
        if expanded.hasPrefix("/"), FileManager.default.fileExists(atPath: expanded) {
            return expanded
        }
        return nil
    }

    private static func retain(_ url: URL, id: UUID) {
        _ = url.startAccessingSecurityScopedResource()
        lock.lock()
        retained[id, default: []].append(url)
        lock.unlock()
    }
}

/// 不放在主线程上跑进程。工程默认隔离是 MainActor，这里显式退出。
nonisolated enum AppLauncher {
    private static let logPrefix = "[Launch]"

    private static let installLock = NSLock()
    private static var installCache: [String: (Date, Bool)] = [:]
    private static let installCacheInterval: TimeInterval = 2

    /// 列表刷新后立刻重新检查安装文件，不等缓存过期。
    static func invalidateInstallCache() {
        installLock.lock()
        installCache.removeAll()
        installLock.unlock()
    }

    /// 详情页和列表用的安装状态。macOS 看路径上的 .app；Windows 看对应容器 C 盘里的 .exe。
    /// 结果缓存 2 秒，避免 SwiftUI 每次布局都去列容器目录。
    static func isInstalled(platform: AppPlatform, path: String, bottleName: String?) -> Bool {
        let key = platform.rawValue + "\n" + path + "\n" + (bottleName ?? "")
        let now = Date()
        installLock.lock()
        if let cached = installCache[key], now.timeIntervalSince(cached.0) < installCacheInterval {
            installLock.unlock()
            return cached.1
        }
        installLock.unlock()
        let value = installedNow(platform: platform, path: path, bottleName: bottleName)
        installLock.lock()
        installCache[key] = (now, value)
        installLock.unlock()
        return value
    }

    private static func installedNow(platform: AppPlatform, path: String, bottleName: String?) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if platform == .macOS {
            return resolvedMacAppPath(trimmed) != nil
        }

        if !looksLikeWindowsPath(trimmed) {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: expanded)
        }

        let relative = windowsRelativePath(trimmed)
        let name = bottleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !relative.isEmpty, !name.isEmpty else { return false }
        for root in matchingDriveRoots(named: name) {
            let file = root.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: file.path) {
                return true
            }
        }
        return false
    }

    /// 只查找名称相符的 CrossOver、Whisky 或本应用容器，避免把别的瓶子里的文件算成已安装。
    static func driveRoots(named name: String) -> [URL] {
        matchingDriveRoots(named: name)
    }

    /// 只查找名称相符的 CrossOver、Whisky 或本应用容器，避免把别的瓶子里的文件算成已安装。
    private static func matchingDriveRoots(named name: String) -> [URL] {
        let home = NSHomeDirectory()
        let roots = [
            URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MyApp/Bottles")
        ]
        var drives: [URL] = []
        for root in roots {
            guard let bottles = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else { continue }
            for bottle in bottles {
                let folderMatch = bottle.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
                guard folderMatch || whiskyBottle(bottle, matches: name) else { continue }
                let drive = bottle.lastPathComponent == "drive_c" ? bottle : bottle.appendingPathComponent("drive_c")
                if !drives.contains(drive) {
                    drives.append(drive)
                }
            }
        }
        return drives
    }

    /// 安装文件是否在 Mac 本地，或某个 Wine 容器的 C 盘里。
    static func installExists(path: String, bottleName: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if !looksLikeWindowsPath(trimmed) {
            let expanded = (trimmed as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                log("找到本地文件：\(expanded)")
                return true
            }
        }

        let relative = windowsRelativePath(trimmed)
        guard !relative.isEmpty else { return false }
        for root in bottleDriveRoots(named: bottleName) {
            let file = root.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: file.path) {
                log("找到容器内文件：\(file.path)")
                return true
            }
        }
        log("本地和容器中都没有：\(trimmed)")
        return false
    }

    static func launch(_ request: LaunchRequest) async -> LaunchResult {
        log("准备启动 \(request.name)")
        let path = request.installPath.trimmingCharacters(in: .whitespacesAndNewlines)
        log("安装路径：\(path)")
        if request.isMacApp {
            guard !path.isEmpty else {
                return failure(L10n.string(.noPath, language: L10n.savedLanguage()))
            }
            return await openInstalledMacApp(path)
        }
        let savedPath = UserDefaults.standard.string(forKey: WineLocator.defaultsKey)
        print("当前读取到的 Wine 路径: \(savedPath ?? "nil")")
        if let savedPath {
            let expanded = (savedPath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                print("【Wine 引擎】本地文件存在，跳过下载：\(expanded)")
                return await launchOnBackground(request, path: path, wine: URL(fileURLWithPath: expanded))
            }
        }
        if let installed = WineLocator.search(), FileManager.default.fileExists(atPath: installed.path) {
            return await launchOnBackground(request, path: path, wine: installed)
        }
        let downloaded: URL
        do {
            downloaded = try await WineEngineInstaller.shared.installIfNeeded()
        } catch {
            return failure(error.localizedDescription)
        }
        guard FileManager.default.fileExists(atPath: downloaded.path) else {
            return failure("已安装的 wine64 不存在：\(downloaded.path)")
        }
        return await launchOnBackground(request, path: path, wine: downloaded)
    }

    private static func launchOnBackground(_ request: LaunchRequest, path: String, wine: URL) async -> LaunchResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: launchInLocalPrefix(request, path: path, wine: wine))
            }
        }
    }

    /// macOS 原生 .app：先认保存的路径，再认 `/Applications` 和 `~/Applications`。
    static func resolvedMacAppPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return expanded
        }
        let name = URL(fileURLWithPath: expanded).lastPathComponent
        guard name.lowercased().hasSuffix(".app") else { return nil }
        let candidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(name),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent(name)
        ]
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            return candidate.path
        }
        return nil
    }

    /// macOS 原生 .app：不查容器，路径存在就交给系统打开。
    @MainActor
    private static func openInstalledMacApp(_ path: String) async -> LaunchResult {
        guard let expanded = resolvedMacAppPath(path) else {
            return failure(L10n.format(.appMissing, L10n.savedLanguage(), path))
        }
        let url = URL(fileURLWithPath: expanded)
        let opened = NSWorkspace.shared.open(url)
        if opened {
            log("NSWorkspace 已打开 \(url.path)")
            return LaunchResult(succeeded: true, message: L10n.string(.macOpened, language: L10n.savedLanguage()))
        }
        return failure(L10n.format(.openFailed, L10n.savedLanguage(), url.path))
    }

    /// 在 Vesta 自己的容器目录里执行 `wine64 <exe>`。调用方已在后台队列。
    private static func launchInLocalPrefix(_ request: LaunchRequest, path: String, wine: URL) -> LaunchResult {
        let root = BottleActions.prepareVestaPrefix()
        let copied = copyExecutableIntoPrefix(path, prefix: root)
        log("本地容器：\(root.path)")
        let wine64Path = wine.standardizedFileURL.path
        let exePath = copied
        print("【路径校验】wine64=\(wine64Path)")
        print("【路径校验】exe=\(exePath)")
        guard wine64Path.hasPrefix("/") else {
            return failure("wine64 不是绝对路径：\(wine64Path)")
        }
        guard FileManager.default.fileExists(atPath: wine64Path) else {
            return failure("wine64 不存在：\(wine64Path)")
        }
        if !FileManager.default.isExecutableFile(atPath: wine64Path) {
            print("【权限校验】isExecutableFile=false，执行 chmod +x：\(wine64Path)")
            if let reason = grantExecutePermission(wine64Path) {
                return failure(reason)
            }
            guard FileManager.default.isExecutableFile(atPath: wine64Path) else {
                return failure("wine64 没有执行权限：\(wine64Path)")
            }
        }
        guard exePath.hasPrefix("/") else {
            return failure("目标 exe 不是绝对路径：\(exePath)")
        }
        guard FileManager.default.fileExists(atPath: exePath) else {
            return failure("目标 exe 不存在：\(exePath)")
        }
        clearQuarantine(exePath: wine64Path)
        clearQuarantine(exePath: exePath)
        var environment = graphicsEnvironment(request, host: .wine)
        environment["WINEPREFIX"] = root.path
        environment["WINEDEBUG"] = "-all"
        environment["WINEARCH"] = "win64"
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = wine.deletingLastPathComponent().path + ":" + currentPath
        if let libraries = wineLibraryPath(wine) {
            let current = ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
            environment["DYLD_FALLBACK_LIBRARY_PATH"] = current.isEmpty ? libraries : libraries + ":" + current
        }
        let wineURL = URL(fileURLWithPath: wine64Path)
        print("【Wine 环境】WINEPREFIX=\(root.path) WINEDEBUG=-all WINEARCH=win64")
        if let reason = bootstrapPrefixIfNeeded(wine64: wineURL, prefix: root, pathEnvironment: environment["PATH"] ?? "", libraryPath: environment["DYLD_FALLBACK_LIBRARY_PATH"]) {
            return failure(reason)
        }
        let arguments = wineArguments(request: request, executable: wineURL, exePath: exePath)
        let command = wineCommand(wine64: wineURL, arguments: arguments)
        print("【Wine 参数】executableURL=\(command.executable.path)")
        print("【Wine 参数】arguments=\(command.arguments)")
        return start(
            executable: command.executable,
            arguments: command.arguments,
            environment: environment,
            appID: request.appID,
            playtimeKey: request.playtimeKey,
            engine: "wine64",
            successMessage: request.successMessage,
            directory: root
        )
    }

    private static func copyExecutableIntoPrefix(_ path: String, prefix: URL) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/"), expanded.lowercased().hasSuffix(".exe"), FileManager.default.fileExists(atPath: expanded) {
            do {
                let windows = try BottleActions.installImportedExecutable(from: URL(fileURLWithPath: expanded), prefix: prefix)
                return hostedExecutablePath(windows, prefix: prefix)
            } catch {
                print("【Wine严重报错】: 复制到容器失败：\(error.localizedDescription)")
                return expanded
            }
        }
        return hostedExecutablePath(trimmed, prefix: prefix)
    }

    static func stop(appID: UUID) {
        if LaunchSessionStore.shared.terminate(appID) {
            log("已向进程发送停止信号")
            return
        }
        log("没有由本程序拉起的进程，只更新界面状态")
        NotificationCenter.default.post(name: .windowsAppDidExit, object: nil, userInfo: ["id": appID])
    }

    /// 只认本机上真实存在的文件，不查容器目录。
    private static func localExecutable(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), FileManager.default.fileExists(atPath: expanded) else { return nil }
        return expanded
    }

    /// 本机上真实存在的 exe 保持 Mac 路径，Wine 会从 Z 盘打开。只有 C:\ 这种路径才转成反斜杠。
    private static func containerExecutablePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("steam:") else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/"), expanded.lowercased().hasSuffix(".exe"), FileManager.default.fileExists(atPath: expanded) {
            return expanded
        }
        let windows = trimmed.replacingOccurrences(of: "/", with: "\\")
        guard windows.lowercased().hasSuffix(".exe") else { return nil }
        return windows
    }

    /// `C:\Program Files\...` 在容器里能找到时，改传该文件的 Mac 路径。反斜杠留给外壳脚本时会被吃掉，Wine 就会秒退。
    private static func hostedExecutablePath(_ path: String, prefix: URL) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: trimmed) {
                return trimmed
            }
            log("本机路径不存在：\(trimmed)")
        }
        let relative = windowsRelativePath(trimmed)
        if !relative.isEmpty {
            let file = prefix.appendingPathComponent("drive_c").appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: file.path) {
                log("容器内文件：\(file.path)")
                return file.path
            }
            log("容器内未找到：\(file.path)")
        }
        if trimmed.contains("\\") {
            return trimmed.replacingOccurrences(of: "\\", with: "/")
        }
        return trimmed
    }

    /// 下载来的 wine64 常被 Gatekeeper 标成隔离文件，启动前清掉，避免系统静默拦住。
    private static func clearQuarantine(exePath: String) {
        guard FileManager.default.fileExists(atPath: exePath) else {
            print("【Wine严重报错】: 隔离属性清理跳过，文件不存在：\(exePath)")
            return
        }
        let xattrURL = URL(fileURLWithPath: "/usr/bin/xattr")
        guard FileManager.default.isExecutableFile(atPath: xattrURL.path) else {
            print("【Wine严重报错】: /usr/bin/xattr 不可执行")
            return
        }
        let xattrProcess = Process()
        xattrProcess.executableURL = xattrURL
        xattrProcess.arguments = ["-d", "com.apple.quarantine", exePath]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        xattrProcess.standardOutput = outputPipe
        xattrProcess.standardError = errorPipe
        do {
            try xattrProcess.run()
        } catch {
            print("【Wine严重报错】: \(error.localizedDescription)")
            return
        }
        xattrProcess.waitUntilExit()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !output.isEmpty {
            print("【Wine标准输出】: \(String(data: output, encoding: .utf8) ?? "")")
        }
        if !errorData.isEmpty {
            print("【Wine严重报错】: \(String(data: errorData, encoding: .utf8) ?? "")")
        }
        print("【Process终止】Exit Code: \(xattrProcess.terminationStatus)")
    }

    /// 已在后台队列。权限不够时用 chmod 补上，再交给 wine64。
    private static func grantExecutePermission(_ wine64Path: String) -> String? {
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", wine64Path]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        chmod.standardOutput = outputPipe
        chmod.standardError = errorPipe
        do {
            try chmod.run()
        } catch {
            return "chmod +x 失败：\(error.localizedDescription)"
        }
        chmod.waitUntilExit()
        guard chmod.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return "chmod +x 失败（\(chmod.terminationStatus)）：\(text)"
        }
        return nil
    }

    /// 目录还是空的才需要 wineboot。注册表、时间戳或上次成功标记都算已初始化，不再要求某个 DLL。
    private static func prefixIsInitialized(_ root: URL) -> Bool {
        guard prefixDirectoryExists(root) else { return false }
        let markers = [
            "system.reg",
            "user.reg",
            "userdef.reg",
            ".update-timestamp",
            ".vesta-wineboot-ok",
            "drive_c/windows/system32/ntdll.dll",
            "drive_c/windows/system32/kernel32.dll"
        ]
        return markers.contains {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    private static func prefixDirectoryExists(_ root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// wineboot 退出码为 0 后记下成功，下次启动不再因为缺少某个文件而重判失败。
    private static func markPrefixReady(_ root: URL) {
        let marker = root.appendingPathComponent(".vesta-wineboot-ok")
        do {
            try Data("ok".utf8).write(to: marker, options: .atomic)
        } catch {
            print("【Wine 初始化】无法写入成功标记：\(marker.path) \(error.localizedDescription)")
        }
    }

    /// Whisky、CrossOver 里已经有注册表的瓶子，也视为成熟容器。
    private static func matureEnginePrefixExists() -> Bool {
        let home = NSHomeDirectory()
        let roots = [
            home + "/Library/Containers/com.isaacmarovitz.Whisky/Data/Library/Application Support/Whisky/Bottles",
            home + "/Library/Application Support/Whisky/Bottles",
            home + "/Library/Application Support/com.isaacmarovitz.Whisky/Bottles",
            home + "/Library/Application Support/CrossOver/Bottles"
        ]
        for root in roots {
            let url = URL(fileURLWithPath: root, isDirectory: true)
            guard prefixDirectoryExists(url) else { continue }
            if prefixLooksReady(url) {
                print("【Wine 初始化】成熟容器：\(url.path)")
                return true
            }
            do {
                let children = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                for child in children where prefixLooksReady(child) {
                    print("【Wine 初始化】成熟容器：\(child.path)")
                    return true
                }
            } catch {
                print("【Wine 初始化】无法读取容器目录：\(root) \(error.localizedDescription)")
            }
        }
        return false
    }

    private static func prefixLooksReady(_ root: URL) -> Bool {
        let markers = ["system.reg", "user.reg", ".update-timestamp"]
        return markers.contains {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    /// 已在后台队列。目录不存在或还没初始化时，先跑完 `wine64 wineboot`，退出码为 0 才继续启动 exe。
    private static func bootstrapPrefixIfNeeded(wine64: URL, prefix: URL, pathEnvironment: String, libraryPath: String?) -> String? {
        if prefixIsInitialized(prefix) {
            print("【Wine 初始化】容器已就绪：\(prefix.path)")
            return nil
        }
        print("【Wine 初始化】WINEPREFIX 不存在或未初始化，执行 wineboot：\(prefix.path)")
        if !FileManager.default.fileExists(atPath: prefix.path) {
            do {
                try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            } catch {
                return "无法创建 WINEPREFIX：\(prefix.path)。\(error.localizedDescription)"
            }
        }
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path
        environment["WINEDEBUG"] = "-all"
        environment["WINEARCH"] = "win64"
        environment["PATH"] = pathEnvironment
        environment["WINEDLLOVERRIDES"] = "mscoree,mshtml="
        if let libraryPath, !libraryPath.isEmpty {
            environment["DYLD_FALLBACK_LIBRARY_PATH"] = libraryPath
        }
        let command = wineCommand(wine64: wine64, arguments: ["wineboot"])
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = environment
        process.currentDirectoryURL = prefix
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let captured = PipeCapture()
        captured.start(outputPipe, isError: false)
        captured.start(errorPipe, isError: true)
        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            print("【Process终止】Exit Code: \(process.terminationStatus)")
        }
        do {
            try process.run()
        } catch {
            print("【Wine严重报错】: \(error.localizedDescription)")
            return "wineboot 无法启动：\(error.localizedDescription)"
        }
        process.waitUntilExit()
        captured.drain(outputPipe, isError: false)
        captured.drain(errorPipe, isError: true)
        let status = process.terminationStatus
        if status == 0, prefixDirectoryExists(prefix) {
            markPrefixReady(prefix)
            print("【Wine 初始化】wineboot 完成：\(prefix.path)")
            return nil
        }
        if matureEnginePrefixExists() {
            if prefixDirectoryExists(prefix) {
                markPrefixReady(prefix)
            }
            print("【Wine 初始化】已有成熟容器，继续启动：\(prefix.path)")
            return nil
        }
        return "wineboot 初始化失败。\(exitSummary(status: Int(status), log: captured.errorLog()))"
    }

    static func exitSummary(status: Int, log: String) -> String {
        let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped: String
        if trimmed.isEmpty || trimmed == "(empty)" {
            clipped = ""
        } else if trimmed.count > 600 {
            clipped = String(trimmed.prefix(600)) + "…"
        } else {
            clipped = trimmed
        }
        if clipped.isEmpty {
            return "Exit Code: \(status)"
        }
        return "Exit Code: \(status)\n\(clipped)"
    }

    /// wine64 本身放在 executableURL。参数数组只放 exe 路径，空格保留在同一个元素里，不经过 shell。
    private static func wineArguments(request: LaunchRequest, executable: URL, exePath: String) -> [String] {
        var arguments = processArguments(request: request, path: exePath, leading: [])
        if arguments.first == executable.path {
            arguments.removeFirst()
        }
        arguments = arguments.map { argument in
            var value = argument
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        if exePath.contains(" ") {
            print("【Wine 参数】exe 路径含空格，已作为单个数组参数传递：\(exePath)")
        }
        if request.usesVirtualDesktop {
            arguments.insert("/desktop=Vesta,1920x1080", at: 0)
            arguments.insert("explorer", at: 0)
            print("【Wine 参数】虚拟桌面 1920x1080")
        }
        return arguments
    }

    /// x86_64 的 Whisky Wine 11 自带 lib，直接执行才能把库路径传进去，并由系统用 Rosetta 跑。
    /// 没有配套 lib 的纯 x86_64 加载器才会走 arch，避免旧预加载器的内存映射失败。
    private static func wineCommand(wine64: URL, arguments: [String]) -> (executable: URL, arguments: [String]) {
        let slices = machoSlices(at: wine64.path)
        let appleSilicon = hostIsAppleSilicon()
        print("【Wine 架构】appleSilicon=\(appleSilicon) arm64=\(slices.arm64) x86_64=\(slices.x86_64)")
        if appleSilicon, slices.x86_64, !slices.arm64, wineLibraryPath(wine64) == nil {
            print("【Wine 架构】使用 arch -x86_64 启动 \(wine64.path)")
            return (URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", wine64.path] + arguments)
        }
        if appleSilicon, slices.x86_64, !slices.arm64 {
            print("【Wine 架构】直接执行 wine64，由 Rosetta 加载 \(wine64.path)")
        }
        return (wine64, arguments)
    }

    private static func wineLibraryPath(_ wine: URL) -> String? {
        let libraries = wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib").path
        guard FileManager.default.fileExists(atPath: libraries) else { return nil }
        return libraries
    }

    /// 安装结束后在后台初始化 Vesta 容器。wineboot 退出码为 0 且目录存在即成功，随后由启动流程直接运行 exe。
    static func initializePrefix(wine64: URL) -> String? {
        let root = BottleActions.prepareVestaPrefix()
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let pathEnvironment = wine64.deletingLastPathComponent().path + ":" + currentPath
        return bootstrapPrefixIfNeeded(
            wine64: wine64,
            prefix: root,
            pathEnvironment: pathEnvironment,
            libraryPath: wineLibraryPath(wine64)
        )
    }

    private static func hostIsAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }

    private static func machoSlices(at path: String) -> (arm64: Bool, x86_64: Bool) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return (false, false)
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 512)
        guard data.count >= 8 else { return (false, false) }
        let magic = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        if magic == 0xFEEDFACF || magic == 0xCFFAEDFE {
            let cpu = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
            let native = magic == 0xFEEDFACF ? cpu : cpu.byteSwapped
            return (native == 0x0100000C, native == 0x01000007)
        }
        let fatMagic = magic.byteSwapped
        guard magic == 0xBEBAFECA || fatMagic == 0xCAFEBABE else { return (false, false) }
        let count = UInt32(bigEndian: data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) })
        var arm64 = false
        var x86 = false
        let slices = min(Int(count), 8)
        for index in 0..<slices {
            let start = 8 + index * 20
            let end = start + 4
            guard data.count >= end else { break }
            let cpu = UInt32(bigEndian: data.subdata(in: start..<end).withUnsafeBytes { $0.load(as: UInt32.self) })
            if cpu == 0x0100000C { arm64 = true }
            if cpu == 0x01000007 { x86 = true }
        }
        return (arm64, x86)
    }

    /// 直接运行时不附带 steam://，避免 Wine 把协议交给 Steam 界面。
    private static func processArguments(request: LaunchRequest, path: String, leading: [String]) -> [String] {
        let extras = request.directExecutable
            ? request.extraArguments.filter { !$0.lowercased().hasPrefix("steam:") }
            : request.extraArguments
        return leading + [path] + extras
    }

    /// DXVK 对 Wine Stable 同样有效。D3DMetal 和 MetalFX 只有 CrossOver 认识，不传给 wine64。
    private static func graphicsEnvironment(_ request: LaunchRequest, host: HostEngine) -> [String: String] {
        guard LicenseGate.shared.allowsAdvanced() else {
            print("【授权】试用已结束，已跳过 DXVK / MetalFX / ESync / FSync")
            return [:]
        }
        var environment: [String: String] = [:]
        if request.enablesDXVK {
            environment["WINEDLLOVERRIDES"] = "d3d11,d3d10core,d3d9,dxgi=n"
            environment["DXVK_STATE_CACHE"] = "1"
            environment["DXVK_STATE_CACHE_PATH"] = ShaderCache.dxvkDirectory(create: true).path
        }
        if host == .crossover, request.enablesMetal3 {
            environment["CX_GRAPHICS"] = "d3dmetal"
            if request.enablesMetalFX, MetalFXSupport.available {
                environment["D3DM_ENABLE_METALFX"] = "1"
            }
        }
        let fsync = request.enablesFsync && WineSyncProbe.supportsFsync()
        if fsync {
            environment["WINEFSYNC"] = "1"
        } else if request.enablesEsync || request.enablesFsync {
            environment["WINEESYNC"] = "1"
            environment["WINEMSYNC"] = "1"
        }
        if request.enablesDXVK || request.enablesEsync || request.enablesFsync {
            environment["WINE_LARGE_ADDRESS_AWARE"] = "1"
        }
        print("【Wine 调优】MetalFX=\(environment["D3DM_ENABLE_METALFX"] == "1") FSync=\(fsync) ESync=\(environment["WINEESYNC"] == "1") MSync=\(environment["WINEMSYNC"] == "1")")
        return environment
    }

    @MainActor
    private static func openMacApp(_ url: URL) async -> LaunchResult {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            let running = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            log("NSWorkspace 已打开 \(url.path)，pid=\(running.processIdentifier)")
            return LaunchResult(succeeded: true, message: L10n.string(.localOpened, language: L10n.savedLanguage()))
        } catch {
            return failure(L10n.format(.openFailed, L10n.savedLanguage(), error.localizedDescription))
        }
    }

    private static func makeProcess(
        executable: URL,
        arguments: [String],
        environment extra: [String: String],
        directory: URL?
    ) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in extra {
            environment[key] = value
        }
        process.environment = environment
        process.currentDirectoryURL = directory ?? executable.deletingLastPathComponent()
        process.qualityOfService = .userInitiated
        return process
    }

    /// 记下 PID。进程结束时通知界面从「运行中」改为「已退出」。
    private static func watch(_ process: Process, appID: UUID) {
        process.terminationHandler = { process in
            print("【Process终止】Exit Code: \(process.terminationStatus)")
            let elapsed = LaunchSessionStore.shared.remove(process, for: appID)
            guard elapsed.removed else { return }
            let status = Int(process.terminationStatus)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .windowsAppDidExit,
                    object: nil,
                    userInfo: ["id": appID, "status": status, "elapsed": elapsed.seconds]
                )
            }
        }
        LaunchSessionStore.shared.store(process, for: appID)
    }

    private static func start(
        executable: URL,
        arguments: [String],
        environment extra: [String: String],
        appID: UUID,
        playtimeKey: String = "",
        engine: String,
        successMessage: String = "",
        directory: URL? = nil
    ) -> LaunchResult {
        let process = makeProcess(executable: executable, arguments: arguments, environment: extra, directory: directory)

        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        let captured = PipeCapture()
        captured.start(output, isError: false)
        captured.start(errorPipe, isError: true)
        process.terminationHandler = { process in
            output.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            captured.drain(output, isError: false)
            captured.drain(errorPipe, isError: true)
            print("【Process终止】Exit Code: \(process.terminationStatus)")
            let stderrString = captured.errorLog()
            let elapsed = LaunchSessionStore.shared.remove(process, for: appID)
            guard elapsed.removed else { return }
            let status = Int(process.terminationStatus)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .windowsAppDidExit,
                    object: nil,
                    userInfo: ["id": appID, "status": status, "log": stderrString, "elapsed": elapsed.seconds]
                )
            }
        }

        LaunchSessionStore.shared.store(process, for: appID, playtimeKey: playtimeKey)
        do {
            try process.run()
        } catch {
            _ = LaunchSessionStore.shared.remove(process, for: appID)
            var stderrString = error.localizedDescription
            if !FileManager.default.fileExists(atPath: executable.path) {
                stderrString = "wine 路径不存在：\(executable.path)。\(stderrString)"
            } else if !FileManager.default.isExecutableFile(atPath: executable.path) {
                stderrString = "wine 没有执行权限：\(executable.path)。\(stderrString)"
            }
            let prefix = extra["WINEPREFIX"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if prefix.isEmpty {
                stderrString = "WINEPREFIX 缺失。\(stderrString)"
            }
            print("【Process终止】Exit Code: -1")
            print("【Wine严重报错】: \(stderrString)")
            return failure(stderrString)
        }

        log("\(engine) 已启动 pid=\(process.processIdentifier)")
        log("executableURL：\(executable.path)")
        for (index, argument) in arguments.enumerated() {
            log("arguments[\(index)]：\(argument)")
        }
        if process.isRunning {
            return LaunchResult(
                succeeded: true,
                message: successMessage.isEmpty ? L10n.format(.launchedVia, L10n.savedLanguage(), engine) : successMessage
            )
        }
        output.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        captured.drain(output, isError: false)
        captured.drain(errorPipe, isError: true)
        let status = process.terminationStatus
        let stderrString = captured.errorLog()
        print("【Process终止】Exit Code: \(status)")
        return failure(exitSummary(status: Int(status), log: stderrString))
    }

    private static func whiskyBottle(_ bottle: URL, matches name: String) -> Bool {
        if bottle.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        for fileName in ["Metadata.plist", "Bottle.plist"] {
            let url = bottle.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            for key in ["name", "Name", "bottleName"] {
                if let value = object[key] as? String, value.caseInsensitiveCompare(name) == .orderedSame {
                    return true
                }
            }
        }
        return false
    }

    static func looksLikeWindowsPath(_ path: String) -> Bool {
        if path.contains("\\") { return true }
        guard let colon = path.firstIndex(of: ":") else { return false }
        return path.distance(from: path.startIndex, to: colon) == 1
    }

    /// `C:\Program Files\App\app.exe` 变成容器 C 盘下的相对路径。
    private static func windowsRelativePath(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
        if looksLikeWindowsPath(path), let colon = value.firstIndex(of: ":") {
            value = String(value[value.index(after: colon)...])
        }
        while value.hasPrefix("/") {
            value.removeFirst()
        }
        return value
    }

    private static func bottleDriveRoots(named name: String) -> [URL] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = NSHomeDirectory()
        var roots: [URL] = []

        func append(bottle: URL) {
            let drive = bottle.lastPathComponent == "drive_c" ? bottle : bottle.appendingPathComponent("drive_c")
            if !roots.contains(drive) {
                roots.append(drive)
            }
        }

        let crossover = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        let local = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/MyApp/Bottles")
        for root in [crossover, local] {
            guard let bottles = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else { continue }
            let matched = bottles.filter {
                $0.lastPathComponent.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            let ordered = matched + bottles.filter { bottle in
                !matched.contains(bottle)
            }
            for bottle in ordered {
                append(bottle: bottle)
            }
        }
        return roots
    }

    private static func isWindowsProgram(_ path: String) -> Bool {
        if path.contains("\\") {
            return true
        }
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["exe", "bat", "cmd", "msi"].contains(ext)
    }

    private static func failure(_ message: String) -> LaunchResult {
        log(message)
        return LaunchResult(succeeded: false, message: message)
    }

    private static func log(_ message: String) {
        print("\(logPrefix) \(message)")
    }
}

/// 把 Wine 的 stdout / stderr 原样打到 Xcode 控制台。读的时候不阻塞，避免管道被写满后进程卡住。
nonisolated private final class PipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""

    func start(_ pipe: Pipe, isError: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if isError {
                print("【Wine严重报错】: \(String(data: data, encoding: .utf8) ?? "")")
            } else {
                print("【Wine标准输出】: \(String(data: data, encoding: .utf8) ?? "")")
            }
            self?.add(String(decoding: data, as: UTF8.self), isError: isError)
        }
    }

    func drain(_ pipe: Pipe, isError: Bool) {
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0 else { return }
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        while true {
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            let data = Data(buffer.prefix(count))
            if isError {
                print("【Wine严重报错】: \(String(data: data, encoding: .utf8) ?? "")")
            } else {
                print("【Wine标准输出】: \(String(data: data, encoding: .utf8) ?? "")")
            }
            add(String(decoding: data, as: UTF8.self), isError: isError)
        }
    }

    func stderrText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// stderr 优先。Wine 有时把 “cannot find” 写到 stdout，所以空的 stderr 会带上 stdout。
    func errorLog() -> String {
        lock.lock()
        defer { lock.unlock() }
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if err.isEmpty, out.isEmpty { return "(empty)" }
        if out.isEmpty { return err }
        if err.isEmpty { return out }
        return "\(err)\n\(out)"
    }

    private func add(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        lock.lock()
        if isError {
            stderr += text
        } else {
            stdout += text
        }
        lock.unlock()
    }
}

/// Process 不能放进 SwiftUI 模型，单独按应用 id 记下，停止时再取回。
nonisolated final class LaunchSessionStore: @unchecked Sendable {
    static let shared = LaunchSessionStore()

    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]
    private var started: [UUID: Date] = [:]
    private var keys: [UUID: String] = [:]
    private var pending: Set<UUID> = []

    func store(_ process: Process, for id: UUID, playtimeKey: String = "") {
        lock.lock()
        processes[id] = process
        started[id] = Date()
        if !playtimeKey.isEmpty {
            keys[id] = playtimeKey
        }
        lock.unlock()
    }

    func remove(_ id: UUID) {
        lock.lock()
        processes[id] = nil
        started[id] = nil
        keys[id] = nil
        lock.unlock()
    }

    /// 应用退出、进程即将被清掉时，把还没结算的游玩秒数交出去。
    func consumeOpenPlaytime() -> [String: TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        var totals: [String: TimeInterval] = [:]
        let now = Date()
        for (id, start) in started {
            let key = keys[id] ?? ""
            guard !key.isEmpty else { continue }
            let seconds = max(0, now.timeIntervalSince(start))
            if seconds > 0 {
                totals[key, default: 0] += seconds
            }
        }
        started.removeAll()
        processes.removeAll()
        keys.removeAll()
        return totals
    }

    /// 只清掉仍然登记的那一个进程，避免旧进程的退出回调把后启动的进程清掉。
    func remove(_ process: Process, for id: UUID) -> (removed: Bool, seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard processes[id] === process else { return (false, 0) }
        processes[id] = nil
        keys[id] = nil
        let seconds = started.removeValue(forKey: id).map { max(0, Date().timeIntervalSince($0)) } ?? 0
        return (true, seconds)
    }

    func isRunning(_ id: UUID) -> Bool {
        trackedIsRunning(id) == true
    }

    /// 没有由本程序拉起的进程时返回 nil，避免把系统打开的应用误判成已退出。
    func trackedIsRunning(_ id: UUID) -> Bool? {
        lock.lock()
        let process = processes[id]
        lock.unlock()
        guard let process else { return nil }
        return process.isRunning
    }

    func terminate(_ id: UUID) -> Bool {
        lock.lock()
        let process = processes[id]
        lock.unlock()
        guard let process, process.isRunning else { return false }
        process.terminate()
        return true
    }

    /// 同一次点击只允许进入一次启动。进程还在，或上一次点击尚未结束时返回 false。
    func claimLaunch(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pending.contains(id) || processes[id] != nil {
            return false
        }
        pending.insert(id)
        return true
    }

    func endLaunchClaim(_ id: UUID) {
        lock.lock()
        pending.remove(id)
        lock.unlock()
    }

    func runningProcessIDs() -> [Int32] {
        lock.lock()
        let active = processes.values.filter(\.isRunning).map(\.processIdentifier)
        lock.unlock()
        return active
    }
}
