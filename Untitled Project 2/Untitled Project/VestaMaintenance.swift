//
//  VestaMaintenance.swift
//
//  容器占用、缓存清理、整包 .vestabackup，以及游戏运行时的状态栏停止。
//  存档 zip 仍只打包存档目录，不走这里。
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct StorageReport: Sendable {
    var path: String
    var total: Int64
    var cache: Int64
    var exists: Bool
}

nonisolated enum StorageMeasure {
    static func currentPrefix() -> URL {
        let saved = UserDefaults.standard.string(forKey: WinePrefixStore.defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if saved.isEmpty {
            return WinePrefixStore.desktopDefault
        }
        return URL(fileURLWithPath: (saved as NSString).expandingTildeInPath, isDirectory: true)
    }

    static func measure() -> StorageReport {
        let prefix = currentPrefix()
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: prefix.path, isDirectory: &isDirectory) && isDirectory.boolValue
        guard exists else {
            return StorageReport(path: prefix.path, total: 0, cache: 0, exists: false)
        }
        let caches = cacheDirectories(in: prefix) + ShaderCache.directories()
        let cacheBytes = caches.reduce(Int64(0)) { $0 + byteCount(at: $1) }
        return StorageReport(path: prefix.path, total: byteCount(at: prefix), cache: cacheBytes, exists: true)
    }

    /// 只清空临时目录，不删除游戏、存档和着色器。着色器走深度清理。
    static func clearCache() -> Int64 {
        let prefix = currentPrefix()
        var freed: Int64 = 0
        for folder in cacheDirectories(in: prefix) {
            freed += byteCount(at: folder)
            let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for child in children {
                try? FileManager.default.removeItem(at: child)
            }
        }
        return freed
    }

    private static func cacheDirectories(in prefix: URL) -> [URL] {
        var folders = [
            prefix.appendingPathComponent("drive_c/windows/temp", isDirectory: true)
        ]
        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        let accounts = (try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []
        for account in accounts where account.hasDirectoryPath {
            folders.append(account.appendingPathComponent("Temp", isDirectory: true))
            folders.append(account.appendingPathComponent("AppData/Local/Temp", isDirectory: true))
        }
        return folders.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    static func byteCount(at root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// 只删容器根目录和 C 盘根目录上的日志，不进入游戏安装目录。
    static func clearLogs() -> Int64 {
        var freed: Int64 = 0
        let prefix = currentPrefix()
        freed += removeLogFiles(in: prefix)
        freed += removeLogFiles(in: prefix.appendingPathComponent("drive_c", isDirectory: true))
        freed += removeChildren(prefix.appendingPathComponent("drive_c/windows/Logs", isDirectory: true))
        let supportLogs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vesta/Logs", isDirectory: true)
        freed += removeChildren(supportLogs)
        return freed
    }

    /// 日志、临时目录，以及超过三周没再写过的着色器。不删除游戏和存档。
    static func cleanRuntimeJunk() -> Int64 {
        clearLogs() + clearCache() + ShaderCache.pruneStale()
    }

    private static func removeLogFiles(in folder: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return 0
        }
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])) ?? []
        var freed: Int64 = 0
        for child in children {
            guard child.pathExtension.lowercased() == "log" else { continue }
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            freed += Int64(values?.fileSize ?? 0)
            try? FileManager.default.removeItem(at: child)
        }
        return freed
    }

    private static func removeChildren(_ folder: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return 0
        }
        let freed = byteCount(at: folder)
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for child in children {
            try? FileManager.default.removeItem(at: child)
        }
        return freed
    }
}

nonisolated enum ShaderCache {
    static func dxvkDirectory(create: Bool = false) -> URL {
        cacheDirectory("DXVKCache", create: create)
    }

    static func vkd3dDirectory(create: Bool = false) -> URL {
        cacheDirectory("VKD3DCache", create: create)
    }

    static func mesaDirectory(create: Bool = false) -> URL {
        cacheDirectory("MesaShaderCache", create: create)
    }

    private static func cacheDirectory(_ name: String, create: Bool) -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vesta/\(name)", isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func directories() -> [URL] {
        let prefix = StorageMeasure.currentPrefix()
        var folders = [
            prefix.appendingPathComponent("shadercache", isDirectory: true),
            dxvkDirectory(),
            vkd3dDirectory(),
            mesaDirectory()
        ]
        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        let accounts = (try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []
        for account in accounts where account.hasDirectoryPath {
            folders.append(account.appendingPathComponent("AppData/Local/D3DSCache", isDirectory: true))
            folders.append(account.appendingPathComponent("AppData/Local/NVIDIA/DXCache", isDirectory: true))
            folders.append(account.appendingPathComponent("AppData/Local/vkd3d-proton", isDirectory: true))
            folders.append(account.appendingPathComponent("AppData/Local/dxvk", isDirectory: true))
        }
        return folders.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    static func deepClean() -> Int64 {
        var freed: Int64 = 0
        for folder in directories() {
            freed += StorageMeasure.byteCount(at: folder)
            let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for child in children {
                try? FileManager.default.removeItem(at: child)
            }
        }
        return freed
    }

    /// 只删超过三周没再写过的着色器，避免把正在用的缓存清掉。
    static func pruneStale() -> Int64 {
        let cutoff = Date().addingTimeInterval(-21 * 24 * 60 * 60)
        var freed: Int64 = 0
        for folder in directories() {
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            ) else { continue }
            for case let file as URL in enumerator {
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
                guard values?.isRegularFile == true, let modified = values?.contentModificationDate, modified < cutoff else { continue }
                freed += Int64(values?.fileSize ?? 0)
                try? FileManager.default.removeItem(at: file)
            }
        }
        return freed
    }
}

nonisolated enum PreferenceSnapshot {
    private static let prefixes = [
        "MyApp.gamePreset.",
        "MyApp.bottlePreset.",
        "MyApp.translationEngine.",
        "MyApp.launchMode."
    ]

    static func capture() -> [String: String] {
        var snapshot: [String: String] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            guard prefixes.contains(where: { key.hasPrefix($0) }) else { continue }
            if let data = value as? Data {
                snapshot[key] = "b64:" + data.base64EncodedString()
            } else if let text = value as? String {
                snapshot[key] = "str:" + text
            }
        }
        return snapshot
    }

    static func restore(_ snapshot: [String: String]) {
        let defaults = UserDefaults.standard
        for (key, value) in snapshot {
            guard prefixes.contains(where: { key.hasPrefix($0) }) else { continue }
            if value.hasPrefix("b64:"), let data = Data(base64Encoded: String(value.dropFirst(4))) {
                defaults.set(data, forKey: key)
            } else if value.hasPrefix("str:") {
                defaults.set(String(value.dropFirst(4)), forKey: key)
            }
        }
    }
}

nonisolated enum VestaArchive {
    private static let kind = "vestabackup"

    static func export(to destination: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("VestaArchive-\(UUID().uuidString)", isDirectory: true)
        let root = staging.appendingPathComponent("VestaArchive", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker: [String: String] = ["kind": kind, "version": "1"]
        let markerData = try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted])
        try markerData.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        try AppLibraryStore.exportLibraryFolder(to: root.appendingPathComponent("VestaLibrary", isDirectory: true))
        let prefix = StorageMeasure.currentPrefix()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: prefix.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try FileManager.default.copyItem(
                at: prefix,
                to: root.appendingPathComponent("VestaContainer", isDirectory: true)
            )
        }
        let preferences = try JSONSerialization.data(
            withJSONObject: PreferenceSnapshot.capture(),
            options: [.prettyPrinted]
        )
        try preferences.write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try runDitto(["-c", "-k", "--keepParent", root.path, destination.path])
    }

    static func restore(from archive: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("VestaArchiveRestore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try runDitto(["-x", "-k", archive.path, staging.path])
        guard let root = archiveRoot(in: staging) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let library = root.appendingPathComponent("VestaLibrary", isDirectory: true)
        if FileManager.default.fileExists(atPath: library.path) {
            try AppLibraryStore.restoreLibraryFolder(at: library)
        }
        let container = root.appendingPathComponent("VestaContainer", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: container.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try replacePrefix(with: container)
        }
        let preferences = root.appendingPathComponent("preferences.json")
        if let data = try? Data(contentsOf: preferences),
           let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            PreferenceSnapshot.restore(snapshot)
        }
    }

    private static func archiveRoot(in staging: URL) -> URL? {
        let named = staging.appendingPathComponent("VestaArchive", isDirectory: true)
        if isArchive(named) { return named }
        let children = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        return children.first { isArchive($0) }
    }

    private static func isArchive(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return false
        }
        return object["kind"] == kind
    }

    private static func replacePrefix(with source: URL) throws {
        let destination = WinePrefixStore.resolve()
        let holding = FileManager.default.temporaryDirectory
            .appendingPathComponent("VestaPrefixHold-\(UUID().uuidString)", isDirectory: true)
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.moveItem(at: destination, to: holding)
        }
        do {
            try manager.copyItem(at: source, to: destination)
            try? manager.removeItem(at: holding)
        } catch {
            try? manager.removeItem(at: destination)
            if manager.fileExists(atPath: holding.path) {
                try? manager.moveItem(at: holding, to: destination)
            }
            throw error
        }
    }

    private static func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if !errorText.isEmpty {
            print("[VestaArchive] \(errorText)")
        }
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

struct StorageReportSection: View {
    @EnvironmentObject private var language: LanguageManager
    @State private var report: StorageReport?
    @State private var isWorking = false
    @State private var note = ""

    var body: some View {
        Section(language.text(.storageSection)) {
            if isWorking && report == nil {
                ProgressView()
            } else {
                Text(report?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(language.format(.storageUsed, BackupManager.sizeText(report?.total ?? 0)))
                Text(language.format(.storageCache, BackupManager.sizeText(report?.cache ?? 0)))
                    .foregroundStyle(.secondary)
            }
            Button(language.text(.storageRefresh), action: refresh)
                .disabled(isWorking)
            Button(language.text(.storageClearCache), action: clearCache)
                .disabled(isWorking || (report?.cache ?? 0) == 0)
            Button(language.text(.shaderDeepClean), action: deepCleanShaders)
                .disabled(isWorking)
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await load() }
    }

    private func refresh() {
        Task { await load() }
    }

    private func load() async {
        isWorking = true
        let measured = await Task.detached(priority: .utility) {
            _ = ShaderCache.pruneStale()
            return StorageMeasure.measure()
        }.value
        report = measured
        isWorking = false
    }

    private func clearCache() {
        isWorking = true
        note = ""
        Task {
            let freed = await Task.detached(priority: .utility) {
                StorageMeasure.clearCache()
            }.value
            let measured = await Task.detached(priority: .utility) {
                StorageMeasure.measure()
            }.value
            report = measured
            note = language.format(.storageCleared, BackupManager.sizeText(freed))
            isWorking = false
        }
    }

    private func deepCleanShaders() {
        isWorking = true
        note = ""
        Task {
            let freed = await Task.detached(priority: .utility) {
                ShaderCache.deepClean()
            }.value
            let measured = await Task.detached(priority: .utility) {
                StorageMeasure.measure()
            }.value
            report = measured
            note = language.format(.shaderDeepCleanDone, BackupManager.sizeText(freed))
            isWorking = false
        }
    }
}

struct VestaArchiveButtons: View {
    @EnvironmentObject private var language: LanguageManager
    @State private var isWorking = false

    var body: some View {
        Button(language.text(.archiveExport), action: exportArchive)
            .disabled(isWorking)
        Button(language.text(.archiveImport), action: confirmImport)
            .disabled(isWorking)
        if isWorking {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func exportArchive() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Vesta.vestabackup"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let destination = url.pathExtension.lowercased() == "vestabackup"
            ? url
            : url.appendingPathExtension("vestabackup")
        isWorking = true
        Task {
            let failed = await Task.detached(priority: .utility) {
                do {
                    try VestaArchive.export(to: destination)
                    return false
                } catch {
                    print("[VestaArchive] 导出失败：\(error.localizedDescription)")
                    return true
                }
            }.value
            isWorking = false
            VestaNotice.show(
                title: language.text(.archiveExport),
                message: language.text(failed ? .archiveFailed : .archiveExportDone)
            )
        }
    }

    private func confirmImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data, .zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = language.text(.archiveImport)
        alert.informativeText = language.text(.archiveImportConfirm)
        alert.addButton(withTitle: language.text(.archiveImport))
        alert.addButton(withTitle: language.text(.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isWorking = true
        Task {
            let failed = await Task.detached(priority: .utility) {
                do {
                    try VestaArchive.restore(from: url)
                    return false
                } catch {
                    print("[VestaArchive] 导入失败：\(error.localizedDescription)")
                    return true
                }
            }.value
            isWorking = false
            if !failed {
                NotificationCenter.default.post(name: .vestaLibraryRestored, object: nil)
            }
            VestaNotice.show(
                title: language.text(.archiveImport),
                message: language.text(failed ? .archiveFailed : .archiveImportDone)
            )
        }
    }
}

nonisolated struct RunningSession: Identifiable, Sendable {
    let id: UUID
    let name: String
}

@MainActor
final class VestaStatusItem: NSObject {
    static let shared = VestaStatusItem()

    private var item: NSStatusItem?

    func update(sessions: [RunningSession], enabled: Bool) {
        remove()
    }

    private func remove() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }
}
