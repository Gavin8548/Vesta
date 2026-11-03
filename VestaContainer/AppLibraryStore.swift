//
//  AppLibraryStore.swift
//
//  把用户导入的程序写到 Application Support，启动时再读回来。
//  游玩时长和导入记录放在同一个 apps.json 里。
//

import AppKit
import Foundation

extension WindowsApp {
    /// 导入项用固定 id。目录里的示例用名称或 Steam 编号，避免每次启动换 id 后时长对不上。
    var playtimeKey: String {
        if isUserImported {
            return "import:" + id.uuidString
        }
        let steam = steamAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !steam.isEmpty {
            return "steam:" + steam
        }
        return "name:" + name
    }

    func playtimeTitle(language: AppLanguage) -> String {
        if playtimeSeconds >= 3600 {
            return L10n.format(.playtimeHours, language, playtimeSeconds / 3600)
        }
        let minutes = Int((playtimeSeconds / 60).rounded(.down))
        let shown = playtimeSeconds > 0 && minutes == 0 ? 1 : minutes
        return L10n.format(.playtimeMinutes, language, shown)
    }
}

@MainActor
enum AppLibraryStore {
    private struct CatalogRecord: Codable {
        var category: String
        var tags: [String]
        var iconURL: String
        var bannerImageURL: String
        var downloadURL: String
        var ambientStyle: String
        var isFavorite: Bool
        var boundInstallPath: String

        init(category: String, tags: [String], iconURL: String, bannerImageURL: String, downloadURL: String, ambientStyle: String, isFavorite: Bool, boundInstallPath: String) {
            self.category = category
            self.tags = tags
            self.iconURL = iconURL
            self.bannerImageURL = bannerImageURL
            self.downloadURL = downloadURL
            self.ambientStyle = ambientStyle
            self.isFavorite = isFavorite
            self.boundInstallPath = boundInstallPath
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL) ?? ""
            bannerImageURL = try container.decodeIfPresent(String.self, forKey: .bannerImageURL) ?? ""
            downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL) ?? ""
            ambientStyle = try container.decodeIfPresent(String.self, forKey: .ambientStyle) ?? ""
            isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
            boundInstallPath = try container.decodeIfPresent(String.self, forKey: .boundInstallPath) ?? ""
        }
    }

    private struct Payload: Codable {
        var apps: [StoredApp]
        var catalogPlaytime: [String: Double]
        var catalogDownloads: [String: String]
        var catalogRecords: [String: CatalogRecord]

        init(apps: [StoredApp], catalogPlaytime: [String: Double], catalogDownloads: [String: String], catalogRecords: [String: CatalogRecord]) {
            self.apps = apps
            self.catalogPlaytime = catalogPlaytime
            self.catalogDownloads = catalogDownloads
            self.catalogRecords = catalogRecords
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            apps = try container.decodeIfPresent([StoredApp].self, forKey: .apps) ?? []
            catalogPlaytime = try container.decodeIfPresent([String: Double].self, forKey: .catalogPlaytime) ?? [:]
            catalogDownloads = try container.decodeIfPresent([String: String].self, forKey: .catalogDownloads) ?? [:]
            catalogRecords = try container.decodeIfPresent([String: CatalogRecord].self, forKey: .catalogRecords) ?? [:]
        }
    }

    private struct StoredApp: Codable {
        var id: UUID
        var name: String
        var absolutePath: String
        var installPath: String
        var bottleName: String?
        var bookmark: Data?
        var iconPath: String?
        var playtimeSeconds: Double
        var publisher: String
        var summary: String
        var symbolName: String
        var tint: String
        var downloadURL: String?
        var isFavorite: Bool
        var platform: String
        var kind: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            absolutePath = try container.decodeIfPresent(String.self, forKey: .absolutePath) ?? ""
            installPath = try container.decodeIfPresent(String.self, forKey: .installPath) ?? ""
            bottleName = try container.decodeIfPresent(String.self, forKey: .bottleName)
            bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
            iconPath = try container.decodeIfPresent(String.self, forKey: .iconPath)
            playtimeSeconds = try container.decodeIfPresent(Double.self, forKey: .playtimeSeconds) ?? 0
            publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "app.fill"
            tint = try container.decodeIfPresent(String.self, forKey: .tint) ?? "blue"
            downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
            isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
            platform = try container.decodeIfPresent(String.self, forKey: .platform) ?? ""
            kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        }

        init(
            id: UUID,
            name: String,
            absolutePath: String,
            installPath: String,
            bottleName: String?,
            bookmark: Data?,
            iconPath: String?,
            playtimeSeconds: Double,
            publisher: String,
            summary: String,
            symbolName: String,
            tint: String,
            downloadURL: String?,
            isFavorite: Bool,
            platform: String,
            kind: String
        ) {
            self.id = id
            self.name = name
            self.absolutePath = absolutePath
            self.installPath = installPath
            self.bottleName = bottleName
            self.bookmark = bookmark
            self.iconPath = iconPath
            self.playtimeSeconds = playtimeSeconds
            self.publisher = publisher
            self.summary = summary
            self.symbolName = symbolName
            self.tint = tint
            self.downloadURL = downloadURL
            self.isFavorite = isFavorite
            self.platform = platform
            self.kind = kind
        }
    }

    static func load(into programs: inout [WindowsApp]) {
        let payload = read()
        let imported = payload.apps.map(makeApp)
        let importedPaths = Set(imported.map(\.absolutePath).filter { !$0.isEmpty })
        var catalog = programs.filter { app in
            !app.isUserImported && !importedPaths.contains(app.absolutePath)
        }
        for index in catalog.indices {
            if let seconds = payload.catalogPlaytime[catalog[index].playtimeKey] {
                catalog[index].playtimeSeconds = seconds
            }
            if let link = payload.catalogDownloads[catalog[index].playtimeKey], !link.isEmpty {
                catalog[index].downloadURL = link
            }
            applyRecord(payload.catalogRecords[catalog[index].playtimeKey], to: &catalog[index])
        }
        programs = imported + catalog
    }

    /// 退出时游戏还在跑，把这一段时长加进已经保存的记录，避免进程被清掉后时长丢掉。
    static func creditPlaytime(_ additions: [String: TimeInterval]) {
        let useful = additions.filter { $0.value > 0 }
        guard !useful.isEmpty else { return }
        var payload = read()
        for (key, seconds) in useful {
            if key.hasPrefix("import:"), let id = UUID(uuidString: String(key.dropFirst("import:".count))),
               let index = payload.apps.firstIndex(where: { $0.id == id }) {
                payload.apps[index].playtimeSeconds += seconds
            } else {
                payload.catalogPlaytime[key, default: 0] += seconds
            }
        }
        write(payload)
    }

    static func save(_ programs: [WindowsApp]) {
        var apps: [StoredApp] = []
        var catalog: [String: Double] = [:]
        var downloads: [String: String] = [:]
        var records: [String: CatalogRecord] = [:]
        for program in programs {
            let link = program.downloadURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if program.isUserImported {
                apps.append(stored(program))
            } else {
                if program.playtimeSeconds > 0 {
                    catalog[program.playtimeKey] = program.playtimeSeconds
                }
                if !link.isEmpty {
                    downloads[program.playtimeKey] = link
                }
                records[program.playtimeKey] = record(for: program, link: link)
            }
        }
        write(Payload(apps: apps, catalogPlaytime: catalog, catalogDownloads: downloads, catalogRecords: records))
    }

    private static func write(_ payload: Payload) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let plain = try JSONEncoder().encode(payload)
            guard let sealed = LibraryVault.seal(plain) else {
                print("[Library] 加密失败，没有写入 apps.json")
                VestaNotice.show(
                    title: L10n.string(.problemTitle, language: L10n.savedLanguage()),
                    message: L10n.string(.libraryTampered, language: L10n.savedLanguage())
                )
                return
            }
            try sealed.write(to: fileURL, options: .atomic)
        } catch {
            print("[Library] 保存 apps.json 失败：\(error.localizedDescription)")
            VestaNotice.show(
                title: L10n.string(.problemTitle, language: L10n.savedLanguage()),
                message: L10n.string(.libraryTampered, language: L10n.savedLanguage())
            )
        }
    }

    /// 把 apps.json、图标和本机读取配置打成一个 zip。
    static func exportLibraryBackup(to destination: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("VestaLibraryBackup-\(UUID().uuidString)", isDirectory: true)
        let root = staging.appendingPathComponent("VestaLibrary", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try exportLibraryFolder(to: root)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try runDitto(["-c", "-k", "--keepParent", root.path, destination.path])
    }

    /// 把游戏库文件写进一个文件夹，供 zip 和整包备份共用。
    nonisolated static func exportLibraryFolder(to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try copyIfExists(fileURL, to: root.appendingPathComponent("apps.json"))
        try copyIfExists(iconFolder, to: root.appendingPathComponent("Icons", isDirectory: true))
        try copyIfExists(folder.appendingPathComponent("library.key"), to: root.appendingPathComponent("library.key"))
        try copyIfExists(folder.appendingPathComponent("license.json"), to: root.appendingPathComponent("license.json"))
        let manifest: [String: String] = [
            "wineEnginePath": UserDefaults.standard.string(forKey: "WineEnginePath") ?? "",
            "winePrefixPath": UserDefaults.standard.string(forKey: "WinePrefixPath") ?? ""
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
        try manifestData.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// 用备份里的列表、时长和解密配置覆盖当前游戏库。
    static func restoreLibraryBackup(from archive: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("VestaLibraryRestore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try runDitto(["-x", "-k", archive.path, staging.path])
        guard let source = libraryRoot(in: staging) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try restoreLibraryFolder(at: source)
    }

    /// 用已经解压出来的 VestaLibrary 目录覆盖当前游戏库。
    nonisolated static func restoreLibraryFolder(at source: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let archivedApps = source.appendingPathComponent("apps.json")
        if FileManager.default.fileExists(atPath: archivedApps.path) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.copyItem(at: archivedApps, to: fileURL)
        }
        let archivedIcons = source.appendingPathComponent("Icons", isDirectory: true)
        if FileManager.default.fileExists(atPath: archivedIcons.path) {
            if FileManager.default.fileExists(atPath: iconFolder.path) {
                try FileManager.default.removeItem(at: iconFolder)
            }
            try FileManager.default.copyItem(at: archivedIcons, to: iconFolder)
        }
        try copyIfExists(source.appendingPathComponent("library.key"), to: folder.appendingPathComponent("library.key"))
        try copyIfExists(source.appendingPathComponent("license.json"), to: folder.appendingPathComponent("license.json"))
        applyManifest(source.appendingPathComponent("manifest.json"))
    }

    static func saveIcon(for file: URL, id: UUID) -> String? {
        let image = NSWorkspace.shared.icon(forFile: file.path)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: iconFolder, withIntermediateDirectories: true)
            let destination = iconFolder.appendingPathComponent(id.uuidString + ".png")
            try png.write(to: destination, options: .atomic)
            return destination.path
        } catch {
            print("[Library] 保存图标失败：\(error.localizedDescription)")
            return nil
        }
    }

    nonisolated private static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vesta", isDirectory: true)
    }

    nonisolated private static var fileURL: URL {
        folder.appendingPathComponent("apps.json")
    }

    nonisolated private static var iconFolder: URL {
        folder.appendingPathComponent("Icons", isDirectory: true)
    }

    nonisolated private static func copyIfExists(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func libraryRoot(in staging: URL) -> URL? {
        let named = staging.appendingPathComponent("VestaLibrary", isDirectory: true)
        if FileManager.default.fileExists(atPath: named.appendingPathComponent("apps.json").path)
            || FileManager.default.fileExists(atPath: named.appendingPathComponent("manifest.json").path) {
            return named
        }
        guard let children = try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) else {
            return nil
        }
        for child in children {
            let nested = child.appendingPathComponent("VestaLibrary", isDirectory: true)
            if FileManager.default.fileExists(atPath: nested.path) {
                return nested
            }
            if FileManager.default.fileExists(atPath: child.appendingPathComponent("apps.json").path) {
                return child
            }
        }
        return nil
    }

    nonisolated private static func applyManifest(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return
        }
        if let engine = object["wineEnginePath"], !engine.isEmpty {
            UserDefaults.standard.set(engine, forKey: "WineEnginePath")
        }
        if let prefix = object["winePrefixPath"], !prefix.isEmpty {
            UserDefaults.standard.set(prefix, forKey: "WinePrefixPath")
        }
    }

    private static func runDitto(_ arguments: [String]) throws {
        let executable = "/usr/bin/ditto"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if !errorText.isEmpty {
            print("[Library] \(errorText)")
        }
        print("[Library] ditto Exit Code: \(process.terminationStatus)")
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func read() -> Payload {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let missing = (error as NSError).code == NSFileReadNoSuchFileError
            if !missing {
                print("[Library] 读取 apps.json 失败：\(error.localizedDescription)")
            }
            return Payload(apps: [], catalogPlaytime: [:], catalogDownloads: [:], catalogRecords: [:])
        }
        let plain: Data
        if LibraryVault.isSealed(data) {
            if LibraryVault.existingKey() == nil {
                print("[Library] 加密库还没有本地密钥，启动时不弹钥匙串，也没有覆盖 apps.json")
                return Payload(apps: [], catalogPlaytime: [:], catalogDownloads: [:], catalogRecords: [:])
            }
            guard let opened = LibraryVault.open(data) else {
                quarantine(data)
                VestaNotice.show(
                    title: L10n.string(.problemTitle, language: L10n.savedLanguage()),
                    message: L10n.string(.libraryTampered, language: L10n.savedLanguage())
                )
                return Payload(apps: [], catalogPlaytime: [:], catalogDownloads: [:], catalogRecords: [:])
            }
            plain = opened
        } else {
            print("【加密】检测到明文 apps.json，下次保存会加密")
            plain = data
        }
        do {
            return try JSONDecoder().decode(Payload.self, from: plain)
        } catch {
            print("[Library] apps.json 无法解析：\(error.localizedDescription)")
            quarantine(data)
            VestaNotice.show(
                title: L10n.string(.problemTitle, language: L10n.savedLanguage()),
                message: L10n.string(.libraryTampered, language: L10n.savedLanguage())
            )
            return Payload(apps: [], catalogPlaytime: [:], catalogDownloads: [:], catalogRecords: [:])
        }
    }

    /// 把读不懂的原文件挪走，避免下一次保存直接盖掉。
    private static func quarantine(_ data: Data) {
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = folder.appendingPathComponent("apps.json.invalid-\(stamp)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.moveItem(at: fileURL, to: destination)
            } else {
                try data.write(to: destination, options: .atomic)
            }
            print("[Library] 已保留无法读取的原文件：\(destination.path)")
        } catch {
            print("[Library] 无法保留原文件：\(error.localizedDescription)")
        }
    }

    private static func record(for program: WindowsApp, link: String) -> CatalogRecord {
        CatalogRecord(
            category: program.category,
            tags: program.displayTags,
            iconURL: program.iconURL ?? "",
            bannerImageURL: program.bannerImageURL ?? "",
            downloadURL: link,
            ambientStyle: program.ambientStyle,
            isFavorite: program.isFavorite,
            boundInstallPath: program.platform == .macOS ? program.installPath : ""
        )
    }

    /// 样本里已经写好的图标和分类优先保留。只有样本缺了，才用文件里的副本补上。
    private static func applyRecord(_ record: CatalogRecord?, to program: inout WindowsApp) {
        guard let record else { return }
        program.isFavorite = record.isFavorite
        if program.category.isEmpty, !record.category.isEmpty {
            program.category = record.category
        }
        if program.tags.isEmpty, !record.tags.isEmpty {
            program.tags = record.tags
        }
        let namedIcon = program.customIconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let icon = program.iconURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if namedIcon.isEmpty, icon.isEmpty, !record.iconURL.isEmpty {
            program.iconURL = record.iconURL
        }
        let banner = program.bannerImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if banner.isEmpty, !record.bannerImageURL.isEmpty {
            program.bannerImageURL = record.bannerImageURL
        }
        if program.ambientStyle.isEmpty, !record.ambientStyle.isEmpty {
            program.ambientStyle = record.ambientStyle
        }
        let link = program.downloadURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if link.isEmpty, !record.downloadURL.isEmpty {
            program.downloadURL = record.downloadURL
        }
        let bound = record.boundInstallPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if program.platform == .macOS, !bound.isEmpty {
            program.installPath = bound
            program.absolutePath = bound
        }
    }

    private static func stored(_ app: WindowsApp) -> StoredApp {
        StoredApp(
            id: app.id,
            name: app.name,
            absolutePath: app.absolutePath,
            installPath: app.installPath,
            bottleName: app.bottleName,
            bookmark: app.importBookmark,
            iconPath: app.customIconName,
            playtimeSeconds: app.playtimeSeconds,
            publisher: app.publisher,
            summary: app.summary,
            symbolName: app.symbolName,
            tint: tintName(app.tint),
            downloadURL: app.downloadURL,
            isFavorite: app.isFavorite,
            platform: app.platform.rawValue,
            kind: app.kind.rawValue
        )
    }

    private static func makeApp(_ stored: StoredApp) -> WindowsApp {
        let macApp = stored.platform == AppPlatform.macOS.rawValue
            || stored.absolutePath.lowercased().hasSuffix(".app")
            || stored.installPath.lowercased().hasSuffix(".app")
        let kind = AppKind(rawValue: stored.kind) ?? (macApp ? .game : .utility)
        var app = WindowsApp(
            id: stored.id,
            name: stored.name,
            publisher: stored.publisher,
            version: "—",
            kind: kind,
            category: kind.title,
            summary: stored.summary,
            bottleName: macApp ? nil : stored.bottleName,
            platform: macApp ? .macOS : .windows,
            installPath: stored.installPath,
            importBookmark: stored.bookmark,
            iconName: "app.fill",
            symbolName: stored.symbolName.isEmpty ? "app.fill" : stored.symbolName,
            tint: tint(stored.tint),
            isRunning: false,
            lastRunText: "尚未运行"
        )
        app.playtimeSeconds = stored.playtimeSeconds
        app.isUserImported = true
        app.absolutePath = stored.absolutePath.isEmpty ? stored.installPath : stored.absolutePath
        app.customIconName = stored.iconPath
        app.downloadURL = stored.downloadURL
        app.isFavorite = stored.isFavorite
        return app
    }

    private static func tintName(_ tint: AppTint) -> String {
        switch tint {
        case .blue: return "blue"
        case .indigo: return "indigo"
        case .green: return "green"
        case .orange: return "orange"
        case .teal: return "teal"
        case .red: return "red"
        case .cyan: return "cyan"
        case .ember: return "ember"
        case .gold: return "gold"
        }
    }

    private static func tint(_ name: String) -> AppTint {
        switch name {
        case "blue": return .blue
        case "indigo": return .indigo
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "cyan": return .cyan
        case "ember": return .ember
        case "gold": return .gold
        default: return .teal
        }
    }
}
