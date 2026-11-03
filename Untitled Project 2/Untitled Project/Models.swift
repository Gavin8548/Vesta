//
//  Models.swift
//
//  界面用到的数据：侧边栏入口、Windows 软件、容器和设置项。
//  不包含任何视图，避免和 SwiftUI 的类型推断搅在一起。
//

import SwiftUI

/// 左侧导航。平台专区下面再套游戏和工具。
public enum SidebarDestination: Hashable, CaseIterable, Identifiable {
    case allApps
    case macOS
    case macGames
    case macTools
    case windows
    case windowsGames
    case windowsTools
    case bottles
    case settings
    case favorites

    public var id: Self { self }

    var title: String {
        localizedTitle(.chinese)
    }

    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .allApps:
            return "🌟 " + L10n.string(.library, language: language)
        case .macOS:
            return L10n.string(.macZone, language: language)
        case .macGames:
            return L10n.string(.macGames, language: language)
        case .macTools:
            return L10n.string(.macTools, language: language)
        case .windows:
            return L10n.string(.windowsZone, language: language)
        case .windowsGames:
            return L10n.string(.windowsGames, language: language)
        case .windowsTools:
            return L10n.string(.windowsTools, language: language)
        case .bottles:
            return L10n.string(.bottles, language: language)
        case .settings:
            return "⚙️ " + L10n.string(.settings, language: language)
        case .favorites:
            return "⭐ " + L10n.string(.favorites, language: language)
        }
    }

    var symbol: String {
        switch self {
        case .allApps:
            return "square.grid.2x2"
        case .macOS:
            return "macwindow"
        case .macGames, .windowsGames:
            return "gamecontroller"
        case .macTools, .windowsTools:
            return "wrench.and.screwdriver"
        case .windows:
            return "pc"
        case .bottles:
            return "cylinder.split.1x2"
        case .settings:
            return "gearshape"
        case .favorites:
            return "star.fill"
        }
    }

    /// 这一项会打开中间的应用列表。
    var showsApps: Bool {
        switch self {
        case .bottles, .settings:
            return false
        case .allApps, .macOS, .macGames, .macTools, .windows, .windowsGames, .windowsTools, .favorites:
            return true
        }
    }

    /// 平台专区及其子分类只看对应平台。
    var platformFilter: AppPlatform? {
        switch self {
        case .macOS, .macGames, .macTools:
            return .macOS
        case .windows, .windowsGames, .windowsTools:
            return .windows
        case .allApps, .bottles, .settings, .favorites:
            return nil
        }
    }

    /// 收藏夹不限平台，只看已点亮星星的项目。
    var favoritesOnly: Bool {
        self == .favorites
    }

    /// 二级分类。游戏看「游戏」；工具看「工具」和「办公」。
    var catalog: AppCatalog? {
        switch self {
        case .macGames, .windowsGames:
            return .game
        case .macTools, .windowsTools:
            return .utility
        case .allApps, .macOS, .windows, .bottles, .settings, .favorites:
            return nil
        }
    }
}

/// 侧边栏二级分类：游戏或工具。
enum AppCatalog {
    case game
    case utility

    /// 工具分类同时收下「工具」和「办公」。平台由侧边栏单独限定。
    func matches(_ app: WindowsApp) -> Bool {
        switch self {
        case .game:
            return app.category == "游戏" || app.kind == .game
        case .utility:
            return app.category == "工具" || app.category == "办公"
        }
    }
}

/// Windows 游戏的启动方式。容器直接跑进程，Steam 交给官方客户端。
enum LaunchMode: String, Hashable, CaseIterable {
    case container
    case steam

    var title: String {
        switch self {
        case .container: return "🖥️ 本地容器运行"
        case .steam: return "🪟 Steam 客户端联动"
        }
    }

    var hint: String {
        switch self {
        case .container:
            return "用 wine64 在 Vesta 自己的容器里启动游戏进程，适合单机 3A。"
        case .steam:
            return "唤醒官方 Steam 客户端，适合联机、正版校验和云存档。"
        }
    }

    private static func storageKey(for app: WindowsApp) -> String {
        let steamID = app.steamAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = steamID.isEmpty ? app.name : steamID
        return "MyApp.launchMode." + token
    }

    /// 用户上次为这款游戏选过的方式。没有记录时返回 nil，沿用游戏自己的默认推荐。
    static func remembered(for app: WindowsApp) -> LaunchMode? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey(for: app)) else { return nil }
        return LaunchMode(rawValue: raw)
    }

    static func remember(_ mode: LaunchMode, for app: WindowsApp) {
        UserDefaults.standard.set(mode.rawValue, forKey: storageKey(for: app))
    }
}

/// 这款游戏启动时使用的图形转译。DXVK、DXMT、系统 Metal、Apple D3DMetal 取一。
enum TranslationEngine: String, CaseIterable, Identifiable {
    case dxvk
    case dxmt
    case metal
    case d3dmetal

    var id: String { rawValue }

    var enablesDXVK: Bool { self == .dxvk }
    var enablesDXMT: Bool { self == .dxmt }
    var enablesMetal3: Bool { self == .d3dmetal }

    private static func storageKey(for app: WindowsApp) -> String {
        let steamID = app.steamAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = steamID.isEmpty ? app.name : steamID
        return "MyApp.translationEngine." + token
    }

    static func remembered(for app: WindowsApp) -> TranslationEngine? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey(for: app)) else { return nil }
        return TranslationEngine(rawValue: raw)
    }

    static func remember(_ engine: TranslationEngine, for app: WindowsApp) {
        UserDefaults.standard.set(engine.rawValue, forKey: storageKey(for: app))
    }

    /// 没选过时沿用容器上的图形开关。wine64 优先 DXVK / DXMT。
    static func current(for app: WindowsApp, bottle: Bottle?) -> TranslationEngine {
        if let saved = remembered(for: app) { return saved }
        if bottle?.enablesDXMT == true { return .dxmt }
        if bottle?.enablesDXVK == true { return .dxvk }
        if bottle?.enablesMetal3 == true { return .d3dmetal }
        return .metal
    }
}

/// 详情页上的两档预设。性能模式走 DXVK，画质平衡模式走 D3DMetal。
enum LaunchProfile: String, CaseIterable, Identifiable {
    case performance
    case balanced

    var id: String { rawValue }

    var engine: TranslationEngine {
        switch self {
        case .performance: return .dxvk
        case .balanced: return .d3dmetal
        }
    }

    static func matching(_ engine: TranslationEngine) -> LaunchProfile? {
        switch engine {
        case .dxvk, .dxmt: return .performance
        case .d3dmetal: return .balanced
        case .metal: return nil
        }
    }
}

/// 应用运行平台。macOS 原生程序不使用 Wine 容器。
nonisolated public enum AppPlatform: String, Hashable, Sendable {
    case windows
    case macOS

    var title: String {
        switch self {
        case .windows: return "Windows"
        case .macOS: return "macOS"
        }
    }
}

/// 软件类别，直接用中文作为原始值，卡片上不用再做一层转换。
public enum AppKind: String, Hashable {
    case game = "游戏"
    case office = "办公"
    case utility = "工具"

    var title: String { rawValue }
}

/// 图标着色。用系统色，浅色和深色外观下都有足够对比度。
public enum AppTint: Hashable {
    case blue, indigo, green, orange, teal, red, cyan, ember, gold

    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .green: return .green
        case .orange: return .orange
        case .teal: return .teal
        case .red: return .red
        case .cyan: return Color(red: 0.05, green: 0.82, blue: 0.78)
        case .ember: return Color(red: 1.0, green: 0.34, blue: 0.08)
        case .gold: return Color(red: 0.86, green: 0.67, blue: 0.28)
        }
    }
}

/// 一条已登记的 Windows 软件或游戏。
public struct WindowsApp: Identifiable, Hashable {
    public let id: UUID
    var name: String
    var publisher: String
    var version: String
    var kind: AppKind
    /// 更细的分类，例如动作、RPG、射击、工具。
    var category: String = ""
    /// 可同时属于多个分类，供顶部筛选和搜索使用。
    var tags: [String] = []
    /// 区服代码。cn 国服，ap 亚服，na 美服，eu 欧服。空字符串表示没有区服。
    var regionCode: String = ""
    /// 海报环境光样式。pubg 使用战术金和烟尘橙，空字符串则按区服或图标色。
    var ambientStyle: String = ""
    var summary: String
    /// 背景故事与核心玩法，详情页简介卡片使用。
    var description: String = ""
    /// PC 官方原版最低配置，例如显卡、处理器和内存。
    var pcMinSpecs: String = ""
    /// 在 Mac 上转译或原生运行时的建议门槛。
    var macMinSpecs: String = ""
    /// 运行注意事项与优化建议。
    var noticeText: String? = nil
    /// 安装所需磁盘空间，单位 GB。为 0 时详情页不显示空间评估。
    var requiredStorageGB: Double = 0
    /// macOS 原生应用不需要容器，此时为 nil。
    var bottleName: String?
    var platform: AppPlatform = .windows
    /// 3A 单机默认走容器，联机游戏默认走 Steam。用户改选后会记住。
    var launchMode: LaunchMode = .container

    /// Windows 游戏且带有 Steam 编号时，详情页才显示启动方式切换。
    var supportsLaunchChoice: Bool {
        let steamID = steamAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard platform == .windows, !steamID.isEmpty else { return false }
        return category == "游戏"
    }

    /// 单机游戏才提供本地 Mod 目录。平台客户端不算。
    var supportsMods: Bool {
        kind == .game && category == "游戏"
    }

    /// 用来和容器的 name、id 做不区分大小写比较。没有容器时为 nil。
    var bottle: String? {
        let trimmed = bottleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
    var installPath: String
    /// 文件选择器授予的访问凭证。下载文件夹里的 exe 之后还要靠它重新打开。
    var importBookmark: Data? = nil
    /// 官网下载页。本地和容器里都没有安装文件时，用来打开浏览器。
    var downloadURL: String? = nil
    /// 宽幅海报。可以是本地图片路径或网址；为空时详情页用色块海报。
    var bannerImage: String? = nil
    /// 海报地址。优先于 bannerImage，支持网址和本地图片路径。
    var bannerImageURL: String? = nil
    /// 按本机文件、容器 C 盘或 Steam 库清单实时判断。
    /// macOS 应用只核对 `/Applications` 与 `~/Applications`。容器目录扫描仍留给显式扫描，避免首帧遍历瓶子。
    var isInstalled: Bool {
        if platform == .macOS || !AppLauncher.looksLikeWindowsPath(installPath) {
            return AppLauncher.isInstalled(platform: platform, path: installPath, bottleName: bottle)
        }
        guard LaunchSafety.backgroundServicesEnabled else { return false }
        if steamAppID == "753" && SteamLibrary.macSteamAppExists() {
            return true
        }
        if AppLauncher.isInstalled(platform: platform, path: installPath, bottleName: bottle) {
            return true
        }
        return SteamLibrary.status(appID: steamAppID, bottleName: bottle) == .installed
    }

    /// 已安装、已在 Steam 库但未下载，或还没入库。
    var availabilityLabel: String {
        switch libraryStatus {
        case .installed: return "已安装"
        case .inLibrary: return "已在库"
        case .absent: return "未安装"
        }
    }

    var availabilityColor: Color {
        switch libraryStatus {
        case .installed: return .green
        case .inLibrary: return .orange
        case .absent: return .secondary
        }
    }

    var libraryStatus: SteamCatalogStatus {
        if platform == .macOS || !AppLauncher.looksLikeWindowsPath(installPath) {
            return isInstalled ? .installed : .absent
        }
        guard LaunchSafety.backgroundServicesEnabled else { return .absent }
        if isInstalled { return .installed }
        return SteamLibrary.status(appID: steamAppID, bottleName: bottle)
    }
    /// 本地资源名，或 SF Symbol 名称。没有网络图标和 Steam 图时用这个符号。
    var iconName: String = ""
    /// 非 Steam 软件的高清 Logo 地址，优先于本地资源和 Steam 图。
    var iconURL: String? = nil
    /// 头像类图标铺满圆角，横版透明 Logo 则留白并垫在主题色上。
    var iconFillsFrame: Bool = false
    /// Assets 或本机图片名。没有 iconURL 时使用。
    var customIconName: String? = nil
    /// Steam 商店应用编号。有值时从官方 CDN 加载海报和 Logo。
    var steamAppID: String? = nil
    var symbolName: String
    var tint: AppTint
    var isRunning: Bool
    /// 正在向系统或容器引擎发起启动，界面显示加载状态。
    var isLaunching: Bool = false
    /// 最近一次启动的简短结果，失败原因也放在这里。
    var launchMessage: String = ""
    var lastRunText: String
    /// 累计游玩秒数。导入的游戏会随 apps.json 一起保存。
    var playtimeSeconds: TimeInterval = 0
    /// 用户从本机导入的程序。预置目录不写入 apps.json。
    var isUserImported: Bool = false
    /// 收藏夹。预置游戏按名称或 Steam 编号记在 apps.json 里，重启后仍然有效。
    var isFavorite: Bool = false
    /// 导入时的 Mac 绝对路径。
    var absolutePath: String = ""

    /// 卡片和筛选使用的分类。样本条目按名称补上预置标签。
    var displayTags: [String] {
        if !tags.isEmpty { return tags }
        return Self.knownTags[name] ?? []
    }

    static let knownTags: [String: [String]] = [
        "黑神话：悟空 (Black Myth: Wukong)": ["动作", "RPG"],
        "赛博朋克 2077 (Cyberpunk 2077)": ["RPG"],
        "艾尔登法环 (Elden Ring)": ["动作", "RPG"],
        "GTA 5 (Grand Theft Auto V)": ["动作"],
        "荒野大镖客：救赎 2 (Red Dead Redemption 2)": ["动作"],
        "博德之门 3 (Baldur's Gate 3)": ["RPG"],
        "怪物猎人：世界 (Monster Hunter: World)": ["动作"],
        "巫师 3：狂猎 (The Witcher 3: Wild Hunt)": ["RPG"],
        "星露谷物语 (Stardew Valley)": ["RPG"],
        "绝地求生 (PUBG)": ["射击", "战术竞技"],
        "Microsoft Word (Windows 容器版)": ["工具"],
        "Microsoft Excel (Windows 容器版)": ["工具"],
        "Microsoft PowerPoint": ["工具"],
        "Notepad++ (Windows 容器版)": ["工具"]
    ]

    /// 启动时优先使用的 exe 绝对路径。没有导入路径时退回安装路径。
    var exePath: String {
        let absolute = absolutePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !absolute.isEmpty { return absolute }
        return installPath
    }

    /// 详情页横版海报地址。已填写的 bannerImageURL 优先，否则用 Steam 宽幅主视觉。
    var bannerURL: String? {
        let explicit = bannerImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }
        let steam = steamAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !steam.isEmpty else { return nil }
        if steam == "753" {
            return SteamArtwork.headerURL(appID: steam)?.absoluteString
        }
        if let hero = SteamArtwork.libraryHeroURL(appID: steam) {
            return hero.absoluteString
        }
        return SteamArtwork.headerURL(appID: steam)?.absoluteString
    }

    /// Steam 商店头图，460×215 左右的宽幅海报。
    var steamHeaderURL: URL? {
        SteamArtwork.headerURL(appID: steamAppID)
    }

    /// Steam 商店透明 Logo。
    var steamLogoURL: URL? {
        SteamArtwork.logoURL(appID: steamAppID)
    }

    static let samples: [WindowsApp] = [
        WindowsApp(
            id: UUID(),
            name: "Steam",
            publisher: "Valve",
            version: "2.10.91",
            kind: .game,
            category: "平台",
            summary: "Valve 的游戏平台。可在容器中打开商店、库，以及已经安装的 Windows 游戏。",
            description: "Valve 的数字发行平台。在这里登录账号、浏览商店、管理游戏库，并让正版游戏完成下载与云存档同步。容器中的 Steam 客户端负责 Windows 游戏的账号校验和启动。",
            pcMinSpecs: "Intel Core i3 / 集成显卡 / 4GB RAM",
            macMinSpecs: "Apple M1 / 8GB 统一内存 / macOS 14+",
            noticeText: "1. Steam 客户端本身占用不高；\n2. 在容器里启动时，请先确认 Gaming 容器已开启 DXVK。",
            requiredStorageGB: 1,
            bottleName: "Gaming",
            installPath: "C:\\Program Files (x86)\\Steam\\steam.exe",
            downloadURL: "https://store.steampowered.com",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/753/header.jpg",
            iconName: "gamecontroller.fill",
            steamAppID: "753",
            symbolName: "gamecontroller.fill",
            tint: .indigo,
            isRunning: false,
            lastRunText: "今天 09:41"
        ),
        WindowsApp(
            id: UUID(),
            name: "黑神话：悟空 (Black Myth: Wukong)",
            publisher: "Game Science",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "游戏科学的动作角色扮演游戏。默认安装在 Gaming 容器的 Steam 库中。",
            description: "一款以中国神话为背景的动作角色扮演游戏。玩家将扮演一位“天命人”，为了探寻昔日传说的真相，踏上一条充满危险与惊奇的西游之路。基于 Unreal Engine 5 打造，战斗系统爽快深邃，完美支持 Mac 兼容层转译。",
            pcMinSpecs: "Intel Core i5-8400 / GTX 1060 (6GB) / 16GB RAM",
            macMinSpecs: "Apple M1 Pro / M2 Pro / M3 或更高 / 16GB 统一内存 / macOS 14+",
            noticeText: "1. 务必在容器中开启 D3DMetal 和 ESync/FSync；\n2. 游戏内建议开启 FSR，渲染比例调至 67%，关闭垂直同步。",
            requiredStorageGB: 130,
            bottleName: "Gaming",
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\BlackMythWukong\\b1\\Binaries\\Win64\\b1-Win64-Shipping.exe",
            downloadURL: "https://store.steampowered.com/app/2358720",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2358720/library_hero.jpg",
            iconName: "figure.martial.arts",
            steamAppID: "2358720",
            symbolName: "figure.martial.arts",
            tint: .orange,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "赛博朋克 2077 (Cyberpunk 2077)",
            publisher: "CD PROJEKT RED",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "夜之城的开放世界角色扮演游戏。可执行文件位于 Steam 库的 x64 目录。",
            description: "一款开放世界动作冒险 RPG 游戏。故事发生在夜之城，一个宏大、充满迷人魅力且危机四伏的未来大都市。玩家扮演一名雇佣兵 V，追寻一种独一无二的植入物。游戏具有极高的自由度与震撼的赛博朋克美学。",
            pcMinSpecs: "Intel Core i7-6700 / GTX 1060 (6GB) / 12GB RAM",
            macMinSpecs: "Apple M1 Max / M2 Pro / M3 或更高 / 16GB 统一内存 / macOS 14+",
            noticeText: "1. 首次加载着色器可能会有微卡，属于正常现象；\n2. 建议将画质预设调至“中”，并开启 FSR 2.1。",
            requiredStorageGB: 70,
            bottleName: "Gaming",
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Cyberpunk 2077\\bin\\x64\\Cyberpunk2077.exe",
            downloadURL: "https://store.steampowered.com/app/1091500",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1091500/library_hero.jpg",
            iconName: "bolt.fill",
            steamAppID: "1091500",
            symbolName: "bolt.fill",
            tint: .teal,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "艾尔登法环 (Elden Ring)",
            publisher: "FromSoftware",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "FromSoftware 的开放世界动作游戏。启动文件在 ELDEN RING 的 Game 目录中。",
            description: "FromSoftware 打造的开放世界动作游戏。交界地破碎之后，玩家化身褪色者，穿越荒野、城堡与地下城，寻找艾尔登法环的碎片。战斗强调观察与出手时机，探索本身也充满未知的奖励与危险。",
            pcMinSpecs: "Intel Core i5-8400 / GTX 1060 (3GB) / 12GB RAM",
            macMinSpecs: "Apple M1 Pro / M2 / 16GB 统一内存 / macOS 14+",
            noticeText: "1. 建议在容器中开启 D3DMetal；\n2. 首次进入时加载着色器会短暂卡顿；\n3. 可将阴影和画质预设调低，以稳住帧率。",
            requiredStorageGB: 60,
            bottleName: "Gaming",
            launchMode: .steam,
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\ELDEN RING\\Game\\eldenring.exe",
            downloadURL: "https://store.steampowered.com/app/1245620",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1245620/library_hero.jpg",
            iconName: "shield.lefthalf.filled",
            steamAppID: "1245620",
            symbolName: "shield.lefthalf.filled",
            tint: .indigo,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "GTA 5 (Grand Theft Auto V)",
            publisher: "Rockstar Games",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "Rockstar 的开放世界游戏。默认从 Gaming 容器里的 GTA5.exe 启动。",
            description: "Rockstar 的现代都市开放世界。玩家在洛圣都的三位主角之间切换，经历一场跨越多年的犯罪故事，从街头委托到精心策划的行动。驾驶、射击与城市生活都留有很高的自由度。",
            pcMinSpecs: "Intel Core i5-3470 / GTX 660 (2GB) / 8GB RAM",
            macMinSpecs: "Apple M1 / 16GB 统一内存 / macOS 14+",
            noticeText: "1. 建议开启 DXVK 或 D3DMetal；\n2. 人口密度和阴影对帧率影响最大，可优先调低这两项。",
            requiredStorageGB: 120,
            bottleName: "Gaming",
            launchMode: .steam,
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Grand Theft Auto V\\GTA5.exe",
            downloadURL: "https://store.steampowered.com/app/271590",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/271590/library_hero.jpg",
            iconName: "car.fill",
            steamAppID: "271590",
            symbolName: "car.fill",
            tint: .green,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "荒野大镖客：救赎 2 (Red Dead Redemption 2)",
            publisher: "Rockstar Games",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "Rockstar 的西部开放世界游戏。默认安装在 Gaming 容器的 Steam 库中。",
            description: "Rockstar Games 倾力打造的史诗级开放世界西部巨作。玩家将扮演亚瑟·摩根和范德林德帮派的成员，在广袤粗犷的美国中西部荒野上四处劫掠、逃亡，体验一段关于荣誉、忠诚与生存的悲壮传奇。",
            pcMinSpecs: "Intel Core i5-2500K / GTX 770 (2GB) / 12GB RAM",
            macMinSpecs: "Apple M2 Pro / M3 或更高 / 16GB 统一内存 / macOS 14+",
            noticeText: "1. 需配合兼容性良好的 DXVK/Vulkan 渲染层；\n2. 建议调低阴影和体积雾质量以大幅提升流畅度。",
            requiredStorageGB: 150,
            bottleName: "Gaming",
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Red Dead Redemption 2\\RDR2.exe",
            downloadURL: "https://store.steampowered.com/app/1174180",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1174180/library_hero.jpg",
            iconName: "map.fill",
            steamAppID: "1174180",
            symbolName: "map.fill",
            tint: .orange,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "博德之门 3 (Baldur's Gate 3)",
            publisher: "Larian Studios",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "拉瑞安的角色扮演游戏。启动文件位于 Baldurs Gate 3 的 bin 目录。",
            description: "由 Larian Studios 精心打造的次世代 RPG 巨作。玩家将在 D&D（龙与地下城）规则的奇幻世界中，组建队伍、自由探索宏大的世界。你的每一个选择都将深刻影响剧情走向，带来无与伦比的沉浸式冒险体验。",
            pcMinSpecs: "Intel Core i5-4690 / GTX 970 / 8GB RAM",
            macMinSpecs: "Apple M1 Pro / M2 / 16GB 内存 / macOS 14+",
            noticeText: "1. 游戏内容宏大，建议预留 150GB 以上固态硬盘空间；\n2. 第三章人多时对 CPU 要求较高，可适当降低同屏人数特效。",
            requiredStorageGB: 150,
            bottleName: "Gaming",
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Baldurs Gate 3\\bin\\bg3.exe",
            downloadURL: "https://store.steampowered.com/app/1086940",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1086940/library_hero.jpg",
            iconName: "dice.fill",
            steamAppID: "1086940",
            symbolName: "dice.fill",
            tint: .indigo,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "怪物猎人：世界 (Monster Hunter: World)",
            publisher: "CAPCOM",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "卡普空的动作游戏。默认从 Gaming 容器里的 MonsterHunterWorld.exe 启动。",
            description: "卡普空的合作狩猎动作游戏。玩家作为调查员深入新大陆，追踪并讨伐体型惊人的怪物，再用采集到的素材打造武器与防具。每次狩猎都要观察环境、寻找弱点和配合同伴。",
            pcMinSpecs: "Intel Core i5-4460 / GTX 760 / 8GB RAM",
            macMinSpecs: "Apple M1 Pro / 16GB 统一内存 / macOS 14+",
            noticeText: "1. 建议在容器中开启 D3DMetal；\n2. 大型怪物战时，可降低阴影和特效质量以保持流畅。",
            requiredStorageGB: 50,
            bottleName: "Gaming",
            launchMode: .steam,
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Monster Hunter World\\MonsterHunterWorld.exe",
            downloadURL: "https://store.steampowered.com/app/582010",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/582010/library_hero.jpg",
            iconName: "pawprint.fill",
            steamAppID: "582010",
            symbolName: "pawprint.fill",
            tint: .teal,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "巫师 3：狂猎 (The Witcher 3: Wild Hunt)",
            publisher: "CD PROJEKT RED",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "CD PROJEKT RED 的角色扮演游戏。可执行文件位于 The Witcher 3 的 x64 目录。",
            description: "CD PROJEKT RED 的奇幻角色扮演游戏。猎魔人杰洛特在战火未平的大陆上寻找失散的养女希里，一路卷入王国、魔物与个人抉择。剑术、法印和炼金术让战斗与调查都有多种做法。",
            pcMinSpecs: "Intel Core i7-4790 / GTX 1060 (6GB) / 8GB RAM",
            macMinSpecs: "Apple M1 Pro / 16GB 统一内存 / macOS 14+",
            noticeText: "1. 建议开启 D3DMetal，并在游戏内打开 FSR；\n2. 毛发与阴影质量较高时占用明显，可先降低这两项。",
            requiredStorageGB: 50,
            bottleName: "Gaming",
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\The Witcher 3\\bin\\x64\\witcher3.exe",
            downloadURL: "https://store.steampowered.com/app/292030",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/292030/library_hero.jpg",
            iconName: "moon.stars.fill",
            steamAppID: "292030",
            symbolName: "moon.stars.fill",
            tint: .green,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "星露谷物语 (Stardew Valley)",
            publisher: "ConcernedApe",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "农场生活模拟游戏。默认安装在 Gaming 容器的 Steam 库中。",
            description: "一款节奏舒缓的田园生活模拟。玩家继承一座荒废农场，在鹈鹕镇耕种、钓鱼、采矿，并与居民渐渐熟络。四季轮转，适合慢慢经营属于自己的一小片土地。",
            pcMinSpecs: "Intel Core 2 Duo / 集成显卡 / 2GB RAM",
            macMinSpecs: "Apple M1 / 8GB 统一内存 / macOS 13+",
            noticeText: "1. 配置要求较低，容器中开启 DXVK 即可；\n2. 若窗口比例异常，可在游戏内改为无边框窗口。",
            requiredStorageGB: 1,
            bottleName: "Gaming",
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Stardew Valley\\Stardew Valley.exe",
            downloadURL: "https://store.steampowered.com/app/413150",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/413150/library_hero.jpg",
            iconName: "leaf.fill",
            steamAppID: "413150",
            symbolName: "leaf.fill",
            tint: .blue,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "生化危机 4：重制版 (Resident Evil 4)",
            publisher: "CAPCOM",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "卡普空的 macOS 原生重制版。直接打开本机的 .app，不使用 Wine 容器。",
            description: "CAPCOM 经典生存恐怖神作的全面现代化重制。故事发生在险恶的欧洲乡村，特工里昂·斯科特·肯尼迪为了拯救被绑架的总统女儿深入虎穴。游戏完美适配 macOS 与 Metal 3，带来惊艳的次世代画质与紧张刺激的枪战体验。",
            pcMinSpecs: "Intel Core i5-7500 / GTX 1050 Ti / 8GB RAM",
            macMinSpecs: "Apple M1 / 8GB 统一内存 / macOS 13.0+",
            noticeText: "macOS 原生适配，完美支持 Metal 3 硬件加速与 MetalFX 动态画质缩放。",
            requiredStorageGB: 60,
            bottleName: nil,
            platform: .macOS,
            installPath: "/Applications/Resident Evil 4.app",
            downloadURL: "https://apps.apple.com/app/id6459882000",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2050650/library_hero.jpg",
            iconName: "scope",
            steamAppID: "2050650",
            symbolName: "scope",
            tint: .red,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "死亡搁浅 导演剪辑版 (Death Stranding Director's Cut)",
            publisher: "Kojima Productions",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "小岛工作室的 macOS 原生版本。已安装时由系统直接打开。",
            description: "著名游戏制作人小岛秀夫打造的颠覆性开放世界大作。在未来的末日废土中，玩家需扮演主角山姆·桥恩斯，跨越满目疮痍的美国大陆运送物资，重新连接孤立的人类社会。支持 MetalFX 升格技术，带来极致的视听震撼。",
            pcMinSpecs: "Intel Core i5-3470 / GTX 1050 / 8GB RAM",
            macMinSpecs: "Apple Silicon M1 / 16GB 统一内存 / macOS 13.3+",
            noticeText: "macOS 原生适配，建议在游戏内开启 MetalFX 质量模式以获得稳定帧率。",
            requiredStorageGB: 80,
            bottleName: nil,
            platform: .macOS,
            installPath: "/Applications/Death Stranding.app",
            downloadURL: "https://apps.apple.com/app/id6449758916",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1850570/library_hero.jpg",
            iconName: "figure.walk",
            steamAppID: "1850570",
            symbolName: "figure.walk",
            tint: .indigo,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "博德之门 3 (Baldur's Gate 3 - Native)",
            publisher: "Larian Studios",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "博德之门 3 的 macOS 原生版，与 Windows 容器里的版本分开列出。",
            description: "由 Larian Studios 精心打造的次世代 RPG 巨作。玩家将在 D&D（龙与地下城）规则的奇幻世界中，组建队伍、自由探索宏大的世界。你的每一个选择都将深刻影响剧情走向，带来无与伦比的沉浸式冒险体验。这一版是 macOS 原生应用，无需 Wine 容器。",
            pcMinSpecs: "Intel Core i5-4690 / GTX 970 / 8GB RAM",
            macMinSpecs: "Apple M1 Pro / M2 / 16GB 内存 / macOS 14+",
            noticeText: "1. 这是 macOS 原生版，无需 Wine 容器；\n2. 建议预留 150GB 以上空间，第三章场景可适当降低同屏特效。",
            requiredStorageGB: 150,
            bottleName: nil,
            platform: .macOS,
            installPath: "/Applications/Baldur's Gate 3.app",
            downloadURL: "https://store.steampowered.com/app/1086940",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1086940/library_hero.jpg",
            iconName: "dice.fill",
            steamAppID: "1086940",
            symbolName: "dice.fill",
            tint: .orange,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "无人深空 (No Man's Sky - Apple Silicon Native)",
            publisher: "Hello Games",
            version: "正式版",
            kind: .game,
            category: "游戏",
            summary: "Hello Games 的 Apple Silicon 原生版。未安装时可以前往商店页面。",
            description: "Hello Games 的宇宙探索游戏。玩家在程序生成的广阔星系中飞行、降落、采集和交易，也可以建立基地，并遇见其他旅行者。Apple Silicon 原生版直接使用 Metal 渲染星空与行星。",
            pcMinSpecs: "Intel Core i3 / GTX 480 / 8GB RAM",
            macMinSpecs: "Apple M1 / M2 / 16GB 统一内存 / macOS 14+",
            noticeText: "1. Apple Silicon 原生版直接使用 Metal；\n2. 可在画质中开启动态分辨率，以换取更稳定的帧率。",
            requiredStorageGB: 25,
            bottleName: nil,
            platform: .macOS,
            installPath: "/Applications/No Man's Sky.app",
            downloadURL: "https://store.steampowered.com/app/275850",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/275850/library_hero.jpg",
            iconName: "sparkles",
            steamAppID: "275850",
            symbolName: "sparkles",
            tint: .teal,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "Microsoft Word (Mac 原生版)",
            publisher: "Microsoft",
            version: "16.89",
            kind: .utility,
            category: "工具",
            summary: "macOS 原生文字处理软件，直接打开本机的 Microsoft Word.app。",
            description: "微软的文字处理软件。用来撰写文章、报告和信函，支持样式、批注和常见的 Office 文档格式。macOS 原生版本可以直接在 Apple 芯片上打开和编辑文档。",
            pcMinSpecs: "Windows 10 / 4GB RAM",
            macMinSpecs: "Apple Silicon / 8GB 统一内存 / macOS 12+",
            noticeText: "macOS 原生办公软件，原生支持 M 系列芯片。",
            bottleName: nil,
            platform: .macOS,
            installPath: "/Applications/Microsoft Word.app",
            downloadURL: "https://www.microsoft.com/microsoft-365/mac/microsoft-365-for-mac",
            bannerImageURL: nil,
            iconName: "doc.richtext.fill",
            iconURL: "https://res.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/png/word_96x1.png",
            customIconName: nil,
            symbolName: "doc.richtext.fill",
            tint: .blue,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "Microsoft Excel (Mac 原生版)",
            publisher: "Microsoft",
            version: "16.89",
            kind: .utility,
            category: "工具",
            summary: "macOS 原生电子表格软件，直接打开本机的 Microsoft Excel.app。",
            description: "微软的电子表格软件。适合整理数据、编写公式、生成图表和数据透视表。macOS 原生版本无需容器，即可处理日常表格和计算。",
            pcMinSpecs: "Windows 10 / 4GB RAM",
            macMinSpecs: "Apple Silicon / 8GB 统一内存 / macOS 12+",
            noticeText: "macOS 原生表格处理软件。",
            bottleName: nil,
            platform: .macOS,
            installPath: "/Applications/Microsoft Excel.app",
            downloadURL: "https://www.microsoft.com/microsoft-365/mac/microsoft-365-for-mac",
            bannerImageURL: nil,
            iconName: "tablecells.fill",
            iconURL: "https://res.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/png/excel_96x1.png",
            customIconName: nil,
            symbolName: "tablecells.fill",
            tint: .green,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "Microsoft PowerPoint (Mac 原生版)",
            publisher: "Microsoft",
            version: "16.89",
            kind: .utility,
            category: "工具",
            summary: "macOS 原生演示文稿软件，直接打开本机的 Microsoft PowerPoint.app。",
            description: "微软的演示文稿软件。用来编排幻灯片、设置动画并直接放映。macOS 原生版本可以打开和播放常见的 PowerPoint 文件。",
            pcMinSpecs: "Windows 10 / 4GB RAM",
            macMinSpecs: "Apple Silicon / 8GB 统一内存 / macOS 12+",
            noticeText: "macOS 原生演示文稿软件。",
            bottleName: nil,
            platform: .macOS,
            installPath: "/Applications/Microsoft PowerPoint.app",
            downloadURL: "https://www.microsoft.com/microsoft-365/mac/microsoft-365-for-mac",
            bannerImageURL: nil,
            iconName: "rectangle.on.rectangle.angled",
            iconURL: "https://res.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/png/powerpoint_96x1.png",
            customIconName: nil,
            symbolName: "rectangle.on.rectangle.angled",
            tint: .orange,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "Microsoft Word (Windows 容器版)",
            publisher: "Microsoft",
            version: "16.89",
            kind: .utility,
            category: "工具",
            summary: "通过 Office 容器运行的 Windows 版 Word。",
            description: "通过 Office 容器运行的 Windows 版 Word。适合需要 Windows 宏、特定加载项，或与 Windows 版式保持一致的文档编辑。账号与文件格式仍由正版 Office 处理。",
            pcMinSpecs: "Windows 10 / 4GB RAM",
            macMinSpecs: "Apple Silicon / 8GB 内存 (Office Bottle)",
            noticeText: "通过 Wine 容器运行的 Windows 版 Word。",
            bottleName: "Office",
            platform: .windows,
            installPath: "C:\\Program Files\\Microsoft Office\\root\\Office16\\WINWORD.EXE",
            bannerImageURL: nil,
            iconName: "doc.richtext.fill",
            iconURL: "https://res.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/png/word_96x1.png",
            customIconName: nil,
            symbolName: "doc.richtext.fill",
            tint: .blue,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "Microsoft Excel (Windows 容器版)",
            publisher: "Microsoft",
            version: "16.89",
            kind: .utility,
            category: "工具",
            summary: "通过 Office 容器运行的 Windows 版 Excel。",
            description: "通过 Office 容器运行的 Windows 版 Excel。适合依赖 Windows 宏、加载项或较复杂工作簿的数据计算，公式与图表能力与 Windows 版保持一致。",
            pcMinSpecs: "Windows 10 / 4GB RAM",
            macMinSpecs: "Apple Silicon / 8GB 内存 (Office Bottle)",
            noticeText: "通过 Wine 容器运行的 Windows 版 Excel。",
            bottleName: "Office",
            platform: .windows,
            installPath: "C:\\Program Files\\Microsoft Office\\root\\Office16\\EXCEL.EXE",
            bannerImageURL: nil,
            iconName: "tablecells.fill",
            iconURL: "https://res.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/png/excel_96x1.png",
            customIconName: nil,
            symbolName: "tablecells.fill",
            tint: .green,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "Microsoft PowerPoint",
            publisher: "Microsoft",
            version: "16.89",
            kind: .utility,
            category: "工具",
            summary: "演示文稿软件，用于制作幻灯片、动画和放映。建议放在 Office 容器中运行。",
            description: "通过 Office 容器运行的 Windows 版 PowerPoint。适合制作和放映需要 Windows 字体、动画或插件环境的演示文稿。",
            pcMinSpecs: "Windows 10 / 4GB RAM",
            macMinSpecs: "Apple Silicon / 8GB 内存 (Office 365 容器)",
            noticeText: "用于演示文稿制作与动画播放。",
            bottleName: "Office",
            platform: .windows,
            installPath: "C:\\Program Files\\Microsoft Office\\root\\Office16\\POWERPNT.EXE",
            bannerImageURL: nil,
            iconName: "rectangle.on.rectangle.angled",
            iconURL: "https://res.cdn.office.net/files/fabric-cdn-prod_20230815.002/assets/brand-icons/product/png/powerpoint_96x1.png",
            customIconName: nil,
            symbolName: "rectangle.on.rectangle.angled",
            tint: .orange,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "绝地求生 (PUBG)",
            publisher: "KRAFTON",
            version: "Live",
            kind: .game,
            category: "游戏",
            tags: ["射击", "战术竞技"],
            ambientStyle: "pubg",
            summary: "百人空降的战术竞技射击。从飞机跳伞，在不断缩小的安全区里搜集装备并生存到最后。",
            description: "《绝地求生》是 KRAFTON 的战术竞技射击游戏。最多一百名玩家跳伞落入同一张地图，在房屋、野外和载具之间搜集武器与装备，安全区会不断缩小。听声辨位、掩体和物资管理决定能不能留到最后。请通过浏览器下载 Windows 版客户端，完成后把安装程序拖入 Vesta，绑定 Wine 运行。",
            pcMinSpecs: "Intel Core i5-4430 / GTX 960 / 8GB RAM / Windows 10 64 位",
            macMinSpecs: "Apple Silicon / 8GB 统一内存 / 通过 Wine 运行 Windows 客户端",
            noticeText: "需通过浏览器下载 Windows 版客户端，下载完成后将安装程序拖入 Vesta 绑定 Wine 运行。",
            requiredStorageGB: 40,
            bottleName: "Gaming",
            installPath: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\PUBG\\TslGame\\Binaries\\Win64\\TslGame.exe",
            downloadURL: "https://store.steampowered.com/app/578080/PUBG_BATTLEGROUNDS/",
            bannerImageURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/578080/library_hero.jpg",
            iconName: "shield.fill",
            iconURL: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/578080/logo.png",
            iconFillsFrame: false,
            steamAppID: "578080",
            symbolName: "shield.fill",
            tint: .gold,
            isRunning: false,
            lastRunText: "尚未运行"
        ),
        WindowsApp(
            id: UUID(),
            name: "Notepad++ (Windows 容器版)",
            publisher: "Don Ho",
            version: "8.7.1",
            kind: .utility,
            category: "工具",
            summary: "通过 Tools 容器运行的 Windows 版 Notepad++。",
            description: "轻量的 Windows 文本与代码编辑器。启动很快，占用也很低，适合打开配置、日志和脚本，并提供语法高亮与多标签编辑。",
            pcMinSpecs: "Windows 7/10 / 1GB RAM",
            macMinSpecs: "Apple Silicon / 4GB 内存 (Wine)",
            noticeText: "经典 Windows 轻量级代码编辑器。",
            bottleName: "Tools",
            platform: .windows,
            installPath: "C:\\Program Files\\Notepad++\\notepad++.exe",
            bannerImageURL: nil,
            iconName: "chevron.left.forwardslash.chevron.right",
            iconURL: "https://img.icons8.com/color/480/notepad-plus-plus.png",
            customIconName: nil,
            symbolName: "chevron.left.forwardslash.chevron.right",
            tint: .teal,
            isRunning: false,
            lastRunText: "尚未运行"
        )
    ]
}

/// 用 Steam 商店编号拼接官方 CDN 图片，不需要把 Logo 放进 Assets。
enum SteamArtwork {
    private static let base = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps"

    static func headerURL(appID: String?) -> URL? {
        assetURL(appID: appID, file: "header.jpg")
    }

    /// Steam 库里的宽幅主视觉，大约 1920×620，适合详情页顶部。
    static func libraryHeroURL(appID: String?) -> URL? {
        assetURL(appID: appID, file: "library_hero.jpg")
    }

    static func logoURL(appID: String?) -> URL? {
        assetURL(appID: appID, file: "logo.png")
    }

    private static func assetURL(appID: String?, file: String) -> URL? {
        let id = appID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { return nil }
        return URL(string: "\(base)/\(id)/\(file)")
    }
}

extension Array where Element == WindowsApp {
    /// 按侧边栏和搜索框过滤。放在模型上，列表和选中同步共用同一套规则。
    func filtered(query: String, onlyRunning: Bool, category: LibraryCategory = .all, platform: AppPlatform? = nil, catalog: AppCatalog? = nil, favoritesOnly: Bool = false) -> [WindowsApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return filter { app in
            if favoritesOnly && !app.isFavorite {
                return false
            }
            if let platform, app.platform != platform {
                return false
            }
            if let catalog, !catalog.matches(app) {
                return false
            }
            if let tag = category.matchTag, !app.matchesTag(tag) {
                return false
            }
            if onlyRunning && !app.isRunning && !app.isLaunching {
                return false
            }
            if trimmed.isEmpty {
                return true
            }
            if app.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if app.publisher.localizedCaseInsensitiveContains(trimmed) { return true }
            if app.kind.title.localizedCaseInsensitiveContains(trimmed) { return true }
            if app.category.localizedCaseInsensitiveContains(trimmed) { return true }
            if app.displayTags.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) { return true }
            if let bottle = app.bottle, bottle.localizedCaseInsensitiveContains(trimmed) { return true }
            return false
        }
    }
}

/// 一个 Windows 容器（Bottle）：独立的系统版本和已装软件。
public struct Bottle: Identifiable, Hashable {
    /// 预置容器用稳定 id，例如 "Gaming"，新建容器才用随机 id。
    public let id: String
    var name: String
    var windowsVersion: String
    var wineVersion: String
    var programNames: [String]
    var isDefault: Bool
    /// 开启后，启动该容器里的程序时会带上 DXVK 的 DLL 覆盖，由 Metal 显示。
    var enablesDXVK: Bool = false
    /// 启动时请求 Metal 3 / D3DMetal。只有 CrossOver 核心才会写入 CX_GRAPHICS。
    var enablesMetal3: Bool = false
    /// 启动时按 DXMT 的 native 覆盖写入 WINEDLLOVERRIDES。不下载 DXMT 本体。
    var enablesDXMT: Bool = false
    /// 启动时设置 WINEESYNC=1。不与 MSync、FSync 同时打开。
    var enablesEsync: Bool = false
    /// 启动时设置 WINEMSYNC=1。游戏容器默认打开，不与 ESync、FSync 同时打开。
    var enablesMsync: Bool = true
    /// 开启后写入 WINE_ENABLE_RETINA=0，按标准 DPI 画窗口。
    var disablesRetina: Bool = false
    /// 开启后把 DXVK / vkd3d / Mesa 着色器缓存写到 Application Support/Vesta。
    var enablesShaderCache: Bool = true

    var graphicsBackend: BottleGraphicsBackend {
        get {
            if enablesDXMT { return .dxmt }
            if enablesMetal3 { return .d3dmetal }
            return .dxvk
        }
        set {
            enablesDXVK = newValue == .dxvk
            enablesDXMT = newValue == .dxmt
            enablesMetal3 = newValue == .d3dmetal
        }
    }

    var syncMode: BottleSyncMode {
        get {
            if enablesEsync { return .esync }
            if enablesMsync { return .msync }
            return .off
        }
        set {
            enablesMsync = newValue == .msync
            enablesEsync = newValue == .esync
        }
    }

    static let versionOptions = [
        "Windows 11 64-bit",
        "Windows 10 64-bit"
    ]

    /// 预置 Gaming（游戏，开启 DXVK）和 Office（办公，默认容器）。
    static let samples: [Bottle] = [
        Bottle(
            id: "Gaming",
            name: "Gaming",
            windowsVersion: "Windows 11 64-bit",
            wineVersion: "Wine 9.0",
            programNames: [
                "Steam",
                "黑神话：悟空 (Black Myth: Wukong)",
                "赛博朋克 2077 (Cyberpunk 2077)",
                "艾尔登法环 (Elden Ring)",
                "GTA 5 (Grand Theft Auto V)",
                "荒野大镖客：救赎 2 (Red Dead Redemption 2)",
                "博德之门 3 (Baldur's Gate 3)",
                "怪物猎人：世界 (Monster Hunter: World)",
                "巫师 3：狂猎 (The Witcher 3: Wild Hunt)",
                "星露谷物语 (Stardew Valley)",
                "绝地求生 (PUBG)"
            ],
            isDefault: false,
            enablesDXVK: true,
            enablesMetal3: false,
            enablesDXMT: false,
            enablesEsync: false,
            enablesMsync: true,
            disablesRetina: false,
            enablesShaderCache: true
        ),
        Bottle(
            id: "Office",
            name: "Office",
            windowsVersion: "Windows 10 64-bit",
            wineVersion: "Wine 9.0",
            programNames: ["Microsoft Word (Windows 容器版)", "Microsoft Excel (Windows 容器版)", "Microsoft PowerPoint"],
            isDefault: true,
            enablesDXVK: false,
            enablesMsync: false,
            enablesShaderCache: false
        ),
        Bottle(
            id: "Tools",
            name: "Tools",
            windowsVersion: "Windows 10 64-bit",
            wineVersion: "Wine 9.0",
            programNames: ["Notepad++ (Windows 容器版)"],
            isDefault: false,
            enablesDXVK: false,
            enablesMsync: false,
            enablesShaderCache: false
        )
    ]
}

extension Bottle {
    /// 预置容器加上用户改过的图形开关。
    static func resolved(named name: String?) -> Bottle? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, var bottle = samples.matching(name: trimmed) else { return nil }
        BottleTuningStore.load(into: &bottle)
        return bottle
    }
}

struct NewBottleDraft {
    var name: String
    var windowsVersion: String
    var enablesDXVK: Bool
    var enablesMetal3: Bool = false
    var presetID: String = ""
}

extension Array where Element == Bottle {
    /// 按容器名称匹配，忽略大小写和首尾空格。
    func matching(name: String) -> Bottle? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return first { bottle in
            bottle.name.lowercased() == key || bottle.id.lowercased() == key
        }
    }
}

extension Array where Element == Bottle {
    func filtered(query: String) -> [Bottle] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return self
        }
        return filter { bottle in
            if bottle.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if bottle.windowsVersion.localizedCaseInsensitiveContains(trimmed) { return true }
            return bottle.programNames.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}

/// 游戏库顶部的分类筛选。
enum LibraryCategory: String, CaseIterable, Identifiable {
    case all
    case action
    case rpg
    case shooter
    case online
    case utility

    var id: String { rawValue }

    var matchTag: String? {
        switch self {
        case .all: return nil
        case .action: return "动作"
        case .rpg: return "RPG"
        case .shooter: return "射击"
        case .online: return "网游"
        case .utility: return "工具"
        }
    }
}

extension WindowsApp {
    func matchesTag(_ tag: String) -> Bool {
        if displayTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame || $0.localizedCaseInsensitiveContains(tag) }) {
            return true
        }
        if tag == "工具" {
            return kind == .utility || kind == .office || category == "工具" || category == "办公"
        }
        return category.localizedCaseInsensitiveContains(tag)
    }
}

/// 设置页中间栏的分组。
public enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case account
    case graphics
    case diagnostics
    case feedback
    case about
    case engine

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .account: return "账户"
        case .graphics: return "图形"
        case .diagnostics: return "硬件与环境诊断"
        case .feedback: return "意见反馈"
        case .about: return "关于"
        case .engine: return "引擎管理"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .account: return "person.crop.circle"
        case .graphics: return "display"
        case .diagnostics: return "stethoscope"
        case .feedback: return "envelope"
        case .about: return "info.circle"
        case .engine: return "cpu"
        }
    }
}

public enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// nil 表示不覆盖系统外观。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
