//
//  GameRecipes.swift
//
//  按游戏名称或 Steam 编号匹配一份渲染食谱。食谱只写入现有的 GamePreset，
//  启动时仍由 AppLauncher 决定哪些环境变量真的传给 wine64。
//

import Foundation

nonisolated struct GameRecipe: Identifiable, Hashable {
    let id: String
    let title: String
    let steamAppIDs: [String]
    let exactNames: [String]
    let nameNeedles: [String]
    let preset: GamePreset
    let noteKey: L10nKey
}

nonisolated enum GameRecipeManager {
    static func match(name: String, steamAppID: String?, platform: AppPlatform) -> GameRecipe? {
        guard platform == .windows else { return nil }
        let steam = steamAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !steam.isEmpty, let found = catalog.first(where: { $0.steamAppIDs.contains(steam) }) {
            return found
        }
        let exact = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let found = catalog.first(where: { $0.exactNames.contains(exact) }) {
            return found
        }
        let folded = name.lowercased()
        return catalog.first { recipe in
            recipe.nameNeedles.contains { folded.contains($0) }
        }
    }

    static func preset(name: String, steamAppID: String?, tags: [String], platform: AppPlatform) -> GamePreset {
        if let recipe = match(name: name, steamAppID: steamAppID, platform: platform) {
            return recipe.preset
        }
        return GamePresetLibrary.suggested(name: name, tags: tags)
    }

    private static let catalog: [GameRecipe] = [
        valorant, pubg, wukong, cyberpunk, eldenRing, gta, rdr2, baldursGate, monsterHunter, witcher, stardew, steam
    ]

    private static let valorant = GameRecipe(
        id: "recipe.valorant",
        title: "VALORANT",
        steamAppIDs: [],
        exactNames: [],
        nameNeedles: ["valorant", "无畏契约", "瓦罗兰特"],
        preset: tuned(
            id: "recipe.valorant",
            engine: .unrealEngine,
            dxvk: false,
            metal: false,
            desktop: true,
            metalFX: false,
            esync: false,
            fsync: false
        ),
        noteKey: .recipeAntiCheat
    )

    private static let pubg = GameRecipe(
        id: "recipe.pubg",
        title: "PUBG",
        steamAppIDs: ["578080"],
        exactNames: [],
        nameNeedles: ["pubg", "绝地求生"],
        preset: tuned(
            id: "recipe.pubg",
            engine: .unrealEngine,
            dxvk: false,
            metal: false,
            desktop: true,
            metalFX: false,
            esync: false,
            fsync: false
        ),
        noteKey: .recipeAntiCheat
    )

    private static let wukong = GameRecipe(
        id: "recipe.wukong",
        title: "黑神话：悟空",
        steamAppIDs: ["2358720"],
        exactNames: [],
        nameNeedles: ["黑神话", "wukong", "black myth"],
        preset: tuned(id: "recipe.wukong", engine: .directX12, dxvk: true, metal: true, desktop: false, metalFX: true, esync: true, fsync: true),
        noteKey: .recipeSinglePlayer
    )

    private static let cyberpunk = GameRecipe(
        id: "recipe.cyberpunk",
        title: "赛博朋克 2077",
        steamAppIDs: ["1091500"],
        exactNames: [],
        nameNeedles: ["cyberpunk", "赛博朋克"],
        preset: tuned(id: "recipe.cyberpunk", engine: .directX12, dxvk: true, metal: true, desktop: false, metalFX: true, esync: true, fsync: true),
        noteKey: .recipeSinglePlayer
    )

    private static let eldenRing = GameRecipe(
        id: "recipe.elden",
        title: "艾尔登法环",
        steamAppIDs: ["1245620"],
        exactNames: [],
        nameNeedles: ["elden ring", "艾尔登法环"],
        preset: tuned(id: "recipe.elden", engine: .directX12, dxvk: true, metal: true, desktop: false, metalFX: true, esync: true, fsync: true),
        noteKey: .recipeOnline
    )

    private static let gta = GameRecipe(
        id: "recipe.gta5",
        title: "GTA 5",
        steamAppIDs: ["271590"],
        exactNames: [],
        nameNeedles: ["gta", "grand theft auto"],
        preset: tuned(id: "recipe.gta5", engine: .directX11, dxvk: true, metal: true, desktop: false, metalFX: true, esync: true, fsync: true),
        noteKey: .recipeOnline
    )

    private static let rdr2 = GameRecipe(
        id: "recipe.rdr2",
        title: "荒野大镖客：救赎 2",
        steamAppIDs: ["1174180"],
        exactNames: [],
        nameNeedles: ["red dead", "荒野大镖客"],
        preset: tuned(id: "recipe.rdr2", engine: .directX12, dxvk: true, metal: true, desktop: false, metalFX: true, esync: true, fsync: true),
        noteKey: .recipeOnline
    )

    private static let baldursGate = GameRecipe(
        id: "recipe.bg3",
        title: "博德之门 3",
        steamAppIDs: ["1086940"],
        exactNames: [],
        nameNeedles: ["baldur", "博德之门"],
        preset: tuned(id: "recipe.bg3", engine: .directX11, dxvk: true, metal: true, desktop: false, metalFX: true, esync: true, fsync: true),
        noteKey: .recipeSinglePlayer
    )

    private static let monsterHunter = GameRecipe(
        id: "recipe.mhw",
        title: "怪物猎人：世界",
        steamAppIDs: ["582010"],
        exactNames: [],
        nameNeedles: ["monster hunter", "怪物猎人"],
        preset: tuned(id: "recipe.mhw", engine: .directX11, dxvk: true, metal: true, desktop: false, metalFX: false, esync: true, fsync: true),
        noteKey: .recipeSinglePlayer
    )

    private static let witcher = GameRecipe(
        id: "recipe.witcher3",
        title: "巫师 3",
        steamAppIDs: ["292030"],
        exactNames: [],
        nameNeedles: ["witcher", "巫师 3", "巫师3"],
        preset: tuned(id: "recipe.witcher3", engine: .directX11, dxvk: true, metal: true, desktop: false, metalFX: true, esync: true, fsync: true),
        noteKey: .recipeSinglePlayer
    )

    private static let stardew = GameRecipe(
        id: "recipe.stardew",
        title: "星露谷物语",
        steamAppIDs: ["413150"],
        exactNames: [],
        nameNeedles: ["stardew", "星露谷"],
        preset: tuned(id: "recipe.stardew", engine: .directX11, dxvk: true, metal: false, desktop: false, metalFX: false, esync: false, fsync: false),
        noteKey: .recipeLight
    )

    private static let steam = GameRecipe(
        id: "recipe.steam",
        title: "Steam",
        steamAppIDs: ["753"],
        exactNames: ["steam"],
        nameNeedles: [],
        preset: tuned(id: "recipe.steam", engine: .directX11, dxvk: false, metal: false, desktop: false, metalFX: false, esync: false, fsync: false),
        noteKey: .recipeSteamClient
    )

    private static func tuned(
        id: String,
        engine: GameEngineType,
        dxvk: Bool,
        metal: Bool,
        desktop: Bool,
        metalFX: Bool,
        esync: Bool,
        fsync: Bool
    ) -> GamePreset {
        GamePreset(
            id: id,
            engineType: engine,
            dxvkEnabled: dxvk,
            d3dMetalEnabled: metal,
            requiredRuntimes: dxvk ? ["vcrun2022", "dxvk"] : ["vcrun2022"],
            virtualDesktop: desktop,
            metalFXEnabled: metalFX,
            esyncEnabled: esync,
            fsyncEnabled: fsync
        )
    }
}
