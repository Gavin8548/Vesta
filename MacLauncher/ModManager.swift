//
//  ModManager.swift
//
//  单机游戏的本地 Mod 目录。只在启用和禁用文件夹之间移动，
//  不改游戏程序，也不碰联机或反作弊。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GameMod: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let enabled: Bool
    let folderPath: String
}

nonisolated enum ModStore {
    static func mods(for key: String) -> [GameMod] {
        let root = directory(for: key)
        let enabled = children(in: root.appendingPathComponent("Enabled"), enabled: true)
        let disabled = children(in: root.appendingPathComponent("Disabled"), enabled: false)
        return (enabled + disabled).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func importFolder(_ url: URL, key: String) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let destination = directory(for: key)
            .appendingPathComponent("Enabled", isDirectory: true)
            .appendingPathComponent(safeFolderName(url.lastPathComponent), isDirectory: true)
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try? manager.removeItem(at: destination)
        }
        try? manager.copyItem(at: url, to: destination)
    }

    static func setEnabled(_ mod: GameMod, key: String, enabled: Bool) {
        guard mod.enabled != enabled else { return }
        let root = directory(for: key)
        let side = enabled ? "Enabled" : "Disabled"
        let destination = root.appendingPathComponent(side, isDirectory: true)
            .appendingPathComponent((mod.folderPath as NSString).lastPathComponent, isDirectory: true)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: URL(fileURLWithPath: mod.folderPath), to: destination)
    }

    static func reveal(key: String) {
        let url = directory(for: key)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    static func key(for name: String, steamAppID: String?) -> String {
        let steam = steamAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !steam.isEmpty { return "steam-\(steam)" }
        let cleaned = name.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            return "-"
        }
        return "name-" + String(cleaned)
    }

    private static func children(in folder: URL, enabled: Bool) -> [GameMod] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.filter(\.hasDirectoryPath).map { url in
            GameMod(id: url.path, name: url.lastPathComponent, enabled: enabled, folderPath: url.path)
        }
    }

    private static func directory(for key: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyApp/Mods", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
        let manager = FileManager.default
        try? manager.createDirectory(at: root.appendingPathComponent("Enabled"), withIntermediateDirectories: true)
        try? manager.createDirectory(at: root.appendingPathComponent("Disabled"), withIntermediateDirectories: true)
        return root
    }

    private static func safeFolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Mod" : trimmed
    }
}

struct ModLibrarySection: View {
    let program: WindowsApp
    @EnvironmentObject private var language: LanguageManager
    @State private var mods: [GameMod] = []
    @State private var isImporterPresented = false
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text(.modsHint))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if mods.isEmpty {
                Text(language.text(.modsEmpty))
                    .foregroundStyle(.secondary)
            } else {
                modList
            }
            HStack(spacing: 8) {
                Button(language.text(.importMod)) { isImporterPresented = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                Button(language.text(.openMods)) { ModStore.reveal(key: storageKey) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: reload)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importFolder(url)
        }
    }

    private var modList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(mods) { mod in
                ModRow(mod: mod) { enabled in
                    toggle(mod, enabled: enabled)
                }
            }
        }
    }

    private var storageKey: String {
        ModStore.key(for: program.name, steamAppID: program.steamAppID)
    }

    private func reload() {
        mods = ModStore.mods(for: storageKey)
    }

    private func importFolder(_ url: URL) {
        let key = storageKey
        isBusy = true
        Task.detached {
            ModStore.importFolder(url, key: key)
            await MainActor.run {
                isBusy = false
                reload()
            }
        }
    }

    private func toggle(_ mod: GameMod, enabled: Bool) {
        let key = storageKey
        ModStore.setEnabled(mod, key: key, enabled: enabled)
        reload()
    }
}

private struct ModRow: View {
    let mod: GameMod
    let onToggle: (Bool) -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        Toggle(isOn: Binding(get: { mod.enabled }, set: onToggle)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .font(.body.weight(.semibold))
                Text(mod.enabled ? language.text(.modOn) : language.text(.modOff))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
