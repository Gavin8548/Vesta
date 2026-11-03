//
//  EngineDesk.swift
//
//  列出本机已经存在的 wine64，并记住默认引擎或某个游戏单独使用的引擎。
//  不下载未校验的包，也不启动 Whisky 界面。
//

import AppKit
import SwiftUI

struct EngineInstall: Identifiable, Equatable, Sendable {
    var path: String
    var title: String
    var kind: String

    var id: String { path }
}

nonisolated enum EngineDesk {
    private static let overrideKey = "Vesta.engineOverrides"

    static func scan() -> [EngineInstall] {
        var found: [EngineInstall] = []
        func add(_ title: String, _ path: String, _ kind: String) {
            let expanded = (path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else { return }
            guard !WineLocator.isRetiredDownload(expanded) else { return }
            guard FileManager.default.isExecutableFile(atPath: expanded) else { return }
            guard !found.contains(where: { $0.path == expanded }) else { return }
            found.append(EngineInstall(path: expanded, title: title, kind: kind))
        }

        if let saved = UserDefaults.standard.string(forKey: WineLocator.defaultsKey) {
            add("Saved", saved, "saved")
        }
        let libraries = WineLocator.engineRoot.appendingPathComponent("Libraries", isDirectory: true)
        if let wine = WineLocator.findWine64(in: libraries) {
            add("Vesta", wine, "vesta")
        }
        let home = NSHomeDirectory()
        let whisky = [
            "/Applications/Whisky.app/Contents/Resources/Wine/bin/wine64",
            home + "/Library/Application Support/com.isaacmarovitz.Whisky/Libraries"
        ]
        for path in whisky {
            if path.hasSuffix("wine64") {
                add("Whisky", path, "whisky")
            } else if let wine = WineLocator.findWine64(in: URL(fileURLWithPath: path, isDirectory: true)) {
                add("Whisky", wine, "whisky")
            }
        }
        for root in ["/Applications/CrossOver.app", home + "/Applications/CrossOver.app"] {
            let url = URL(fileURLWithPath: root, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let wine = WineLocator.findWine64(in: url) {
                add("CrossOver", wine, "crossover")
            }
        }
        for root in ["/Applications/Game Porting Toolkit.app", home + "/Applications/Game Porting Toolkit.app"] {
            let url = URL(fileURLWithPath: root, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let wine = WineLocator.findWine64(in: url) {
                add("Game Porting Toolkit", wine, "gptk")
            }
        }
        return found
    }

    static func rememberGlobal(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else { return false }
        guard !WineLocator.isRetiredDownload(expanded) else { return false }
        WineLocator.remember(expanded)
        return true
    }

    static func path(for appID: UUID) -> String? {
        let raw = overrides()[appID.uuidString] ?? ""
        guard FileManager.default.isExecutableFile(atPath: raw) else { return nil }
        return raw
    }

    static func setOverride(_ path: String?, for appID: UUID) {
        var map = overrides()
        if let path, FileManager.default.isExecutableFile(atPath: path) {
            map[appID.uuidString] = path
        } else {
            map.removeValue(forKey: appID.uuidString)
        }
        UserDefaults.standard.set(map, forKey: overrideKey)
    }

    private static func overrides() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: overrideKey) as? [String: String] ?? [:]
    }
}

struct EngineManagerPane: View {
    @EnvironmentObject private var language: LanguageManager
    @State private var engines: [EngineInstall] = []
    @State private var note = ""
    @State private var page: EngineDeskPage = .installs
    @State private var selectedPath = ""
    @State private var gameID: WindowsApp.ID = WindowsApp.samples.first { $0.kind == .game }?.id ?? UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker(language.text(.enginePane), selection: $page) {
                Text(language.text(.engineInstalledTab)).tag(EngineDeskPage.installs)
                Text(language.text(.engineDownloadTab)).tag(EngineDeskPage.downloads)
                Text(language.text(.supportedGames)).tag(EngineDeskPage.games)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            switch page {
            case .installs:
                installs
            case .downloads:
                EngineDownloadPane(engines: engines) {
                    Task { await reload() }
                }
            case .games:
                SupportedGamesPane(engines: engines, selectedPath: $selectedPath)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await reload() }
    }

    private var installs: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(language.text(.engineHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if engines.isEmpty {
                    Text(language.text(.engineNone))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(engines) { engine in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.title).font(.headline)
                                Text(engine.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Button(language.text(.engineUse)) {
                                note = EngineDesk.rememberGlobal(engine.path)
                                    ? language.text(.engineSaved)
                                    : language.text(.engineInvalid)
                                if note == language.text(.engineSaved) {
                                    selectedPath = engine.path
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Button(language.text(.engineBindFile), action: bindFile)
                Picker(language.text(.engineForGame), selection: $gameID) {
                    ForEach(WindowsApp.samples.filter { $0.kind == .game }) { app in
                        Text(app.localizedName(language.currentLanguage)).tag(app.id)
                    }
                }
                Picker(language.text(.engineUse), selection: Binding(
                    get: { EngineDesk.path(for: gameID) ?? "" },
                    set: { EngineDesk.setOverride($0.isEmpty ? nil : $0, for: gameID) }
                )) {
                    Text(language.text(.engineFollow)).tag("")
                    ForEach(engines) { engine in
                        Text(engine.title).tag(engine.path)
                    }
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() async {
        let found = await Task.detached(priority: .utility) {
            EngineDesk.scan()
        }.value
        engines = found
        let saved = UserDefaults.standard.string(forKey: WineLocator.defaultsKey).map { ($0 as NSString).expandingTildeInPath } ?? ""
        if selectedPath.isEmpty || !found.contains(where: { $0.path == selectedPath }) {
            selectedPath = found.first { $0.path == saved }?.path ?? found.first?.path ?? ""
        }
    }

    private func bindFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if EngineDesk.rememberGlobal(url.path) {
            selectedPath = (url.path as NSString).expandingTildeInPath
            note = language.text(.engineSaved)
            Task { await reload() }
        } else {
            note = language.text(.engineInvalid)
        }
    }
}

private enum EngineDeskPage {
    case installs
    case downloads
    case games
}
