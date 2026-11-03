//
//  SaveSync.swift
//
//  扫描容器里的存档目录，备份到用户指定的文件夹、iCloud Drive 或本机加密库。
//  启动前只比较清单时间，云端较新时先询问，不静默覆盖本地进度。
//

import AppKit
import CryptoKit
import Foundation
import SwiftUI

nonisolated struct SaveHistoryItem: Identifiable, Hashable, Sendable {
    var id: String
    var folder: URL
    var updated: Date
    var bytes: Int64
}

nonisolated struct SaveSpot: Identifiable, Hashable, Sendable {
    var relativePath: String
    var bytes: Int64

    var id: String { relativePath }
}

nonisolated struct SaveManifest: Codable, Sendable {
    var updated: Date
    var bytes: Int64
    var folders: [String]
    var sealed: Bool
}

nonisolated enum SaveSyncManager {
    private static let folderNames = ["Documents", "Saved Games", "AppData/Roaming", "AppData/LocalLow"]
    private static let magic = Data("VSS1".utf8)

    static func scan(bottleName: String) -> [SaveSpot] {
        guard let drive = driveCandidates(bottleName: bottleName).first else { return [] }
        return spots(in: drive)
    }

    static func cloudIsNewer(bottleName: String) -> Bool {
        guard let manifest = readManifest(at: cloudPackage(bottleName: bottleName)?.deletingLastPathComponent()) else {
            return false
        }
        guard let local = localMarker(bottleName: bottleName) else {
            return true
        }
        return manifest.updated.timeIntervalSince(local) > 1
    }

    static func export(bottleName: String, to folder: URL) -> String {
        writeResult(bottleName: bottleName, folder: folder, recordLocal: true)
    }

    static func pushToICloud(bottleName: String) -> String {
        guard let folder = cloudFolder(bottleName: bottleName, create: true) else {
            return L10n.string(.saveSynciCloudMissing, language: L10n.savedLanguage())
        }
        return writeResult(bottleName: bottleName, folder: folder, recordLocal: true)
    }

    static func pushToVault(bottleName: String) -> String {
        writeResult(bottleName: bottleName, folder: vaultFolder(bottleName: bottleName, create: true), recordLocal: true)
    }

    static func restoreNewestCloud(bottleName: String) -> String {
        let language = L10n.savedLanguage()
        guard let package = cloudPackage(bottleName: bottleName),
              let manifest = readManifest(at: package.deletingLastPathComponent()) else {
            return L10n.string(.saveSyncEmpty, language: language)
        }
        do {
            if !scan(bottleName: bottleName).isEmpty {
                _ = try writePackage(bottleName: bottleName, to: vaultFolder(bottleName: bottleName, create: true))
            }
            try installPackage(package, sealed: manifest.sealed, bottleName: bottleName)
            storeLocalMarker(manifest.updated, bottleName: bottleName)
            return L10n.string(.saveSyncRestored, language: language)
        } catch {
            print("[SaveSync] 恢复失败：\(error.localizedDescription)")
            return L10n.string(.saveSyncFailed, language: language)
        }
    }

    private static func writeResult(bottleName: String, folder: URL, recordLocal: Bool) -> String {
        let language = L10n.savedLanguage()
        do {
            let manifest = try writePackage(bottleName: bottleName, to: folder)
            if recordLocal {
                storeLocalMarker(manifest.updated, bottleName: bottleName)
                snapshotHistory(from: folder, bottleName: bottleName)
            }
            if manifest.sealed {
                return L10n.string(.saveSyncBackupDone, language: language)
            }
            return L10n.string(.saveSyncVaultPlain, language: language)
        } catch SaveSyncError.nothingToCopy {
            return L10n.string(.saveSyncEmpty, language: language)
        } catch {
            print("[SaveSync] 备份失败：\(error.localizedDescription)")
            return L10n.string(.saveSyncFailed, language: language)
        }
    }

    private static func writePackage(bottleName: String, to folder: URL) throws -> SaveManifest {
        guard let drive = driveCandidates(bottleName: bottleName).first else {
            throw SaveSyncError.noDrive
        }
        let spots = spots(in: drive)
        guard !spots.isEmpty else { throw SaveSyncError.nothingToCopy }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("VestaSave-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for spot in spots {
            let source = drive.appendingPathComponent(spot.relativePath)
            let destination = staging.appendingPathComponent(spot.relativePath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }
        let zip = folder.appendingPathComponent("payload.zip")
        try runDitto(["-c", "-k", "--keepParent", staging.path, zip.path])
        let zipData = try Data(contentsOf: zip)
        try? FileManager.default.removeItem(at: zip)
        let sealed = sealIfPossible(zipData)
        try sealed.payload.write(to: folder.appendingPathComponent("payload.vestasave"), options: .atomic)
        if sealed.usedKey {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: folder.appendingPathComponent("payload.vestasave").path
            )
        }
        let manifest = SaveManifest(
            updated: Date(),
            bytes: spots.reduce(Int64(0)) { $0 + $1.bytes },
            folders: spots.map(\.relativePath),
            sealed: sealed.usedKey
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        print("【存档】已写入 \(folder.path) sealed=\(sealed.usedKey)")
        return manifest
    }

    private static func installPackage(_ package: URL, sealed: Bool, bottleName: String) throws {
        guard let drive = driveCandidates(bottleName: bottleName).first else {
            throw SaveSyncError.noDrive
        }
        let data = try Data(contentsOf: package)
        let zipBytes = try unseal(data, expectSealed: sealed)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("VestaSaveRestore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let zip = staging.appendingPathComponent("payload.zip")
        try zipBytes.write(to: zip, options: .atomic)
        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try runDitto(["-x", "-k", zip.path, unpacked.path])
        let payload = unpackedRoot(in: unpacked)
        try merge(from: payload, to: drive)
    }

    private static func sealIfPossible(_ data: Data) -> (payload: Data, usedKey: Bool) {
        guard let key = LibraryVault.existingKey() else {
            return (data, false)
        }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else {
                return (data, false)
            }
            return (magic + combined, true)
        } catch {
            print("[SaveSync] 加密失败，改为明文保存：\(error.localizedDescription)")
            return (data, false)
        }
    }

    private static func unseal(_ data: Data, expectSealed: Bool) throws -> Data {
        guard data.starts(with: magic) else {
            if expectSealed { throw SaveSyncError.sealedMissing }
            return data
        }
        guard let key = LibraryVault.existingKey() else {
            throw SaveSyncError.missingKey
        }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        return try AES.GCM.open(box, using: key)
    }

    private static func spots(in drive: URL) -> [SaveSpot] {
        let users = drive.appendingPathComponent("users")
        guard let accounts = try? FileManager.default.contentsOfDirectory(
            at: users,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        var found: [SaveSpot] = []
        for account in accounts {
            let values = try? account.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            for name in folderNames {
                let folder = account.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }
                let relative = "users/\(account.lastPathComponent)/\(name)"
                found.append(SaveSpot(relativePath: relative, bytes: StorageMeasure.byteCount(at: folder)))
            }
        }
        return found
    }

    private static func driveCandidates(bottleName: String) -> [URL] {
        var urls: [URL] = []
        let prefix = StorageMeasure.currentPrefix().appendingPathComponent("drive_c", isDirectory: true)
        urls.append(prefix)
        for extra in AppLauncher.driveRoots(named: bottleName) where !urls.contains(where: { $0.path == extra.path }) {
            urls.append(extra)
        }
        return urls.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func iCloudDriveRoot() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return root
    }

    private static func cloudFolder(bottleName: String, create: Bool) -> URL? {
        guard let root = iCloudDriveRoot() else { return nil }
        let folder = root
            .appendingPathComponent("Vesta Saves", isDirectory: true)
            .appendingPathComponent(safeName(bottleName), isDirectory: true)
        if create {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                print("[SaveSync] 无法创建 iCloud 目录：\(error.localizedDescription)")
                return nil
            }
        }
        return folder
    }

    private static func cloudPackage(bottleName: String) -> URL? {
        guard let folder = cloudFolder(bottleName: bottleName, create: false) else { return nil }
        let payload = folder.appendingPathComponent("payload.vestasave")
        guard FileManager.default.fileExists(atPath: payload.path) else { return nil }
        return payload
    }

    static func history(bottleName: String) -> [SaveHistoryItem] {
        let root = vaultFolder(bottleName: bottleName, create: false)
            .appendingPathComponent("history", isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return folders.compactMap { folder -> SaveHistoryItem? in
            guard let manifest = readManifest(at: folder) else { return nil }
            return SaveHistoryItem(
                id: folder.lastPathComponent,
                folder: folder,
                updated: manifest.updated,
                bytes: manifest.bytes
            )
        }
        .sorted { $0.updated > $1.updated }
    }

    static func restoreHistory(_ item: SaveHistoryItem, bottleName: String) -> String {
        let language = L10n.savedLanguage()
        let package = item.folder.appendingPathComponent("payload.vestasave")
        guard FileManager.default.fileExists(atPath: package.path),
              let manifest = readManifest(at: item.folder) else {
            return L10n.string(.saveSyncEmpty, language: language)
        }
        do {
            try installPackage(package, sealed: manifest.sealed, bottleName: bottleName)
            return L10n.string(.saveSyncRestored, language: language)
        } catch {
            print("[SaveSync] 恢复历史备份失败：\(error.localizedDescription)")
            return L10n.string(.saveSyncFailed, language: language)
        }
    }

    static func restorePayload(_ package: URL, bottleName: String) -> String {
        let language = L10n.savedLanguage()
        guard FileManager.default.fileExists(atPath: package.path) else {
            return L10n.string(.saveSyncEmpty, language: language)
        }
        do {
            try installPackage(package, sealed: false, bottleName: bottleName)
            return L10n.string(.saveSyncRestored, language: language)
        } catch {
            print("[SaveSync] 恢复云端备份失败：\(error.localizedDescription)")
            return L10n.string(.saveSyncFailed, language: language)
        }
    }

    static func latestPayload(bottleName: String) -> URL? {
        if let newest = history(bottleName: bottleName).first {
            let file = newest.folder.appendingPathComponent("payload.vestasave")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        let current = vaultFolder(bottleName: bottleName, create: false).appendingPathComponent("payload.vestasave")
        return FileManager.default.fileExists(atPath: current.path) ? current : nil
    }

    private static func snapshotHistory(from folder: URL, bottleName: String) {
        let payload = folder.appendingPathComponent("payload.vestasave")
        let manifest = folder.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: payload.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = vaultFolder(bottleName: bottleName, create: true)
            .appendingPathComponent("history", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: payload, to: dest.appendingPathComponent("payload.vestasave"))
            if FileManager.default.fileExists(atPath: manifest.path) {
                try FileManager.default.copyItem(at: manifest, to: dest.appendingPathComponent("manifest.json"))
            }
        } catch {
            print("[SaveSync] 历史备份没有留下：\(error.localizedDescription)")
        }
    }

    private static func vaultFolder(bottleName: String, create: Bool) -> URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vesta/SaveVault", isDirectory: true)
            .appendingPathComponent(safeName(bottleName), isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private static func readManifest(at folder: URL?) -> SaveManifest? {
        guard let folder else { return nil }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SaveManifest.self, from: data)
    }

    private static func localMarker(bottleName: String) -> Date? {
        let raw = UserDefaults.standard.string(forKey: markerKey(bottleName)) ?? ""
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func storeLocalMarker(_ date: Date, bottleName: String) {
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: date), forKey: markerKey(bottleName))
    }

    private static func markerKey(_ bottleName: String) -> String {
        "MyApp.saveSync." + safeName(bottleName).lowercased()
    }

    private static func safeName(_ name: String) -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(cleaned.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" { return character }
            return "-"
        })
        return text.isEmpty ? "Bottle" : text
    }

    private static func unpackedRoot(in staging: URL) -> URL {
        let children = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        if children.count == 1, let only = children.first, only.hasDirectoryPath {
            return only
        }
        return staging
    }

    private static func merge(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if !manager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: destination)
            return
        }
        guard isDirectory.boolValue else {
            try manager.removeItem(at: destination)
            try manager.copyItem(at: source, to: destination)
            return
        }
        let children = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for child in children {
            try merge(from: child, to: destination.appendingPathComponent(child.lastPathComponent))
        }
    }

    private static func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            print("[SaveSync] \(errorText)")
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private enum SaveSyncError: Error {
    case nothingToCopy
    case noDrive
    case missingKey
    case sealedMissing
}

struct SaveSyncCard: View {
    let bottleName: String
    @EnvironmentObject private var language: LanguageManager
    @State private var spots: [SaveSpot] = []
    @State private var history: [SaveHistoryItem] = []
    @State private var cloud: [SaveCloudRecord] = []
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(.saveSyncSection))
                .font(.headline)
            Text(language.text(.saveSyncScope))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if spots.isEmpty {
                Text(language.text(.saveSyncEmpty))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(language.format(.saveSyncFound, String(spots.count)))
                    .font(.subheadline)
                ForEach(spots.prefix(6)) { spot in
                    HStack {
                        Text(spot.relativePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(BackupManager.sizeText(spot.bytes))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            if !history.isEmpty {
                Text(language.text(.saveHistory))
                    .font(.subheadline)
                ForEach(history.prefix(6)) { item in
                    HStack {
                        Text(item.updated.formatted(date: .abbreviated, time: .shortened))
                        Spacer(minLength: 8)
                        Button(language.text(.saveRestore)) {
                            restore(item)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption)
                }
            }
            if !cloud.isEmpty {
                Text(language.text(.saveCloud))
                    .font(.subheadline)
                ForEach(cloud) { record in
                    HStack {
                        Text(record.createdAt)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button(language.text(.saveRestore)) {
                            restoreCloud(record)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button(language.text(.saveSyncScan), action: refresh)
                        .disabled(busy)
                    Button(language.text(.saveSyncBackup), action: backup)
                        .disabled(busy)
                    Button(language.text(.saveSynciCloud), action: pushCloud)
                        .disabled(busy)
                    Button(language.text(.saveSyncVault), action: pushVault)
                        .disabled(busy)
                    Button(language.text(.saveCloud), action: uploadCloud)
                        .disabled(busy)
                }
                .controlSize(.small)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: bottleName) {
            let name = bottleName
            history = await Task.detached(priority: .utility) {
                SaveSyncManager.history(bottleName: name)
            }.value
        }
    }

    private func refresh() {
        Task { await load() }
    }

    private func load() async {
        let name = bottleName
        spots = await Task.detached(priority: .utility) {
            SaveSyncManager.scan(bottleName: name)
        }.value
        history = await Task.detached(priority: .utility) {
            SaveSyncManager.history(bottleName: name)
        }.value
    }

    /// 只有用户点击云端按钮时才创建 Supabase 客户端，避免冷启动时在主线程里连上网络。
    private func loadCloud() async {
        cloud = await SaveCloudSync.list(bottleName: bottleName)
    }

    private func backup() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let name = bottleName
        run { SaveSyncManager.export(bottleName: name, to: folder) }
    }

    private func pushCloud() {
        run { SaveSyncManager.pushToICloud(bottleName: bottleName) }
    }

    private func pushVault() {
        run { SaveSyncManager.pushToVault(bottleName: bottleName) }
    }

    private func restore(_ item: SaveHistoryItem) {
        let name = bottleName
        run { SaveSyncManager.restoreHistory(item, bottleName: name) }
    }

    private func uploadCloud() {
        busy = true
        note = ""
        Task {
            note = await SaveCloudSync.upload(bottleName: bottleName)
            await load()
            await loadCloud()
            busy = false
        }
    }

    private func restoreCloud(_ record: SaveCloudRecord) {
        busy = true
        note = ""
        Task {
            note = await SaveCloudSync.restore(record, bottleName: bottleName)
            await load()
            await loadCloud()
            busy = false
        }
    }

    private func run(_ work: @escaping () -> String) {
        busy = true
        note = ""
        Task {
            let message = await Task.detached(priority: .utility) {
                work()
            }.value
            note = message
            await load()
            busy = false
        }
    }
}
