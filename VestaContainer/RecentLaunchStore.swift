//
//  RecentLaunchStore.swift
//
//  记住最近成功启动的游戏，供菜单栏直接再启动一次。
//

import Combine
import Foundation
import SwiftUI

struct RecentLaunch: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var installPath: String
    var bottleName: String
    var enablesDXVK: Bool
    var enablesMetal3: Bool
    var enablesEsync: Bool
    var bottleIsKnown: Bool
    var isMacApp: Bool
    var extraArguments: [String]
    var directExecutable: Bool
    var usesVirtualDesktop: Bool
    var enablesMetalFX: Bool
    var enablesFsync: Bool

    init(_ request: LaunchRequest) {
        id = request.appID
        name = request.name
        installPath = request.installPath
        bottleName = request.bottleName
        enablesDXVK = request.enablesDXVK
        enablesMetal3 = request.enablesMetal3
        enablesEsync = request.enablesEsync
        bottleIsKnown = request.bottleIsKnown
        isMacApp = request.isMacApp
        extraArguments = request.extraArguments
        directExecutable = request.directExecutable
        usesVirtualDesktop = request.usesVirtualDesktop
        enablesMetalFX = request.enablesMetalFX
        enablesFsync = request.enablesFsync
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        installPath = try container.decode(String.self, forKey: .installPath)
        bottleName = try container.decode(String.self, forKey: .bottleName)
        enablesDXVK = try container.decode(Bool.self, forKey: .enablesDXVK)
        enablesMetal3 = try container.decode(Bool.self, forKey: .enablesMetal3)
        enablesEsync = try container.decode(Bool.self, forKey: .enablesEsync)
        bottleIsKnown = try container.decode(Bool.self, forKey: .bottleIsKnown)
        isMacApp = try container.decode(Bool.self, forKey: .isMacApp)
        extraArguments = try container.decodeIfPresent([String].self, forKey: .extraArguments) ?? []
        directExecutable = try container.decodeIfPresent(Bool.self, forKey: .directExecutable) ?? false
        usesVirtualDesktop = try container.decodeIfPresent(Bool.self, forKey: .usesVirtualDesktop) ?? false
        enablesMetalFX = try container.decodeIfPresent(Bool.self, forKey: .enablesMetalFX) ?? false
        enablesFsync = try container.decodeIfPresent(Bool.self, forKey: .enablesFsync) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(installPath, forKey: .installPath)
        try container.encode(bottleName, forKey: .bottleName)
        try container.encode(enablesDXVK, forKey: .enablesDXVK)
        try container.encode(enablesMetal3, forKey: .enablesMetal3)
        try container.encode(enablesEsync, forKey: .enablesEsync)
        try container.encode(bottleIsKnown, forKey: .bottleIsKnown)
        try container.encode(isMacApp, forKey: .isMacApp)
        try container.encode(extraArguments, forKey: .extraArguments)
        try container.encode(directExecutable, forKey: .directExecutable)
        try container.encode(usesVirtualDesktop, forKey: .usesVirtualDesktop)
        try container.encode(enablesMetalFX, forKey: .enablesMetalFX)
        try container.encode(enablesFsync, forKey: .enablesFsync)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, installPath, bottleName, enablesDXVK, enablesMetal3, enablesEsync
        case bottleIsKnown, isMacApp, extraArguments, directExecutable, usesVirtualDesktop
        case enablesMetalFX, enablesFsync
    }

    var request: LaunchRequest {
        LaunchRequest(
            appID: id,
            name: name,
            installPath: installPath,
            bottleName: bottleName,
            enablesDXVK: enablesDXVK,
            enablesMetal3: enablesMetal3,
            enablesEsync: enablesEsync,
            bottleIsKnown: bottleIsKnown,
            isMacApp: isMacApp,
            extraArguments: extraArguments,
            directExecutable: directExecutable,
            usesVirtualDesktop: usesVirtualDesktop,
            enablesMetalFX: enablesMetalFX,
            enablesFsync: enablesFsync
        )
    }
}

@MainActor
final class RecentLaunchStore: ObservableObject {
    static let shared = RecentLaunchStore()

    @Published private(set) var recents: [RecentLaunch] = []
    @Published var lastMessage = ""

    private static let storageKey = "MyApp.recentLaunches"
    private let limit = 8

    var libraryGames: [WindowsApp] {
        Array(WindowsApp.samples.filter { $0.kind == .game }.prefix(6))
    }

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([RecentLaunch].self, from: data)
        else { return }
        recents = saved
    }

    func remember(_ request: LaunchRequest) {
        var next = recents.filter { $0.id != request.appID }
        next.insert(RecentLaunch(request), at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        recents = next
        persist()
    }

    func title(for item: RecentLaunch, language: AppLanguage) -> String {
        let base: String
        if let app = WindowsApp.samples.first(where: { $0.id == item.id }) {
            base = app.localizedName(language)
        } else {
            base = item.name
        }
        if LaunchSessionStore.shared.isRunning(item.id) {
            return base + " · " + L10n.string(.running, language: language)
        }
        return base
    }

    func launch(_ item: RecentLaunch) {
        Task {
            let result = await AppLauncher.launch(item.request)
            lastMessage = result.message
            if result.succeeded {
                remember(item.request)
            }
        }
    }

    func launch(_ app: WindowsApp) {
        launch(RecentLaunch(request(for: app)))
    }

    private func request(for app: WindowsApp) -> LaunchRequest {
        let bottle = Bottle.samples.first {
            $0.name.caseInsensitiveCompare(app.bottle ?? "") == .orderedSame
        }
        let engine = TranslationEngine.current(for: app, bottle: bottle)
        if app.platform == .macOS {
            let expanded = (app.installPath as NSString).expandingTildeInPath
            return LaunchRequest(
                appID: app.id,
                name: app.name,
                installPath: expanded,
                bottleName: "",
                enablesDXVK: false,
                enablesMetal3: false,
                enablesEsync: false,
                bottleIsKnown: false,
                isMacApp: true
            )
        }
        return LaunchRequest(
            appID: app.id,
            name: app.name,
            installPath: app.installPath,
            bottleName: bottle?.name ?? app.bottle ?? "",
            enablesDXVK: engine.enablesDXVK,
            enablesMetal3: engine.enablesMetal3,
            enablesEsync: GamePresetStore.launchTuning(for: app).esync || (GamePresetStore.saved(for: app) == nil && (bottle?.enablesEsync ?? false)),
            bottleIsKnown: bottle != nil,
            isMacApp: false,
            directExecutable: true,
            usesVirtualDesktop: GamePresetStore.usesVirtualDesktop(for: app),
            enablesMetalFX: GamePresetStore.launchTuning(for: app).metalFX,
            enablesFsync: GamePresetStore.launchTuning(for: app).fsync
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

struct RecentGamesMenu: View {
    @ObservedObject private var store = RecentLaunchStore.shared
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        recentSection
        if store.recents.isEmpty {
            librarySection
        }
        if !store.lastMessage.isEmpty {
            Divider()
            Text(store.lastMessage)
        }
    }

    private var recentSection: some View {
        Section(language.text(.recentGames)) {
            if store.recents.isEmpty {
                Text(language.text(.noRecentGames))
            } else {
                ForEach(store.recents) { item in
                    Button(store.title(for: item, language: language.currentLanguage)) {
                        store.launch(item)
                    }
                }
            }
        }
    }

    private var librarySection: some View {
        Section(language.text(.libraryShortcuts)) {
            ForEach(store.libraryGames) { app in
                Button(app.localizedName(language.currentLanguage)) {
                    store.launch(app)
                }
            }
        }
    }
}
