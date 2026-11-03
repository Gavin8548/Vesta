//
//  BackupManager.swift
//
//  只打包容器 C 盘里的存档目录，不复制游戏本体。
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BottleBackup: Identifiable, Hashable, Sendable {
    let url: URL
    let created: Date
    let byteCount: Int64

    var id: String { url.path }
}

nonisolated enum BackupManager {
    private static let saveFolders = ["Documents", "Saved Games", "AppData/Roaming", "AppData/LocalLow"]

    static func backups(for bottleName: String) -> [BottleBackup] {
        let folder = backupFolder(for: bottleName)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "zip" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                return BottleBackup(
                    url: url,
                    created: values?.creationDate ?? .distantPast,
                    byteCount: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.created > $1.created }
    }

    static func createBackup(bottleName: String) -> String {
        let language = L10n.savedLanguage()
        guard let drive = existingDrive(named: bottleName) else {
            return L10n.string(.backupNoDrive, language: language)
        }
        let saves = saveDirectories(in: drive)
        guard !saves.isEmpty else {
            return L10n.string(.backupEmpty, language: language)
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = backupFolder(for: bottleName)
        let stamp = Self.stamp.string(from: Date())
        let zip = folder.appendingPathComponent("\(safeName(bottleName))-\(stamp).zip")
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for save in saves {
                let relative = relativePath(of: save, under: drive)
                let destination = staging.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: save, to: destination)
            }
            try zipFolder(staging, to: zip)
            try? FileManager.default.removeItem(at: staging)
            return L10n.string(.backupDone, language: language)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            return L10n.string(.backupFailed, language: language)
        }
    }

    static func restore(_ backup: BottleBackup, bottleName: String) -> String {
        let language = L10n.savedLanguage()
        guard let drive = existingDrive(named: bottleName) else {
            return L10n.string(.backupNoDrive, language: language)
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try unzip(backup.url, to: staging)
            let payload = unpackedRoot(in: staging)
            try merge(from: payload, to: drive)
            try? FileManager.default.removeItem(at: staging)
            return L10n.string(.backupRestored, language: language)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            return L10n.string(.backupFailed, language: language)
        }
    }

    @MainActor
    static func export(_ backup: BottleBackup) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = backup.url.lastPathComponent
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: backup.url, to: destination)
    }

    static func sizeText(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        if megabytes < 1000 {
            return String(format: "%.0f MB", megabytes)
        }
        return String(format: "%.1f GB", megabytes / 1000)
    }

    private static func existingDrive(named name: String) -> URL? {
        AppLauncher.driveRoots(named: name).first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func saveDirectories(in drive: URL) -> [URL] {
        let users = drive.appendingPathComponent("users")
        guard let accounts = try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil) else {
            return []
        }
        var found: [URL] = []
        for account in accounts where account.hasDirectoryPath {
            for folder in saveFolders {
                let url = account.appendingPathComponent(folder)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    found.append(url)
                }
            }
        }
        return found
    }

    private static func backupFolder(for bottleName: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyApp/Backups", isDirectory: true)
            .appendingPathComponent(safeName(bottleName), isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func safeName(_ name: String) -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = cleaned.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" { return character }
            return "-"
        }
        let text = String(allowed)
        return text.isEmpty ? "Bottle" : text
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = url.path
        guard path.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }

    private static func zipFolder(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", source.path, destination.path]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if !errorText.isEmpty {
            print("[Backup] \(errorText)")
        }
        print("[Backup] ditto Exit Code: \(process.terminationStatus)")
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func unzip(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", source.path, destination.path]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if !errorText.isEmpty {
            print("[Backup] \(errorText)")
        }
        print("[Backup] ditto Exit Code: \(process.terminationStatus)")
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
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

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

struct BottleBackupSection: View {
    let bottleName: String
    @EnvironmentObject private var language: LanguageManager
    @State private var backups: [BottleBackup] = []
    @State private var selectedID: BottleBackup.ID?
    @State private var status = ""
    @State private var isBusy = false

    var body: some View {
        GroupBox(language.text(.backupSection)) {
            VStack(alignment: .leading, spacing: 10) {
                if backups.isEmpty {
                    Text(language.text(.backupEmpty))
                        .foregroundStyle(.secondary)
                } else {
                    backupList
                }
                buttonRow
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: reload)
    }

    private var backupList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(backups) { backup in
                Button {
                    selectedID = backup.id
                } label: {
                    HStack {
                        Text(backup.url.lastPathComponent)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(BackupManager.sizeText(backup.byteCount))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedID == backup.id ? Color.accentColor : Color.primary)
            }
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Button(language.text(.backupNow), action: backup)
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            Button(language.text(.restoreBackup), action: restore)
                .disabled(isBusy || chosen == nil)
            Button(language.text(.exportSave), action: export)
                .disabled(chosen == nil)
        }
        .controlSize(.regular)
    }

    private var chosen: BottleBackup? {
        if let selectedID, let match = backups.first(where: { $0.id == selectedID }) {
            return match
        }
        return backups.first
    }

    private func reload() {
        backups = BackupManager.backups(for: bottleName)
        if selectedID == nil {
            selectedID = backups.first?.id
        }
    }

    private func backup() {
        run { BackupManager.createBackup(bottleName: bottleName) }
    }

    private func restore() {
        guard let chosen else { return }
        run { BackupManager.restore(chosen, bottleName: bottleName) }
    }

    private func export() {
        guard let chosen else { return }
        BackupManager.export(chosen)
    }

    private func run(_ work: @escaping @Sendable () -> String) {
        guard !isBusy else { return }
        isBusy = true
        Task.detached {
            let message = work()
            await MainActor.run {
                status = message
                isBusy = false
                reload()
            }
        }
    }
}
