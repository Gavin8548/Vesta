//
//  BottleActions.swift
//
//  容器由 Vesta 建在 Application Support 里，不使用 Whisky 的瓶子目录。
//  打开 C 盘仍走 Finder；命令行使用本机的 wine。
//

import AppKit

nonisolated enum ContainerState: Equatable {
    case ready(URL)
    case incomplete(URL)
    case missing
}

enum BottleActions {
    /// 优先打开 Vesta 自己的容器 C 盘。
    static func openCDrive(named name: String) -> String {
        let url = cDriveURL(named: name, createIfNeeded: true)
        let parent = url.deletingLastPathComponent().path
        let selected = NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: parent)
        print("[Bottle] 在 Finder 中打开 C 盘：\(url.path) selected=\(selected)")
        return selected ? L10n.string(.finderOpened, language: L10n.savedLanguage()) : L10n.string(.finderFailed, language: L10n.savedLanguage())
    }

    /// 在「终端」里执行 `wine cmd`，工作目录前缀是该容器。
    static func runWineConsole(named name: String, enablesDXVK: Bool) -> String {
        guard let wine = wineExecutable() else {
            print("[Bottle] 没有 wine64，静默跳过命令行")
            return ""
        }

        let prefix = cDriveURL(named: name, createIfNeeded: true).deletingLastPathComponent()
        var command = "export WINEPREFIX='\(prefix.path)'"
        if enablesDXVK {
            command += "; export WINEDLLOVERRIDES='d3d11,d3d10core,d3d9,dxgi=n'"
        }
        command += "; exec '\(wine.path)' cmd"

        if let error = openTerminal(command: command) {
            print("[Bottle] 终端打开失败：\(error)")
            return L10n.format(.terminalFailed, L10n.savedLanguage(), "\(error)")
        }
        print("[Bottle] 已运行 Wine 命令行：\(command)")
        return L10n.string(.wineConsoleOpened, language: L10n.savedLanguage())
    }

    /// 容器放在用户选定的目录。没有选过时，用桌面上的 VestaContainer。
    @discardableResult
    nonisolated static func prepareVestaPrefix() -> URL {
        let root = WinePrefixStore.resolve()
        prepareContents(of: root)
        print("[Bottle] Vesta WinePrefix：\(root.path)")
        return root
    }

    /// 在 Application Support 里建好标准 Wine 前缀，并返回瓶子根目录。
    @discardableResult
    nonisolated static func prepareLocalPrefix(named name: String) -> URL {
        let token = safeName(name)
        let root = localBottlesRoot().appendingPathComponent(token, isDirectory: true)
        prepareContents(of: root)
        print("[Bottle] 本地 Wine 容器：\(root.path)")
        return root
    }

    private nonisolated static func prepareContents(of root: URL) {
        let drive = root.appendingPathComponent("drive_c", isDirectory: true)
        let user = userFolderName()
        let folders = [
            "Program Files",
            "Program Files (x86)",
            "windows/system32",
            "windows/syswow64",
            "windows/fonts",
            "users/Public",
            "users/\(user)"
        ]
        for folder in folders {
            let url = drive.appendingPathComponent(folder, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                print("【WinePrefix】创建失败：\(url.path) \(error.localizedDescription)")
            }
        }
        let devices = root.appendingPathComponent("dosdevices", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)
        } catch {
            print("【WinePrefix】创建失败：\(devices.path) \(error.localizedDescription)")
        }
        link(devices.appendingPathComponent("c:"), to: drive)
        link(devices.appendingPathComponent("z:"), to: URL(fileURLWithPath: "/", isDirectory: true))
    }

    /// 把选中的 exe 复制到指定容器的 C 盘，并返回 Wine 使用的 Windows 路径。
    nonisolated static func installImportedExecutable(from source: URL, prefix: URL) throws -> String {
        let drive = prefix.appendingPathComponent("drive_c", isDirectory: true)
        return try installImportedExecutable(from: source, drive: drive)
    }

    /// 把选中的 exe 复制到该容器的 C 盘，并返回 Wine 使用的 Windows 路径。
    nonisolated static func installImportedExecutable(from source: URL, bottleName: String) throws -> String {
        let trimmed = bottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let drive = cDriveURL(named: trimmed.isEmpty ? "Bottle" : trimmed, createIfNeeded: true)
        return try installImportedExecutable(from: source, drive: drive)
    }

    private nonisolated static func installImportedExecutable(from source: URL, drive: URL) throws -> String {
        let folderName = safeName(source.deletingPathExtension().lastPathComponent)
        let fileName = source.lastPathComponent
        let folder = drive
            .appendingPathComponent("Program Files", isDirectory: true)
            .appendingPathComponent("Vesta Imports", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        print("[Bottle] 已复制到容器：\(destination.path)")
        return "C:\\Program Files\\Vesta Imports\\\(folderName)\\\(fileName)"
    }

    /// 启动时使用的瓶子根目录，和上面复制文件的 C 盘是同一个容器。
    nonisolated static func prefix(named name: String) -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cDriveURL(named: trimmed.isEmpty ? "Bottle" : trimmed, createIfNeeded: true)
            .deletingLastPathComponent()
    }

    /// 不创建目录。drive_c 在才算可用；瓶子在但没有 C 盘则视为丢失。
    nonisolated static func containerState(named name: String) -> ContainerState {
        let token = safeName(name)
        if let root = existingBottleRoot(named: token) {
            let drive = root.appendingPathComponent("drive_c")
            if FileManager.default.fileExists(atPath: drive.path) {
                return .ready(root)
            }
            return .incomplete(root)
        }
        return .missing
    }

    /// 在已有瓶子里补上 C 盘；没有瓶子时，在 Vesta 自己的目录里新建一个。
    @discardableResult
    nonisolated static func rebuildContainer(named name: String) -> URL {
        let root = prepareLocalPrefix(named: name)
        print("[Bottle] 已准备本地容器：\(root.path)")
        return root
    }

    private nonisolated static func existingBottleRoot(named name: String) -> URL? {
        let root = localBottlesRoot().appendingPathComponent(safeName(name), isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        return root
    }

    private nonisolated static func localBottlesRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyApp/Bottles", isDirectory: true)
    }

    private nonisolated static func userFolderName() -> String {
        let raw = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = raw.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "Public" : cleaned
    }

    private nonisolated static func link(_ link: URL, to destination: URL) {
        if FileManager.default.fileExists(atPath: link.path) { return }
        do {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        } catch {
            print("【WinePrefix】无法建立盘符链接：\(link.path) \(error.localizedDescription)")
        }
    }

    private nonisolated static func cDriveURL(named name: String, createIfNeeded: Bool) -> URL {
        if createIfNeeded {
            return prepareLocalPrefix(named: name).appendingPathComponent("drive_c")
        }
        return localCDrive(named: safeName(name))
    }

    private nonisolated static func localCDrive(named name: String) -> URL {
        let root = localBottlesRoot().appendingPathComponent(safeName(name), isDirectory: true)
        return root.appendingPathComponent("drive_c")
    }

    private nonisolated static func safeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "Bottle" : cleaned
    }

    private static func wineExecutable() -> URL? {
        return HostEngine.standardWineBinary()
    }

    private static func openTerminal(command: String) -> String? {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\" to activate\ntell application \"Terminal\" to do script \"\(escaped)\""
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error?[NSAppleScript.errorMessage] as? String
    }
}

/// 记住 Wine 容器的绝对路径。默认是桌面上的 VestaContainer。
nonisolated enum WinePrefixStore {
    static let defaultsKey = "WinePrefixPath"

    static var desktopDefault: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/VestaContainer", isDirectory: true)
    }

    /// 每次启动 exe 都走这里：读已保存路径，没有就用桌面，目录不存在就创建。
    static func resolve() -> URL {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = saved.isEmpty ? desktopDefault.path : (saved as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                print("【WinePrefix】已创建：\(url.path)")
            } catch {
                print("【WinePrefix】创建失败：\(url.path) \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        print("【WinePrefix】当前路径：\(url.path)")
        return url
    }

    static func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                print("【WinePrefix】创建失败：\(path) \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(path, forKey: defaultsKey)
        print("成功保存 WinePrefix 路径: \(path)")
    }

    @MainActor
    static func chooseWithPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择容器位置"
        panel.message = "可以选择桌面、文稿或任意文件夹，作为 Wine 容器。"
        panel.prompt = "使用此位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        remember(url)
        return url.standardizedFileURL
    }
}
