//
//  GamePresets.swift
//
//  按标签或模板给一款游戏选好渲染后端。启动仍走原来的 wine64 参数：
//  DXVK 受授权限制，D3DMetal 只在 CrossOver 下写入。
//

import SwiftUI

nonisolated enum GameEngineType: String, Codable, CaseIterable, Identifiable {
    case unrealEngine = "UnrealEngine"
    case unity = "Unity"
    case directX11 = "DirectX11"
    case directX12 = "DirectX12"

    var id: String { rawValue }

    var titleKey: L10nKey {
        switch self {
        case .unrealEngine: return .presetEngineUnreal
        case .unity: return .presetEngineUnity
        case .directX11: return .presetEngineDX11
        case .directX12: return .presetEngineDX12
        }
    }
}

nonisolated struct GamePreset: Codable, Hashable, Identifiable {
    var id: String
    var engineType: GameEngineType
    var dxvkEnabled: Bool
    var d3dMetalEnabled: Bool
    var requiredRuntimes: [String]
    var virtualDesktop: Bool
    var metalFXEnabled: Bool = false
    var esyncEnabled: Bool = false
    var fsyncEnabled: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, engineType, dxvkEnabled, d3dMetalEnabled, requiredRuntimes, virtualDesktop
        case metalFXEnabled, esyncEnabled, fsyncEnabled
    }

    init(
        id: String,
        engineType: GameEngineType,
        dxvkEnabled: Bool,
        d3dMetalEnabled: Bool,
        requiredRuntimes: [String],
        virtualDesktop: Bool,
        metalFXEnabled: Bool = false,
        esyncEnabled: Bool = false,
        fsyncEnabled: Bool = false
    ) {
        self.id = id
        self.engineType = engineType
        self.dxvkEnabled = dxvkEnabled
        self.d3dMetalEnabled = d3dMetalEnabled
        self.requiredRuntimes = requiredRuntimes
        self.virtualDesktop = virtualDesktop
        self.metalFXEnabled = metalFXEnabled
        self.esyncEnabled = esyncEnabled
        self.fsyncEnabled = fsyncEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        engineType = try container.decode(GameEngineType.self, forKey: .engineType)
        dxvkEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxvkEnabled) ?? false
        d3dMetalEnabled = try container.decodeIfPresent(Bool.self, forKey: .d3dMetalEnabled) ?? false
        requiredRuntimes = try container.decodeIfPresent([String].self, forKey: .requiredRuntimes) ?? []
        virtualDesktop = try container.decodeIfPresent(Bool.self, forKey: .virtualDesktop) ?? false
        metalFXEnabled = try container.decodeIfPresent(Bool.self, forKey: .metalFXEnabled) ?? false
        esyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .esyncEnabled) ?? false
        fsyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .fsyncEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(engineType, forKey: .engineType)
        try container.encode(dxvkEnabled, forKey: .dxvkEnabled)
        try container.encode(d3dMetalEnabled, forKey: .d3dMetalEnabled)
        try container.encode(requiredRuntimes, forKey: .requiredRuntimes)
        try container.encode(virtualDesktop, forKey: .virtualDesktop)
        try container.encode(metalFXEnabled, forKey: .metalFXEnabled)
        try container.encode(esyncEnabled, forKey: .esyncEnabled)
        try container.encode(fsyncEnabled, forKey: .fsyncEnabled)
    }
}

nonisolated enum GamePresetLibrary {
    static let shooter = GamePreset(
        id: "shooter",
        engineType: .unrealEngine,
        dxvkEnabled: true,
        d3dMetalEnabled: false,
        requiredRuntimes: ["vcrun2022", "dxvk"],
        virtualDesktop: false,
        metalFXEnabled: true,
        esyncEnabled: true,
        fsyncEnabled: true
    )
    static let rpg = GamePreset(
        id: "rpg",
        engineType: .directX11,
        dxvkEnabled: true,
        d3dMetalEnabled: true,
        requiredRuntimes: ["vcrun2022", "dxvk"],
        virtualDesktop: false,
        metalFXEnabled: true,
        esyncEnabled: true,
        fsyncEnabled: true
    )
    static let action = GamePreset(
        id: "action",
        engineType: .unrealEngine,
        dxvkEnabled: true,
        d3dMetalEnabled: false,
        requiredRuntimes: ["vcrun2022", "dxvk"],
        virtualDesktop: false,
        metalFXEnabled: true,
        esyncEnabled: true,
        fsyncEnabled: true
    )
    static let utility = GamePreset(
        id: "utility",
        engineType: .directX11,
        dxvkEnabled: false,
        d3dMetalEnabled: false,
        requiredRuntimes: ["vcrun2022"],
        virtualDesktop: true
    )
    static let unreal = GamePreset(
        id: "unreal",
        engineType: .unrealEngine,
        dxvkEnabled: true,
        d3dMetalEnabled: false,
        requiredRuntimes: ["vcrun2022", "dxvk"],
        virtualDesktop: false,
        metalFXEnabled: true,
        esyncEnabled: true,
        fsyncEnabled: true
    )
    static let unity = GamePreset(
        id: "unity",
        engineType: .unity,
        dxvkEnabled: true,
        d3dMetalEnabled: false,
        requiredRuntimes: ["vcrun2022", "dxvk"],
        virtualDesktop: false,
        metalFXEnabled: true,
        esyncEnabled: true,
        fsyncEnabled: true
    )
    static let directX11 = GamePreset(
        id: "dx11",
        engineType: .directX11,
        dxvkEnabled: true,
        d3dMetalEnabled: false,
        requiredRuntimes: ["vcrun2022", "dxvk"],
        virtualDesktop: false,
        metalFXEnabled: true,
        esyncEnabled: true,
        fsyncEnabled: true
    )
    static let directX12 = GamePreset(
        id: "dx12",
        engineType: .directX12,
        dxvkEnabled: true,
        d3dMetalEnabled: true,
        requiredRuntimes: ["vcrun2022", "dxvk"],
        virtualDesktop: false,
        metalFXEnabled: true,
        esyncEnabled: true,
        fsyncEnabled: true
    )

    static var tagPresets: [GamePreset] { [shooter, rpg, action, utility] }
    static var enginePresets: [GamePreset] { [unreal, unity, directX11, directX12] }

    static func preset(id: String) -> GamePreset? {
        (tagPresets + enginePresets).first { $0.id == id }
    }

    static func titleKey(for id: String) -> L10nKey {
        switch id {
        case shooter.id: return .presetShooter
        case rpg.id: return .presetRPG
        case action.id: return .presetAction
        case utility.id: return .presetUtility
        case unreal.id: return .presetEngineUnreal
        case unity.id: return .presetEngineUnity
        case directX11.id: return .presetEngineDX11
        case directX12.id: return .presetEngineDX12
        default: return .presetCustom
        }
    }

    /// 射击优先于 RPG，再是动作。名称里带 Unreal 或 Unity 时用对应引擎模板。
    static func suggested(name: String, tags: [String]) -> GamePreset {
        let joined = (tags + [name]).joined(separator: " ").lowercased()
        if tags.contains(where: { $0.localizedCaseInsensitiveContains("射击") }) || joined.contains("shooter") {
            return shooter
        }
        if tags.contains(where: { $0.caseInsensitiveCompare("RPG") == .orderedSame || $0.localizedCaseInsensitiveContains("rpg") }) {
            return rpg
        }
        if tags.contains(where: { $0.localizedCaseInsensitiveContains("动作") }) || joined.contains("action") {
            return action
        }
        if joined.contains("unreal") || joined.contains("-shipping") {
            return unreal
        }
        if joined.contains("unity") {
            return unity
        }
        if tags.contains(where: { $0.localizedCaseInsensitiveContains("工具") }) {
            return utility
        }
        return rpg
    }

    static func translation(for preset: GamePreset, host: HostEngine?) -> TranslationEngine {
        if preset.d3dMetalEnabled, host == .crossover {
            return .d3dmetal
        }
        if preset.dxvkEnabled {
            return .dxvk
        }
        if preset.d3dMetalEnabled {
            return .d3dmetal
        }
        return .metal
    }

    static func runtimeReady(_ name: String) -> Bool {
        switch name {
        case "dxvk":
            return true
        case "vcrun2022":
            let dll = StorageMeasure.currentPrefix()
                .appendingPathComponent("drive_c/windows/system32/vcruntime140.dll")
            return FileManager.default.fileExists(atPath: dll.path)
        default:
            return false
        }
    }
}

enum GamePresetStore {
    static func saved(for app: WindowsApp) -> GamePreset? {
        guard let data = UserDefaults.standard.data(forKey: appKey(app.playtimeKey)) else { return nil }
        return try? JSONDecoder().decode(GamePreset.self, from: data)
    }

    static func usesVirtualDesktop(for app: WindowsApp) -> Bool {
        if let saved = saved(for: app) {
            return saved.virtualDesktop
        }
        guard let bottle = app.bottle, let preset = savedBottle(named: bottle) else { return false }
        return preset.virtualDesktop
    }

    static func launchTuning(for app: WindowsApp) -> (esync: Bool, fsync: Bool, metalFX: Bool) {
        let preset = saved(for: app) ?? app.bottle.flatMap { savedBottle(named: $0) }
        return (
            preset?.esyncEnabled ?? false,
            preset?.fsyncEnabled ?? false,
            preset?.metalFXEnabled ?? false
        )
    }

    static func apply(_ preset: GamePreset, to app: WindowsApp, host: HostEngine?) {
        guard let data = try? JSONEncoder().encode(preset) else { return }
        UserDefaults.standard.set(data, forKey: appKey(app.playtimeKey))
        TranslationEngine.remember(GamePresetLibrary.translation(for: preset, host: host), for: app)
        print("【预设】已应用 \(preset.id) engine=\(preset.engineType.rawValue) DXVK=\(preset.dxvkEnabled) D3DMetal=\(preset.d3dMetalEnabled) MetalFX=\(preset.metalFXEnabled) ESync=\(preset.esyncEnabled) FSync=\(preset.fsyncEnabled) 虚拟桌面=\(preset.virtualDesktop)")
    }

    static func rememberBottle(_ presetID: String, name: String) {
        guard let preset = GamePresetLibrary.preset(id: presetID),
              let data = try? JSONEncoder().encode(preset) else { return }
        UserDefaults.standard.set(data, forKey: bottleKey(name))
    }

    private static func savedBottle(named name: String) -> GamePreset? {
        guard let data = UserDefaults.standard.data(forKey: bottleKey(name)) else { return nil }
        return try? JSONDecoder().decode(GamePreset.self, from: data)
    }

    private static func appKey(_ token: String) -> String {
        "MyApp.gamePreset." + token
    }

    private static func bottleKey(_ name: String) -> String {
        "MyApp.bottlePreset." + name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct GamePresetCard: View {
    let program: WindowsApp
    let host: HostEngine?
    let onApply: (GamePreset) -> Void
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var license = LicenseManager.shared
    @State private var preset = GamePresetLibrary.rpg
    @State private var applied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            templateRow(GamePresetLibrary.tagPresets)
            templateRow(GamePresetLibrary.enginePresets)
            toggles
            runtimes
            Text(language.text(.presetHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear(perform: reload)
        .onChange(of: program.id) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .vestaLibraryRestored)) { _ in
            reload()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.text(.presetSection))
                .font(.headline)
            Text(headline)
                .font(.subheadline.weight(.semibold))
            Text(language.text(preset.engineType.titleKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(language.text(matchedRecipe?.noteKey ?? .recipeGeneric))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(language.text(.recipeApply), action: applyRecipe)
                    .controlSize(.small)
                if !applied {
                    Button(language.text(.presetApply), action: applyCurrent)
                        .controlSize(.small)
                }
            }
        }
    }

    private var matchedRecipe: GameRecipe? {
        GameRecipeManager.match(
            name: program.name,
            steamAppID: program.steamAppID,
            platform: program.platform
        )
    }

    private var headline: String {
        if let recipe = matchedRecipe, preset.id == recipe.preset.id {
            return recipe.title
        }
        return language.text(GamePresetLibrary.titleKey(for: preset.id))
    }

    private func templateRow(_ presets: [GamePreset]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(presets) { item in
                    Button(language.text(GamePresetLibrary.titleKey(for: item.id))) {
                        preset = item
                        applied = true
                        onApply(item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(preset.id == item.id && applied ? Color.accentColor : Color.secondary)
                }
            }
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(.profileHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    profileButton(.performance, title: .performanceMode)
                    if host == .crossover {
                        profileButton(.balanced, title: .balancedMode)
                    }
                }
            }
            Text(language.text(.graphicsBackend))
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    backendButton(.metal, title: "Metal", locked: false)
                    backendButton(.dxvk, title: "DXVK", locked: !license.hasProAccess)
                    if host == .crossover {
                        backendButton(.d3dmetal, title: "D3DMetal", locked: false)
                    }
                }
            }
            if host != .crossover, preset.d3dMetalEnabled {
                Text(language.text(.presetD3DMetalWine))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(language.text(.graphicsSync))
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    syncButton(.off, title: language.text(.syncOff), locked: false)
                    syncButton(.esync, title: "ESync", locked: !license.hasProAccess)
                    syncButton(.fsync, title: "FSync", locked: !license.hasProAccess)
                }
            }
            Text(language.text(WineSyncProbe.supportsFsync() ? .presetFsyncReady : .presetFsyncFallback))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(language.text(.presetVirtualDesktop), isOn: desktopBinding)
            Toggle(language.text(.presetMetalFX), isOn: metalFXBinding)
                .disabled(!license.hasProAccess)
            Text(metalFXNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !license.hasProAccess {
                Text(language.text(.proLockedHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runtimes: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(preset.requiredRuntimes, id: \.self) { name in
                Text(runtimeLine(name))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func runtimeLine(_ name: String) -> String {
        if name == "dxvk" {
            return preset.dxvkEnabled ? language.text(.presetDXVKOn) : language.text(.presetDXVKOff)
        }
        let ready = GamePresetLibrary.runtimeReady(name)
        return language.text(ready ? .presetRuntimeReady : .presetRuntimeMissing)
    }

    private var displayedEngine: TranslationEngine {
        var engine = GamePresetLibrary.translation(for: preset, host: host)
        if host != .crossover, engine == .d3dmetal {
            engine = .metal
        }
        return engine
    }

    private var displayedSync: WineSyncChoice {
        if preset.fsyncEnabled { return .fsync }
        if preset.esyncEnabled { return .esync }
        return .off
    }

    private func profileButton(_ profile: LaunchProfile, title: L10nKey) -> some View {
        let selected = LaunchProfile.matching(displayedEngine) == profile
        return Button(language.text(title)) {
            chooseBackend(profile.engine)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(profile == .performance && !license.hasProAccess)
        .tint(selected ? Color.accentColor : Color.secondary)
    }

    private func backendButton(_ engine: TranslationEngine, title: String, locked: Bool) -> some View {
        Button(title) {
            chooseBackend(engine)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(locked)
        .tint(displayedEngine == engine ? Color.accentColor : Color.secondary)
    }

    private func syncButton(_ choice: WineSyncChoice, title: String, locked: Bool) -> some View {
        Button(title) {
            chooseSync(choice)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(locked)
        .tint(displayedSync == choice ? Color.accentColor : Color.secondary)
    }

    private func chooseBackend(_ engine: TranslationEngine) {
        if engine == .dxvk, !license.hasProAccess { return }
        var next = preset
        switch engine {
        case .dxvk:
            next.dxvkEnabled = true
            next.d3dMetalEnabled = false
        case .d3dmetal:
            next.d3dMetalEnabled = true
            next.dxvkEnabled = false
        case .metal:
            next.dxvkEnabled = false
            next.d3dMetalEnabled = false
        }
        commit(next)
    }

    private func chooseSync(_ choice: WineSyncChoice) {
        if choice != .off, !license.hasProAccess { return }
        var next = preset
        switch choice {
        case .off:
            next.esyncEnabled = false
            next.fsyncEnabled = false
        case .esync:
            next.esyncEnabled = true
            next.fsyncEnabled = false
        case .fsync:
            next.esyncEnabled = false
            next.fsyncEnabled = true
        }
        commit(next)
    }

    private var desktopBinding: Binding<Bool> {
        Binding(
            get: { preset.virtualDesktop },
            set: { newValue in
                var next = preset
                next.virtualDesktop = newValue
                commit(next)
            }
        )
    }

    private var metalFXBinding: Binding<Bool> {
        Binding(
            get: { preset.metalFXEnabled },
            set: { newValue in
                var next = preset
                next.metalFXEnabled = newValue
                if newValue {
                    next.d3dMetalEnabled = true
                }
                commit(next)
            }
        )
    }

    private var metalFXNote: String {
        if !MetalFXSupport.available {
            return language.text(.presetMetalFXUnsupported)
        }
        if host != .crossover {
            return language.text(.presetMetalFXWine)
        }
        return language.text(.presetMetalFXReady)
    }

    private func applyRecipe() {
        let next = GameRecipeManager.preset(
            name: program.name,
            steamAppID: program.steamAppID,
            tags: program.displayTags,
            platform: program.platform
        )
        commit(next)
    }

    private func applyCurrent() {
        applied = true
        onApply(preset)
    }

    private func commit(_ next: GamePreset) {
        preset = next
        applied = true
        onApply(next)
    }

    private func reload() {
        if let saved = GamePresetStore.saved(for: program) {
            preset = saved
            applied = true
        } else {
            preset = GameRecipeManager.preset(
                name: program.name,
                steamAppID: program.steamAppID,
                tags: program.displayTags,
                platform: program.platform
            )
            applied = false
        }
    }
}

private enum WineSyncChoice {
    case off
    case esync
    case fsync
}
