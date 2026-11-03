//
//  LanguageManager.swift
//
//  界面语言。未保存过时跟随系统：英、日、韩、法、意、西各自对应，其余用中文。
//  用户选过之后写入 UserDefaults。没有单独译文的词条回退到英文。
//

import Combine
import SwiftUI

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english
    case japanese
    case korean
    case french
    case italian
    case spanish

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .chinese: return "🇨🇳 中文"
        case .english: return "🇺🇸 English"
        case .japanese: return "🇯🇵 日本語"
        case .korean: return "🇰🇷 한국어"
        case .french: return "🇫🇷 Français"
        case .italian: return "🇮🇹 Italiano"
        case .spanish: return "🇪🇸 Español"
        }
    }

    static func resolve(code: String) -> AppLanguage {
        if code.hasPrefix("zh") { return .chinese }
        if code.hasPrefix("ja") { return .japanese }
        if code.hasPrefix("ko") { return .korean }
        if code.hasPrefix("fr") { return .french }
        if code.hasPrefix("it") { return .italian }
        if code.hasPrefix("es") { return .spanish }
        if code.hasPrefix("en") { return .english }
        return .chinese
    }
}

nonisolated enum L10nKey: String, Hashable, CaseIterable, Sendable {
    case library, bottles, settings, about, launchGame, installViaSteam, downloadSetup, browserDownload, downloadValorantClient, noDirectLink, downloadGuideTitle, downloadGuideMessage
    case downloadCNClient, downloadAPClient, downloadNAClient, downloadEUClient
    case downloadGuideCN, downloadGuideAP, downloadGuideNA, downloadGuideEU, downloadGuidePUBG
    case regionLabel, regionCN, regionAP, regionNA, regionEU
    case diskSufficient, diskInsufficient, localContainer, steamLinkage, appNotFound, installInContainerFirst
    case installed, inLibrary, notInstalled, notRunning, running, launching, launchingNow, downloadingEngine, extractingEngine, engineDownloadFailed, chooseWine64, chooseWine64Button, redownloadEngine, repairNow, problemTitle, problemEngine, problemPrefix, problemArchive, problemGeneric, repairDone, ready, stopped
    case version, publisher, kind, platform, category, installStatus, container, lastRun, noContainer, notRunYet, today
    case overviewGame, overviewApp, hardwareTitle, pcSpecs, macSpecs, notProvided, tuningTips, installPath
    case diskFree, diskRequired, diskTotal, diskEnoughBody, diskShortBody
    case refreshFiles, needInstall, wakeSteam, cancel, installGuide, buySteam, appStore, goDownload, stop, nativeMac
    case missingBottle, macNeedsNoBottle, bottleSection, bottleName, bottleIdentifier, bottleSystem, dxvkOn, dxvkOff
    case createBottle, bindBottle, noBottlesHere, unnamed, launchMethod, containerHint, steamHint
    case appCount, runningCount, searchApps, noMatch, noMatchHint, emptyCategory, emptyCategoryHint
    case nothingRunning, nothingRunningHint, showAll, noApps, noAppsHint, importExe
    case scanning, scanLocal, macZone, macGames, macTools, windowsZone, windowsGames, windowsTools
    case preferences, restoreBottle, menuBarStatus, settingsFooter, appearance, systemAppearance, light, dark
    case dxvkExample, retinaExample, graphicsFooter, productName, complianceTitle, complianceBody
    case ackTitle, ackBody, wineNote, whiskyNote, dxvkNote
    case licenseHeading, licenseKey, verifyLicense, licenseHelp, activate, close, keyTooShort, keyPending
    case activated, trialRemaining, notActivated, hardwareSummary, unifiedMemory, systemMemory
    case importFailed, ok, importedPublisher, importedSummary, importedMacSummary, unassignedBottle, unnamedApp, chooseExe, playtimeMinutes, playtimeHours, prefixLocation, choosePrefixFolder, useDesktopPrefix
    case bottleCount, searchBottles, newBottle, noBottles, noBottlesHint, noBottleMatch, noBottleMatchHint
    case softwareCount, defaultBadge, newBottleHint, bottleNamePrompt, enableDXVK, dxvkBottleHint, windowsVersion, create
    case bottleMissingTitle, bottleMissingHint, bottleIntro, currentDefault, setDefault
    case advancedGraphics, metal3, defaultBottle, openCDrive, wineConsole, installedSoftware, emptyBottle
    case selectAppTitle, selectAppHint, directLaunch, steamHandOff, steamInstallHandOff, steamClientMissing, filesRefreshed
    case general, graphics, clearSearch, importHelp, scanHelp, detailHelp
    case startingStatus, exited, containerNotFound, containerLostTitle, containerLostMessage, rebuildContainer, containerRebuilt, noEngine, launchedVia, macOpened, localOpened, noPath, fileMissing
    case directExeRequired, appInfo, steamBottleHandOff, runHelp, appMissing, openFailed, engineFailed, engineExited, systemEngine
    case finderOpened, finderFailed, wineMissing, terminalFailed, wineConsoleOpened, enableDXVKShort, interfaceLabel, wineLicense, appleChip
    case fpsOverlay, fpsOverlayHint, perfWaiting
    case backupSection, backupNow, restoreBackup, exportSave, backupEmpty, backupNoDrive, backupDone, backupFailed, backupRestored, backupLibrary, restoreLibrary, libraryBackupDone, libraryRestoreDone, libraryBackupFailed
    case themeSection, accentColor, accentDark, accentTechBlue, accentVaporwave, wallpaper, wallpaperNone, wallpaperNight, wallpaperInk, wallpaperOrbit, chooseWallpaper, wallpaperDrop
    case detailOverview, detailMods, modsEmpty, modsHint, importMod, openMods, modOn, modOff, loadedPath
    case languageMenu, filterAll, filterGame, filterOffice, filterTool, filterAction, filterRPG, filterShooter, filterOnline
    case sidebarMain, sidebarCategories, sidebarSettings, favorites, favoritesEmpty, favoritesEmptyHint, favorite, unfavorite, enterLicense, getLicense, translationEngine, translationHint, hostEngine, hostEngineHint
    case diagnostics, repairEnvironment, diagReady, diagMissing, diagPartial
    case diagRosetta, diagWhisky, diagCpp
    case diagRosettaIntel, diagRosettaReady, diagRosettaMissing
    case diagWhiskyReady, diagWhiskyPartial, diagWhiskyMissing
    case diagCppReady, diagCppPartial, diagCppMissing, diagRepairDone, diagRepairFailed
    case performanceMode, balancedMode, profileHint
    case licensePrompt, buyLicense, activateOnline, activationSaved, activationOffline, proLockedHint, licenseKeychainFailed, integrityFailedTitle, integrityFailedBody, libraryTampered
    case recentGames, noRecentGames, libraryShortcuts
    case membershipTitle, membershipSubtitle, membershipUnlocked, membershipUnlockedDetail, membershipPitch
    case membershipPay, membershipHaveKey, membershipKeyPlaceholder
    case vestaAuthSubtitle, authTabAccount, authTabKey, authGoogle, authOr
    case authEmail, authPhone, authEmailPlaceholder, authSendLink, authPhonePlaceholder, authGetCode
    case authEmailCode, authConfirmLogin, authCodeInvalid
    case authKeyHint, authKeyPlaceholder, authActivate, authUnavailable, authAppleNoSync, authAppleFailed
    case emailLoginTitle, emailLoginSubtitle, emailLoginPlaceholder, emailLoginSend
    case chooseCountry, countrySearchPrompt, phoneLoginTitle
    case accountSettings, accountSection, accountSignedOut, accountSignIn, accountSignedIn, accountSignOut
    case profileTitle, profileUsername, profileUsernamePrompt, profileBirthday, profileSave, profileSaved, profileChoosePhoto, profileSignInFirst
    case supabaseNotConfigured, supabaseAwaitConfirm
    case serviceSection, licenseManageSection, restorePurchases, upgradeLifetime
    case serviceTrialTitle, serviceLifetimeTitle, serviceExpiredTitle
    case serviceTrialBody, serviceLifetimeBody, serviceExpiredBody
    case accountTrialDays, lifetimeBadge, expiredBadge
    case enterSavedLicense, licenseRestoredLocal, licenseRestoreEmpty
    case deviceIDTitle, deviceIDHint, deviceIDCopy, deviceIDCopied, deviceIDUnavailable
    case deviceBindTitle, deviceBoundElsewhere, deviceBoundOtherEmail, deviceBindFailed
    case storageSection, storageUsed, storageCache, storageRefresh, storageClearCache, storageCleared
    case archiveExport, archiveImport, archiveImportConfirm, archiveExportDone, archiveImportDone, archiveFailed
    case statusRunning, statusStop
    case presetSection, presetApply, presetHint, presetCustom
    case presetShooter, presetRPG, presetAction, presetUtility
    case presetEngineUnreal, presetEngineUnity, presetEngineDX11, presetEngineDX12
    case presetDXVK, presetD3DMetal, presetVirtualDesktop, presetD3DMetalWine
    case presetDXVKOn, presetDXVKOff, presetRuntimeReady, presetRuntimeMissing
    case presetMetalFX, presetMetalFXReady, presetMetalFXWine, presetMetalFXUnsupported
    case presetEsync, presetFsync, presetFsyncReady, presetFsyncFallback
    case shaderDeepClean, shaderDeepCleanDone
    case recipeApply, recipeGeneric, recipeAntiCheat, recipeOnline, recipeSinglePlayer, recipeLight, recipeSteamClient
    case graphicsBackend, graphicsSync, syncOff, archiveBottleHint
    case saveSyncSection, saveSyncScope, saveSyncScan, saveSyncFound, saveSyncEmpty
    case saveSyncBackup, saveSyncBackupDone, saveSyncFailed, saveSynciCloud, saveSynciCloudMissing
    case saveSyncVault, saveSyncVaultPlain, saveSyncNewerCloud, saveSyncRestoreBeforeLaunch, saveSyncRestored, saveSyncSkip
    case perfNoInject
    case otaSection, otaCheck, otaWineReady, otaWineMissing, otaNoReplace, otaNewerUnverified
    case otaDXVK, otaMoltenVKFound, otaMoltenVKMissing, otaD3DMetal, otaD3DMetalWine, otaInstallPinned, otaFailed
    case bindLocalApp, bindLocalAppHint, bindLocalAppInvalid
    case feedbackPane, feedbackTitle, feedbackBody, feedbackSend
    case importDropHint, importDropReady
    case cleanJunk, cleanJunkHint, cleanJunkDone
}

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            guard currentLanguage != oldValue else { return }
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "MyApp.language"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let saved = AppLanguage(rawValue: raw) {
            currentLanguage = saved
        } else {
            currentLanguage = Self.systemPreference()
        }
        print("[MyApp] LanguageManager ready")
    }

    func text(_ key: L10nKey) -> String {
        L10n.string(key, language: currentLanguage)
    }

    func format(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: args)
    }

    private static func systemPreference() -> AppLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? ""
        return AppLanguage.resolve(code: code)
    }
}

/// 不依赖界面刷新的查表。启动器在后台组句子时用保存下来的语言。
nonisolated enum L10n {
    static func savedLanguage() -> AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: "MyApp.language"),
           let saved = AppLanguage(rawValue: raw) {
            return saved
        }
        let code = Locale.current.language.languageCode?.identifier ?? ""
        return AppLanguage.resolve(code: code)
    }

    static func string(_ key: L10nKey, language: AppLanguage) -> String {
        guard let pair = table[key] else {
            return ""
        }
        switch language {
        case .chinese:
            return pair.zh
        case .english:
            return pair.en
        case .japanese:
            return eastAsian[key]?.ja ?? pair.en
        case .korean:
            return eastAsian[key]?.ko ?? pair.en
        case .french:
            return romance[key]?.fr ?? pair.en
        case .italian:
            return romance[key]?.it ?? pair.en
        case .spanish:
            return romance[key]?.es ?? pair.en
        }
    }

    static func format(_ key: L10nKey, _ language: AppLanguage, _ args: CVarArg...) -> String {
        let template = string(key, language: language)
        guard !template.isEmpty else { return "" }
        return String(format: template, arguments: args)
    }

    private static let table: [L10nKey: (zh: String, en: String)] = [
        .library: ("游戏库", "Game Library"),
        .bottles: ("容器管理", "Bottles / Containers"),
        .settings: ("设置", "Settings"),
        .about: ("ℹ️ 关于", "ℹ️ About"),
        .launchGame: ("运行游戏", "Launch Game"),
        .installViaSteam: ("通过 Steam 安装", "Install via Steam"),
        .downloadSetup: ("下载 / 安装", "Download / Setup"),
        .browserDownload: ("获取安装包 / 浏览器下载", "Get installer / Open in browser"),
        .downloadValorantClient: ("下载亚服客户端", "Download the Asia client"),
        .noDirectLink: ("暂无直链", "No direct link"),
        .downloadGuideTitle: ("官方下载页面", "Official download page"),
        .downloadGuideMessage: ("将为您打开官方下载页面。请注意：在网页中请务必下载 Windows (.exe) 版本的安装程序或客户端。下载完成后，直接将 .exe 文件拖入 Vesta 游戏库即可通过 Wine 运行！", "This opens the official download page. On that page, be sure to download the Windows (.exe) installer or client. When the download finishes, drag the .exe into the Vesta library to run it with Wine."),
        .downloadCNClient: ("下载国服客户端", "Download the China client"),
        .downloadAPClient: ("下载亚服客户端", "Download the Asia client"),
        .downloadNAClient: ("下载美服客户端", "Download the Americas client"),
        .downloadEUClient: ("下载欧服客户端", "Download the Europe client"),
        .downloadGuideCN: ("需通过浏览器下载腾讯代理的国服客户端，安装后绑定 Wine 运行。", "Download the Tencent China client in your browser, then bind it to Wine to run."),
        .downloadGuideAP: ("需通过浏览器下载亚服的 Riot 客户端，安装后绑定 Wine 运行。", "Download the Asia-Pacific Riot client in your browser, then bind it to Wine to run."),
        .downloadGuideNA: ("需通过浏览器下载美服的 Riot 客户端，安装后绑定 Wine 运行。", "Download the Americas Riot client in your browser, then bind it to Wine to run."),
        .downloadGuideEU: ("需通过浏览器下载欧服的 Riot 客户端，安装后绑定 Wine 运行。", "Download the Europe Riot client in your browser, then bind it to Wine to run."),
        .downloadGuidePUBG: ("需通过浏览器下载 Windows 版客户端，下载完成后将安装程序拖入 Vesta 绑定 Wine 运行。", "Download the Windows client in your browser. When it finishes, drag the installer into Vesta and bind it to Wine."),
        .regionLabel: ("区服", "Region"),
        .regionCN: ("国服", "China"),
        .regionAP: ("亚服", "Asia-Pacific"),
        .regionNA: ("美服", "Americas"),
        .regionEU: ("欧服", "Europe"),
        .diskSufficient: ("磁盘空间充足", "Disk Space Available"),
        .diskInsufficient: ("磁盘空间不足", "Disk Space Insufficient"),
        .localContainer: ("本地容器运行", "Local Container"),
        .steamLinkage: ("Steam 客户端联动", "Steam Linkage"),
        .appNotFound: ("未找到应用程序", "Application Not Found"),
        .installInContainerFirst: ("请先在容器中安装该游戏。", "Please install the game in the container first."),
        .installed: ("已安装", "Installed"),
        .inLibrary: ("已在库", "In Library"),
        .notInstalled: ("未安装", "Not Installed"),
        .notRunning: ("未运行", "Not Running"),
        .running: ("运行中", "Running"),
        .launching: ("正在启动", "Launching"),
        .launchingNow: ("正在启动…", "Launching…"),
        .downloadingEngine: ("正在下载兼容引擎: %d%%", "Downloading the compatibility engine: %d%%"),
        .extractingEngine: ("正在解压兼容引擎: %d%%", "Extracting the compatibility engine: %d%%"),
        .redownloadEngine: ("重新下载", "Download again"),
        .repairNow: ("一键修复", "Repair"),
        .problemTitle: ("无法启动", "Could not start"),
        .problemEngine: ("没有找到可用的兼容引擎，或引擎文件不完整。可以重新下载，也可以先修复容器后再试。", "The compatibility engine is missing or incomplete. Download it again, or repair the container and try once more."),
        .problemPrefix: ("容器目录不存在，或当前没有写入权限。可以一键修复，修复后请再次运行。", "The container folder is missing or cannot be written. Repair it, then launch again."),
        .problemArchive: ("引擎压缩包已损坏或无法解压。请重新下载。", "The engine archive is damaged or could not be extracted. Download it again."),
        .problemGeneric: ("这次启动没有成功。可以重新下载兼容引擎，或一键修复容器后再试。", "The launch did not succeed. Download the compatibility engine again, or repair the container and try once more."),
        .repairDone: ("容器目录已重新准备好，请再次点击运行游戏。", "The container folder is ready. Launch the game again."),
        .engineDownloadFailed: ("兼容引擎下载失败：%@", "Could not download the compatibility engine: %@"),
        .chooseWine64: ("自动下载没有完成。请选择本机的 wine64，也可以进入 Whisky 或 Wine Stable，选择里面的 wine64 或 wine。", "The automatic download did not finish. Choose a local wine64, or the wine64 or wine binary inside Whisky or Wine Stable."),
        .chooseWine64Button: ("选择 wine64", "Choose wine64"),
        .ready: ("就绪", "Ready"),
        .stopped: ("已停止", "Stopped"),
        .version: ("版本", "Version"),
        .publisher: ("发行商", "Publisher"),
        .kind: ("类型", "Type"),
        .platform: ("平台", "Platform"),
        .category: ("分类", "Category"),
        .installStatus: ("安装状态", "Install Status"),
        .container: ("容器", "Container"),
        .lastRun: ("上次运行", "Last Run"),
        .noContainer: ("无需容器", "No container"),
        .notRunYet: ("尚未运行", "Not run yet"),
        .today: ("今天 %@", "Today %@"),
        .overviewGame: ("📖 游戏简介 / 概览", "📖 Overview"),
        .overviewApp: ("📖 应用简介 / 概览", "📖 Overview"),
        .hardwareTitle: ("💻 硬件配置与运行门槛", "💻 Hardware and Requirements"),
        .pcSpecs: ("🪟 PC 官方原版配置", "🪟 Official PC Requirements"),
        .macSpecs: ("🍎 Mac 实际运行推荐", "🍎 Recommended Mac Setup"),
        .notProvided: ("未提供", "Not provided"),
        .tuningTips: ("⚠️ 运行注意事项与调优技巧", "⚠️ Notes and Tuning"),
        .installPath: ("安装路径", "Install Path"),
        .diskFree: ("磁盘可用空间 %@ GB", "Disk space available: %@ GB"),
        .diskRequired: ("游戏所需空间 %@ GB", "Required: %@ GB"),
        .diskTotal: ("主磁盘共 %@ GB", "Disk total %@ GB"),
        .diskEnoughBody: ("当前磁盘剩余容量 %@ GB，满足该游戏所需的 %@ GB，可放心下载！", "This disk has %@ GB free, which covers the %@ GB this game needs. You can download it."),
        .diskShortBody: ("当前磁盘仅剩余 %@ GB，无法安装该游戏（需 %@ GB）。请先清理 Mac 磁盘空间或更改安装路径", "Only %@ GB is free, which is not enough (%@ GB required). Free up space or choose another install location."),
        .refreshFiles: ("🔄 刷新本地文件检测", "🔄 Refresh Local Files"),
        .needInstall: ("需要完成游戏安装", "Installation Required"),
        .wakeSteam: ("唤醒 Steam 下载", "Wake Steam to Download"),
        .cancel: ("取消", "Cancel"),
        .installGuide: ("未在本地容器中检测到《%@》文件。请确保您已在 Steam 官方拥有该游戏正版，点击下方按钮将自动唤醒容器内的 Steam 开启下载。", "“%@” was not found in the local container. If you own it on Steam, the button below opens Steam inside the container to download it."),
        .buySteam: ("去 Steam 购买/获取", "Get on Steam"),
        .appStore: ("去 App Store 获取", "Get on the App Store"),
        .goDownload: ("前往下载", "Download"),
        .stop: ("停止", "Stop"),
        .nativeMac: ("macOS 原生", "macOS native"),
        .missingBottle: ("未找到容器 %@", "Container %@ was not found"),
        .macNeedsNoBottle: ("这是 macOS 原生应用，不需要 Wine 容器。", "This is a native macOS app and does not need a Wine container."),
        .bottleSection: ("所属容器", "Container"),
        .bottleName: ("名称", "Name"),
        .bottleIdentifier: ("标识", "Identifier"),
        .bottleSystem: ("系统", "System"),
        .dxvkOn: ("已开启（Metal）", "On (Metal)"),
        .dxvkOff: ("未开启", "Off"),
        .createBottle: ("创建该容器", "Create This Container"),
        .bindBottle: ("绑定现有容器", "Bind an Existing Container"),
        .noBottlesHere: ("还没有容器。可以先创建该容器。", "There are no containers yet. Create one first."),
        .unnamed: ("未命名", "Untitled"),
        .launchMethod: ("启动方式", "Launch Method"),
        .containerHint: ("用 wine64 在 Vesta 自己的容器里直接启动游戏进程，适合单机 3A。", "Starts the game executable with wine64 inside Vesta's own container. Best for single-player AAA games."),
        .steamHint: ("唤醒官方 Steam 客户端，适合联机、正版校验和云存档。", "Opens the official Steam client. Best for online play, ownership checks, and cloud saves."),
        .appCount: ("%d 个应用", "%d apps"),
        .runningCount: ("%d 个正在运行", "%d running"),
        .searchApps: ("搜索应用或发行商", "Search apps or publishers"),
        .noMatch: ("没有匹配的应用", "No matching apps"),
        .noMatchHint: ("换一个名称或发行商试试。", "Try another name or publisher."),
        .emptyCategory: ("这个分类下没有应用", "Nothing in this category"),
        .emptyCategoryHint: ("换到「全部」，或扫描本机后再看。", "Switch to All, or scan this Mac."),
        .nothingRunning: ("没有正在运行的应用", "Nothing is running"),
        .nothingRunningHint: ("从游戏库中选择软件，再点击运行。", "Choose an app in the library, then launch it."),
        .showAll: ("查看所有应用", "Show All Apps"),
        .noApps: ("还没有应用", "No apps yet"),
        .noAppsHint: ("使用上方的「导入 .exe 软件」加入 Windows 程序。", "Use Import .exe above to add a Windows program."),
        .importExe: ("导入游戏 / 容器应用", "Import Game / Container App"),
        .scanning: ("正在扫描…", "Scanning…"),
        .scanLocal: ("扫描本地游戏", "Scan Local Games"),
        .macZone: ("🍎 macOS 专区", "🍎 macOS Zone"),
        .macGames: ("🎮 游戏大作", "🎮 AAA Games"),
        .macTools: ("🛠️ 实用工具", "🛠️ Utility Tools"),
        .windowsZone: ("🪟 Windows 专区", "🪟 Windows"),
        .windowsGames: ("🎮 3A/PC 游戏", "🎮 AAA / PC Games"),
        .windowsTools: ("🛠️ 容器工具", "🛠️ Bottle Tools"),
        .preferences: ("偏好设置", "Preferences"),
        .restoreBottle: ("启动时恢复上次的容器", "Restore the last container on launch"),
        .menuBarStatus: ("在菜单栏显示运行状态", "Show running status in the menu bar"),
        .settingsFooter: ("外观会立即作用于本窗口。语言切换也会立即生效。", "Appearance and language apply to this window immediately."),
        .appearance: ("外观", "Appearance"),
        .systemAppearance: ("跟随系统", "System"),
        .light: ("浅色", "Light"),
        .dark: ("深色", "Dark"),
        .dxvkExample: ("启用 DXVK 图形转换（示例）", "Enable DXVK translation (sample)"),
        .retinaExample: ("启用高分辨率 Retina 模式（示例）", "Enable Retina mode (sample)"),
        .graphicsFooter: ("这些开关只演示设置页的布局，还没有连接到图形转换层。", "These toggles only show the settings layout. They are not wired to the graphics layer yet."),
        .productName: ("游戏管理与容器调度", "Game Library and Containers"),
        .complianceTitle: ("软件定位声明", "About This App"),
        .complianceBody: ("本软件为独立的第三方游戏管理与容器调度工具，不包含任何游戏本体与二进制破解文件。所有游戏版权及商标均归其原开发商与发行商所有。", "This is an independent third-party library and container tool. It does not include game files or circumvention binaries. Game copyrights and trademarks belong to their developers and publishers."),
        .ackTitle: ("开源致谢", "Acknowledgements"),
        .ackBody: ("本软件不随附这些项目的源代码或二进制文件。若本机安装了对应工具，启动时会调用你已经安装的副本，并遵守其许可证。", "This app does not ship their source or binaries. If you have them installed, launch uses your local copy under its license."),
        .wineNote: ("Windows 程序兼容层。LGPL 允许动态链接，修改 Wine 本身时需要提供对应源代码。", "A Windows compatibility layer. The LGPL allows dynamic linking. Changes to Wine itself must ship with source."),
        .whiskyNote: ("面向 macOS 的 Wine 图形前端。GPL 适用于 Whisky 自己的程序，不把本软件变成 GPL 作品。", "A macOS front end for Wine. The GPL covers Whisky itself and does not relicense this app."),
        .dxvkNote: ("将 Direct3D 转到 Vulkan 的开源层。zlib 是宽松许可，保留版权声明即可。", "Translates Direct3D to Vulkan. The zlib license is permissive if the copyright notice is kept."),
        .licenseHeading: ("商业授权", "License"),
        .licenseKey: ("激活码", "License key"),
        .verifyLicense: ("验证激活码", "Verify Key"),
        .licenseHelp: ("查看试用状态并输入激活码", "View trial status and enter a license key"),
        .activate: ("激活", "Activate"),
        .close: ("关闭", "Close"),
        .keyTooShort: ("请输入完整的激活码。", "Enter the full license key."),
        .keyPending: ("激活码已收下，但 Gumroad / Lemon Squeezy 在线校验尚未接入，因此不会把软件标成已激活。", "The key was saved locally, but Gumroad / Lemon Squeezy verification is not connected yet, so the app stays unactivated."),
        .activated: ("授权有效 / 终身版", "Licensed / Lifetime"),
        .trialRemaining: ("试用期中 · 剩余 %d 天", "Trial · %d days left"),
        .notActivated: ("未激活", "Not activated"),
        .hardwareSummary: ("Mac 硬件摘要", "Mac Hardware Summary"),
        .unifiedMemory: ("%@ 统一内存", "%@ unified memory"),
        .systemMemory: ("%@ 内存", "%@ memory"),
        .importFailed: ("导入失败", "Import Failed"),
        .ok: ("好", "OK"),
        .importedPublisher: ("本地导入", "Imported"),
        .importedSummary: ("从本机导入的 Windows 可执行文件。运行时将使用当前默认容器。", "A Windows executable imported from this Mac. It launches in the current default container."),
        .importedMacSummary: ("从本机导入的 macOS 应用。将直接打开这个 .app，不经过 Wine 容器。", "A macOS app imported from this Mac. It opens directly and does not use a Wine container."),
        .unassignedBottle: ("未分配容器", "Unassigned container"),
        .unnamedApp: ("未命名应用", "Untitled App"),
        .chooseExe: ("请选择 .app、.exe，或包含游戏/容器的文件夹。", "Choose an .app, an .exe, or a folder that contains a game or container."),
        .playtimeMinutes: ("已游玩 %d 分钟", "Played %d min"),
        .playtimeHours: ("已游玩 %.1f 小时", "Played %.1f hr"),
        .prefixLocation: ("容器位置", "Container location"),
        .choosePrefixFolder: ("选择位置", "Choose location"),
        .useDesktopPrefix: ("使用桌面", "Use Desktop"),
        .bottleCount: ("%d 个容器", "%d containers"),
        .searchBottles: ("搜索容器或其中的软件", "Search containers or their apps"),
        .newBottle: ("新建容器", "New Container"),
        .noBottles: ("还没有容器", "No containers yet"),
        .noBottlesHint: ("创建一个容器，用来隔离不同 Windows 软件的运行环境。", "Create a container to isolate Windows apps from each other."),
        .noBottleMatch: ("没有匹配的容器", "No matching containers"),
        .noBottleMatchHint: ("换一个容器名称或 Windows 版本试试。", "Try another container name or Windows version."),
        .softwareCount: ("%d 个软件", "%d apps"),
        .defaultBadge: ("默认", "Default"),
        .newBottleHint: ("填写名称和 Windows 版本。游戏容器可以打开 DXVK / Metal。", "Enter a name and Windows version. Game containers can enable DXVK / Metal."),
        .bottleNamePrompt: ("容器名称，例如 Gaming、Office", "Container name, for example Gaming or Office"),
        .enableDXVK: ("开启 DXVK / Metal 渲染加速", "Enable DXVK / Metal"),
        .dxvkBottleHint: ("DirectX 会通过 DXVK 转到 Metal，适合 Gaming 这类游戏容器。", "DirectX goes through DXVK to Metal. This suits a Gaming container."),
        .windowsVersion: ("Windows 版本", "Windows Version"),
        .create: ("创建", "Create"),
        .bottleMissingTitle: ("未选择容器", "No Container Selected"),
        .bottleMissingHint: ("选择一个容器以查看其中的 Windows 版本和已安装软件。", "Select a container to see its Windows version and installed apps."),
        .bottleIntro: ("容器是一套独立的 Windows 环境。把办公软件和游戏分开放，可以避免它们共用同一套系统设置。", "A container is a separate Windows environment. Keeping office apps and games apart avoids shared settings."),
        .currentDefault: ("当前默认容器", "Current Default"),
        .setDefault: ("设为默认", "Make Default"),
        .advancedGraphics: ("高级渲染", "Graphics"),
        .metal3: ("Metal 3 硬件加速", "Metal 3 acceleration"),
        .defaultBottle: ("默认容器", "Default container"),
        .openCDrive: ("在 Finder 中打开容器 C 盘", "Show Container C: in Finder"),
        .wineConsole: ("运行 Wine 命令行", "Open Wine Console"),
        .installedSoftware: ("已安装的软件", "Installed Apps"),
        .emptyBottle: ("此容器中还没有应用。导入 .exe 时会放进当前默认容器。", "This container has no apps yet. Imported .exe files go into the default container."),
        .selectAppTitle: ("未选择软件", "No App Selected"),
        .selectAppHint: ("在中间列表选择一个应用，即可查看详情并运行。", "Select an app in the list to see its details and launch it."),
        .directLaunch: ("已直接启动游戏进程，未打开 Steam 主界面。", "The game process started directly, without opening the Steam window."),
        .steamHandOff: ("已交给 Steam 开始游戏", "Handed off to Steam"),
        .steamInstallHandOff: ("已交给 Steam 安装", "Steam will install it"),
        .steamClientMissing: ("没有找到 Steam 客户端，请先安装官方 Steam。", "Steam was not found. Install the official Steam client first."),
        .filesRefreshed: ("已重新检测本地文件", "Local files were checked again"),
        .general: ("⚙️ 通用", "⚙️ General"),
        .graphics: ("🖥️ 图形", "🖥️ Graphics"),
        .clearSearch: ("清除搜索", "Clear search"),
        .importHelp: ("选择 .app、.exe，或包含游戏/容器的文件夹", "Choose an .app, an .exe, or a folder that contains a game or container"),
        .scanHelp: ("在 Steam 库、应用程序文件夹和容器 C 盘中查找已安装的程序", "Look for installed apps in Steam, Applications, and container C: drives"),
        .detailHelp: ("查看 %@ 的详情", "Show details for %@"),
        .startingStatus: ("正在启动…", "Launching…"),
        .exited: ("已退出", "Exited"),
        .containerNotFound: ("未找到容器 %@。请先创建或绑定容器。", "Container %@ was not found. Create or bind it first."),
        .containerLostTitle: ("容器需要重建", "Container needs a rebuild"),
        .containerLostMessage: ("容器 %@ 已丢失或不完整。可以在 Vesta 自己的 Bottles 目录里重建 C 盘。", "Container %@ is missing or incomplete. Rebuild its C: drive in Vesta's own Bottles folder."),
        .rebuildContainer: ("重建容器", "Rebuild Container"),
        .containerRebuilt: ("容器已重建。请再点一次运行。", "The container was rebuilt. Run it again."),
        .noEngine: ("容器 %@ 已配置，但没有可执行的 wine64，无法静默启动。", "Container %@ is configured, but no executable wine64 was found, so it cannot start silently."),
        .launchedVia: ("已通过 %@ 启动", "Launched with %@"),
        .macOpened: ("已启动 macOS 应用", "The macOS app is open"),
        .localOpened: ("已启动本地应用", "The local app is open"),
        .noPath: ("没有配置安装路径，无法启动。", "No install path is set, so it cannot launch."),
        .fileMissing: ("找不到可执行文件：%@", "Executable not found: %@"),
        .directExeRequired: ("本地容器运行需要游戏的 .exe 路径，不会打开 Steam 主界面。", "Local container launch needs the game .exe path and will not open the Steam window."),
        .appInfo: ("软件信息", "App Info"),
        .steamBottleHandOff: ("已交给容器中的 Steam 客户端。登录、下载、联机和云存档由官方客户端完成。", "Handed off to Steam inside the container. Sign-in, downloads, online play, and cloud saves stay with the official client."),
        .runHelp: ("运行此 Windows 应用", "Run this Windows app"),
        .appMissing: ("找不到应用程序：%@", "Application not found: %@"),
        .openFailed: ("无法打开应用：%@", "Could not open the app: %@"),
        .engineFailed: ("%1$@ 启动失败：%2$@", "%1$@ failed to launch: %2$@"),
        .engineExited: ("%1$@ 退出了，代码 %2$d。详情在控制台。", "%1$@ exited with code %2$d. Details are in the console."),
        .systemEngine: ("系统", "System"),
        .finderOpened: ("已在 Finder 中打开容器 C 盘", "Opened the container C: drive in Finder"),
        .finderFailed: ("无法在 Finder 中选中 C 盘", "Could not select the C: drive in Finder"),
        .wineMissing: ("未找到 /usr/local/bin/wine64 或 Homebrew 的 wine64，无法打开命令行。", "wine64 was not found in /usr/local/bin or Homebrew, so the console cannot open."),
        .terminalFailed: ("无法打开终端：%@", "Could not open Terminal: %@"),
        .wineConsoleOpened: ("已在终端打开 Wine 命令行", "Opened a Wine console in Terminal"),
        .enableDXVKShort: ("开启 DXVK", "Enable DXVK"),
        .interfaceLabel: ("界面", "Interface"),
        .wineLicense: ("GNU Lesser General Public License v2.1 或更高版本", "GNU Lesser General Public License v2.1 or later"),
        .appleChip: ("Apple 芯片", "Apple silicon"),
        .fpsOverlay: ("FPS 浮窗", "FPS Overlay"),
        .fpsOverlayHint: ("游戏运行时在 Mac 屏幕左上角显示这台电脑的 CPU 和内存。FPS、GPU 和温度读不到，因为浮窗不注入、不读取游戏进程。", "While a game is running, the Mac screen's top-left shows this computer's CPU and memory. FPS, GPU, and temperature are unavailable because the overlay does not inject into or read the game."),
        .perfWaiting: ("等待游戏", "Waiting for a game"),
        .backupSection: ("容器备份与存档", "Backups and Saves"),
        .backupNow: ("一键备份存档", "Back Up Saves"),
        .restoreBackup: ("备份还原", "Restore Backup"),
        .exportSave: ("导出存档", "Export Saves"),
        .backupEmpty: ("这个容器里还没有可备份的存档目录。", "This container has no save folders to back up yet."),
        .backupNoDrive: ("还没有找到这个容器的 C 盘，请先创建或打开容器。", "This container's C: drive was not found. Create or open the container first."),
        .backupDone: ("存档已打包备份。", "Saves were packed into a backup."),
        .backupFailed: ("备份没有完成，请稍后再试。", "The backup did not finish. Try again."),
        .backupRestored: ("存档已还原到容器。", "Saves were restored into the container."),
        .backupLibrary: ("备份游戏库", "Back Up Library"),
        .restoreLibrary: ("恢复游戏库", "Restore Library"),
        .libraryBackupDone: ("游戏库已导出。其中包含应用列表、游玩时长和本机解密所需的配置。", "The library was exported, including the app list, playtime, and the local files needed to read it."),
        .libraryRestoreDone: ("游戏库已恢复。应用列表和游玩时长已按备份还原。", "The library was restored, including the app list and playtime."),
        .libraryBackupFailed: ("游戏库备份没有完成。请确认目标文件夹可以写入。", "The library backup did not finish. Check that the destination folder can be written."),
        .themeSection: ("视觉主题", "Appearance"),
        .accentColor: ("高亮色", "Accent Color"),
        .accentDark: ("暗黑模式", "Dark"),
        .accentTechBlue: ("极简科技蓝", "Tech Blue"),
        .accentVaporwave: ("蒸汽波", "Vaporwave"),
        .wallpaper: ("启动器壁纸", "Launcher Wallpaper"),
        .wallpaperNone: ("无壁纸", "None"),
        .wallpaperNight: ("夜色霓虹", "Night Neon"),
        .wallpaperInk: ("山雾水墨", "Ink Mountains"),
        .wallpaperOrbit: ("深空机库", "Orbital Hangar"),
        .chooseWallpaper: ("选择本地图片", "Choose Image"),
        .wallpaperDrop: ("把图片拖到这里，或选择一张默认壁纸。", "Drop an image here, or pick a built-in wallpaper."),
        .detailOverview: ("详情", "Details"),
        .detailMods: ("模组 / Mods", "Mods"),
        .modsEmpty: ("还没有导入 Mod。", "No mods imported yet."),
        .modsHint: ("只管理本机 Mod 文件夹。启用或禁用不会修改联机组件，也不会改动反作弊。", "This only manages local mod folders. Enabling or disabling does not change online components or anti-cheat."),
        .importMod: ("导入 Mod 文件夹", "Import Mod Folder"),
        .openMods: ("一键打开 Mods 目录", "Open Mods Folder"),
        .modOn: ("已启用", "Enabled"),
        .modOff: ("已禁用", "Disabled"),
        .loadedPath: ("已加载路径: %@", "Loaded: %@"),
        .languageMenu: ("🌐 语言 / Language", "🌐 Language"),
        .filterAll: ("全部", "All"),
        .filterGame: ("游戏", "Games"),
        .filterOffice: ("办公", "Office"),
        .filterTool: ("工具", "Tools"),
        .filterAction: ("动作", "Action"),
        .filterRPG: ("RPG", "RPG"),
        .filterShooter: ("射击", "Shooter"),
        .filterOnline: ("网游", "Online"),
        .sidebarMain: ("主功能区", "Main"),
        .sidebarCategories: ("分类区", "Categories"),
        .favorites: ("收藏夹", "Favorites"),
        .favoritesEmpty: ("还没有收藏", "No favorites yet"),
        .favoritesEmptyHint: ("点亮卡片上的星星，游戏就会出现在这里。", "Star a game and it will show up here."),
        .favorite: ("收藏", "Add to Favorites"),
        .unfavorite: ("取消收藏", "Remove from Favorites"),
        .sidebarSettings: ("设置区", "Settings"),
        .enterLicense: ("输入激活码", "Enter License Key"),
        .getLicense: ("获取许可证", "Get a License"),
        .translationEngine: ("转译引擎", "Translation Engine"),
        .translationHint: ("DXVK 适合多数 DirectX 游戏。Metal 使用系统默认图形。D3DMetal 只在 CrossOver 下可用。", "DXVK suits most DirectX games. Metal uses the system graphics path. D3DMetal is available with CrossOver."),
        .hostEngine: ("兼容层", "Compatibility Engine"),
        .hostEngineHint: ("使用系统里的 wine64。路径包括 /usr/local/bin/wine64 和 Homebrew 的 wine64。", "Uses the system wine64, including /usr/local/bin/wine64 and Homebrew's wine64."),
        .diagnostics: ("🩺 硬件与环境诊断", "🩺 Hardware and Environment"),
        .repairEnvironment: ("一键修复/配置环境", "Repair / Configure"),
        .diagReady: ("正常", "Ready"),
        .diagMissing: ("缺失", "Missing"),
        .diagPartial: ("部分可用", "Partial"),
        .diagRosetta: ("Rosetta 2", "Rosetta 2"),
        .diagWhisky: ("Wine 引擎", "Wine Engine"),
        .diagCpp: ("C++ 运行库", "C++ Runtime"),
        .diagRosettaIntel: ("这台 Mac 是 Intel 芯片，不需要 Rosetta 2。", "This Intel Mac does not need Rosetta 2."),
        .diagRosettaReady: ("Rosetta 2 已安装，可以运行 x86_64 程序。", "Rosetta 2 is installed and can run x86_64 programs."),
        .diagRosettaMissing: ("没有检测到 Rosetta 2。一键修复会请求安装。", "Rosetta 2 was not found. Repair will ask to install it."),
        .diagWhiskyReady: ("已找到标准 wine64。", "A standard wine64 was found."),
        .diagWhiskyPartial: ("wine64 还不可用。", "wine64 is not ready."),
        .diagWhiskyMissing: ("没有找到 /usr/local/bin/wine64 或 Homebrew 的 wine64。", "/usr/local/bin/wine64 and Homebrew's wine64 were not found."),
        .diagCppReady: ("系统 libc++ 可用，容器里也能找到 vcruntime140.dll。", "The system libc++ is available, and vcruntime140.dll was found in a container."),
        .diagCppPartial: ("系统 libc++ 可用。容器里还没有 vcruntime140.dll。", "The system libc++ is available. vcruntime140.dll is not in a container yet."),
        .diagCppMissing: ("没有找到系统 libc++。", "The system libc++ was not found."),
        .diagRepairDone: ("环境已重新检测。需要时会安装 Rosetta。", "The environment was checked again. Rosetta installs when needed."),
        .diagRepairFailed: ("Rosetta 安装没有完成。可以在系统提示中允许安装后再试。", "Rosetta did not finish installing. Allow the system prompt and try again."),
        .performanceMode: ("性能模式", "Performance"),
        .balancedMode: ("画质平衡模式", "Balanced Quality"),
        .profileHint: ("性能模式使用 DXVK。画质平衡模式使用 D3DMetal。", "Performance uses DXVK. Balanced quality uses D3DMetal."),
        .licensePrompt: ("输入许可证密钥", "Enter license key"),
        .buyLicense: ("购买激活码", "Buy a License"),
        .activateOnline: ("在线激活", "Activate Online"),
        .activationSaved: ("密钥已写入这台 Mac 的钥匙串，界面会显示终身授权。在线商店还没有回传订单。", "The key is stored in this Mac's Keychain and the lifetime badge is shown. The store has not confirmed an order."),
        .activationOffline: ("购买页没有连上。密钥仍写入钥匙串，并显示终身授权。在线商店还没有回传订单。", "The purchase page did not respond. The key is still in the Keychain and the lifetime badge is shown. The store has not confirmed an order."),
        .proLockedHint: ("试用已结束。DXVK、Metal 和 Esync 等高级加速需要 Pro。可以输入激活码，或前往购买页。", "The trial has ended. DXVK, Metal, and Esync need Pro. Enter a license key, or open the purchase page."),
        .licenseKeychainFailed: ("授权状态没有写入钥匙串，这次没有记为已激活。", "The license could not be saved in the Keychain, so it was not marked active."),
        .integrityFailedTitle: ("应用完整性校验未通过", "App integrity check failed"),
        .integrityFailedBody: ("主程序或资源目录与代码签名不一致，文件可能被改动过。请重新安装官方版本。", "The app or its resources do not match the code signature and may have been modified. Reinstall the official build."),
        .libraryTampered: ("游戏列表文件无法解密，可能被改动过。原文件已保留，没有用空数据覆盖。", "The game library could not be decrypted and may have been modified. The original file was kept and was not replaced with empty data."),
        .recentGames: ("最近游戏", "Recent Games"),
        .noRecentGames: ("还没有最近启动的游戏", "No recently launched games"),
        .libraryShortcuts: ("游戏库", "Library"),
        .membershipTitle: ("解锁 Vesta Pro 终身版", "Unlock Vesta Pro for life"),
        .membershipSubtitle: ("专为 macOS 打造的高性能游戏管理与优化中心", "A high-performance game library and tuning center built for macOS"),
        .membershipUnlocked: ("您已成功激活 Vesta 永久会员", "Vesta lifetime membership is active on this Mac"),
        .membershipUnlockedDetail: ("感谢支持！已为您解锁无限制容器管理、性能监测浮窗与高级图形优化。", "Thank you. Container management, the performance overlay, and advanced graphics options are available on this Mac."),
        .membershipPitch: ("一次购买，终身使用。支付后您将通过邮箱收到激活码。", "One purchase, lifetime use. The activation code arrives by email after payment."),
        .membershipPay: ("前往网页安全支付", "Pay securely on the web"),
        .membershipHaveKey: ("已有激活码？在此输入：", "Already have a code? Enter it here:"),
        .membershipKeyPlaceholder: ("请输入您的 License Key", "Enter your license key"),
        .vestaAuthSubtitle: ("登录账户以同步您的 Pro 会员权益", "Sign in to sync your Vesta Pro membership"),
        .authTabAccount: ("账户登录", "Account"),
        .authTabKey: ("激活码兑换", "License Key"),
        .authGoogle: ("使用 Google 账号登录", "Continue with Google"),
        .authOr: ("或使用快捷方式", "Or use another method"),
        .authEmail: ("邮箱登录", "Email"),
        .authPhone: ("手机号登录", "Phone"),
        .authEmailPlaceholder: ("请输入电子邮箱", "Enter your email"),
        .authSendLink: ("发送邮箱验证码", "Send an email code"),
        .authEmailCode: ("请输入 6 位邮箱验证码", "Enter the 6-digit email code"),
        .authConfirmLogin: ("确认并登录", "Confirm and sign in"),
        .authCodeInvalid: ("请输入正确的 6 位验证码", "Enter the 6-digit code"),
        .authPhonePlaceholder: ("请输入手机号", "Enter your phone number"),
        .authGetCode: ("获取短信验证码", "Send an SMS code"),
        .authKeyHint: ("如果您已在 Stripe 网页端完成购买，可直接输入兑换码激活：", "If you already paid on the Stripe page, enter the code here:"),
        .authKeyPlaceholder: ("例如: VESTA-XXXX-XXXX-XXXX", "Example: VESTA-XXXX-XXXX-XXXX"),
        .authActivate: ("验证并激活 Vesta Pro", "Verify and activate Vesta Pro"),
        .authUnavailable: ("账户登录尚未接入服务器，不会同步会员。请用激活码在这台 Mac 上解锁。", "Account sign-in is not connected to a server and will not sync membership. Use a license key on this Mac."),
        .authAppleNoSync: ("Apple 登录已完成，但账户同步尚未接入，这台 Mac 的会员状态没有改变。", "Apple sign-in finished, but account sync is not connected, so membership on this Mac is unchanged."),
        .authAppleFailed: ("Apple 登录失败：%@", "Apple sign-in failed: %@"),
        .emailLoginTitle: ("使用电子邮箱登录 Vesta", "Sign in to Vesta with email"),
        .emailLoginSubtitle: ("邮箱验证码还没有接入邮件服务，现在不会发信，也不会登录账户。", "Email codes are not connected to a mail service. No message is sent, and the account is not signed in."),
        .emailLoginPlaceholder: ("请输入您的常用邮箱", "Enter your email"),
        .emailLoginSend: ("获取邮箱验证码", "Email me a code"),
        .chooseCountry: ("选择国家或地区", "Choose a Country or Region"),
        .countrySearchPrompt: ("搜索国家或区号 (如 中国 / +61)", "Search a country or code (e.g. China / +61)"),
        .phoneLoginTitle: ("Vesta 全球手机号登录", "Vesta phone sign-in"),
        .accountSettings: ("账户", "Account"),
        .accountSection: ("账户信息", "Account"),
        .accountSignedOut: ("您尚未登录账号", "You are not signed in"),
        .accountSignIn: ("去登录 / 激活", "Sign In / Activate"),
        .accountSignedIn: ("已登录", "Signed in"),
        .accountSignOut: ("退出登录", "Sign Out"),
        .profileTitle: ("个人信息", "Profile"),
        .profileUsername: ("昵称", "Name"),
        .profileUsernamePrompt: ("输入昵称，可以使用 #、★、_ 等符号", "Enter a name. Symbols such as #, ★, and _ are allowed"),
        .profileBirthday: ("生日", "Birthday"),
        .profileSave: ("保存", "Save"),
        .profileSaved: ("个人信息已保存。", "Profile saved."),
        .profileChoosePhoto: ("选择头像", "Choose Photo"),
        .profileSignInFirst: ("登录后才能编辑个人信息。", "Sign in before editing your profile."),
        .supabaseNotConfigured: ("还没有填入 Supabase 项目地址和匿名密钥，因此不会连接服务器。", "The Supabase project URL and anon key are still placeholders, so the app does not contact the server."),
        .supabaseAwaitConfirm: ("注册已提交。邮箱确认完成前，这台 Mac 上还没有登录会话。", "Sign-up was submitted. There is no session on this Mac until the email is confirmed."),
        .serviceSection: ("当前服务与授权", "Plan and License"),
        .licenseManageSection: ("授权管理", "License"),
        .restorePurchases: ("恢复历史购买", "Restore Purchases"),
        .upgradeLifetime: ("立即升级为 Vesta Pro 终身版 ($AUD 99.99)", "Upgrade to Vesta Pro Lifetime ($AUD 99.99)"),
        .serviceTrialTitle: ("Vesta Pro 试用版", "Vesta Pro Trial"),
        .serviceLifetimeTitle: ("Vesta Pro 终身永久授权", "Vesta Pro Lifetime"),
        .serviceExpiredTitle: ("试用期已结束", "Trial Ended"),
        .serviceTrialBody: ("您正在体验 Vesta 的全部高级功能。试用期结束后需购买永久授权以继续使用。", "You are trying Vesta Pro. A lifetime license is required after the trial."),
        .serviceLifetimeBody: ("一次购买，终身享有无限容器管理、性能监测浮窗与全部未来更新。", "One purchase covers lifetime container management, the performance overlay, and future updates."),
        .serviceExpiredBody: ("您的 14 天免费试用已到期，部分高级功能已被锁定，请升级或输入激活码。", "The 14-day trial has ended. Upgrade or enter a license key."),
        .accountTrialDays: ("剩余 %d 天", "%d days left"),
        .lifetimeBadge: ("永久有效", "Lifetime"),
        .expiredBadge: ("已过期", "Expired"),
        .enterSavedLicense: ("输入兑换码 / 激活码 (License Key)", "Enter a License Key"),
        .licenseRestoredLocal: ("已重新读到这台 Mac 上保存的激活码。在线商店没有回传订单。", "The license key saved on this Mac was read again. The store has not confirmed an order."),
        .licenseRestoreEmpty: ("这台 Mac 上没有已保存的激活码，云端账单也还没有接入。", "No license key is saved on this Mac, and cloud receipts are not connected."),
        .deviceIDTitle: ("当前电脑机器码", "Device ID"),
        .deviceIDHint: ("登录或激活时会把账号和这台 Mac 绑定。换机请联系客服解绑。", "Sign-in and activation bind the account to this Mac. Contact support to move it."),
        .deviceIDCopy: ("复制机器码", "Copy Device ID"),
        .deviceIDCopied: ("机器码已复制", "Device ID copied"),
        .deviceIDUnavailable: ("读不到这台 Mac 的硬件序列号", "This Mac's hardware serial number could not be read"),
        .deviceBindTitle: ("无法激活", "Cannot activate"),
        .deviceBoundElsewhere: ("该账号已在其他设备激活，如需换机请联系客服解绑", "This account is already activated on another device. Contact support to unbind it."),
        .deviceBoundOtherEmail: ("这台 Mac 已绑定其他账号，不能再用新邮箱激活。", "This Mac is already bound to another account."),
        .deviceBindFailed: ("没能把这台 Mac 写入授权记录，这次没有激活。", "This Mac could not be saved in the license record, so it was not activated."),
        .storageSection: ("容器存储", "Container Storage"),
        .storageUsed: ("VestaContainer 占用 %@", "VestaContainer uses %@"),
        .storageCache: ("可清理缓存 %@", "Cache that can be cleared: %@"),
        .storageRefresh: ("重新计算占用", "Recalculate"),
        .storageClearCache: ("清理容器缓存", "Clear Container Cache"),
        .storageCleared: ("已清理 %@", "Cleared %@"),
        .archiveExport: ("导出整包备份", "Export Full Backup"),
        .archiveImport: ("导入整包备份", "Import Full Backup"),
        .archiveImportConfirm: ("将用这份 .vestabackup 覆盖当前游戏库和 Wine 容器，并写回其中的渲染食谱。存档专用 zip 不会被改动。", "This .vestabackup replaces the current library and Wine container, and writes back the saved render recipes. Save-only zip backups are left as they are."),
        .archiveExportDone: ("已导出 .vestabackup，里面包含游戏库、Wine 容器和每款游戏的渲染食谱。", "Exported a .vestabackup with the library, Wine container, and each game's render recipe."),
        .archiveImportDone: ("已从 .vestabackup 恢复游戏库、Wine 容器和渲染食谱。", "Restored the library, Wine container, and render recipes from the .vestabackup."),
        .archiveFailed: ("整包备份没有完成。", "The full backup did not finish."),
        .statusRunning: ("运行中", "Running"),
        .statusStop: ("停止", "Stop"),
        .presetSection: ("智能预设", "Game Preset"),
        .presetApply: ("应用此方案", "Apply Preset"),
        .presetHint: ("点标签即可写好这款游戏的渲染方式。DXVK 会进入启动参数；D3DMetal 只在 CrossOver 下生效。VC++ 只检查容器里是否已有，不会另外下载。", "A tag writes this game's renderer. DXVK is added to the launch environment. D3DMetal is sent only to CrossOver. VC++ is checked in the container and is not downloaded."),
        .presetCustom: ("自定义", "Custom"),
        .presetShooter: ("射击", "Shooter"),
        .presetRPG: ("RPG", "RPG"),
        .presetAction: ("动作", "Action"),
        .presetUtility: ("工具", "Utility"),
        .presetEngineUnreal: ("Unreal Engine", "Unreal Engine"),
        .presetEngineUnity: ("Unity", "Unity"),
        .presetEngineDX11: ("DirectX 11", "DirectX 11"),
        .presetEngineDX12: ("DirectX 12", "DirectX 12"),
        .presetDXVK: ("DXVK", "DXVK"),
        .presetD3DMetal: ("D3DMetal", "D3DMetal"),
        .presetVirtualDesktop: ("虚拟桌面", "Virtual Desktop"),
        .presetD3DMetalWine: ("当前是 Wine 容器，D3DMetal 不会传给 wine64。换成 CrossOver 后才会启用。", "This is a Wine prefix, so D3DMetal is not passed to wine64. It is used only with CrossOver."),
        .presetDXVKOn: ("DXVK：启动时启用", "DXVK: enabled at launch"),
        .presetDXVKOff: ("DXVK：未启用", "DXVK: off"),
        .presetRuntimeReady: ("VC++ 2022：容器里已有 vcruntime140.dll", "VC++ 2022: vcruntime140.dll is already in the container"),
        .presetRuntimeMissing: ("VC++ 2022：容器里还没有，不会自动下载安装包", "VC++ 2022: not in the container, and no installer is downloaded"),
        .presetMetalFX: ("AI 性能超分辨率（MetalFX）", "AI Upscaling (MetalFX)"),
        .presetMetalFXReady: ("这台 Mac 支持 MetalFX。开启后只在 CrossOver 的 D3DMetal 启动参数里写入 D3DM_ENABLE_METALFX，不会往游戏进程里插帧。", "This Mac supports MetalFX. When on, D3DM_ENABLE_METALFX is sent only with CrossOver D3DMetal. Frames are not inserted into the game."),
        .presetMetalFXWine: ("MetalFX 已记入预设。当前是 Wine 容器，不会把 D3DM_ENABLE_METALFX 传给 wine64。", "MetalFX is saved on the preset. This Wine prefix does not receive D3DM_ENABLE_METALFX."),
        .presetMetalFXUnsupported: ("这台 Mac 的 GPU 不支持 MetalFX 超采样。", "This Mac's GPU does not support MetalFX upscaling."),
        .presetEsync: ("ESync 多线程同步", "ESync"),
        .presetFsync: ("FSync（eventfd）", "FSync (eventfd)"),
        .presetFsyncReady: ("检测到 Wine 内核包含 FSync，开启后写入 WINEFSYNC。", "This Wine build includes FSync. When on, launch sets WINEFSYNC."),
        .presetFsyncFallback: ("当前 Wine 没有 FSync。开启后会改用 ESync 和 macOS 的 WINEMSYNC。", "This Wine build has no FSync. When on, launch uses ESync and macOS WINEMSYNC instead."),
        .shaderDeepClean: ("深度清理着色器缓存", "Deep-clean Shader Cache"),
        .shaderDeepCleanDone: ("已清理着色器缓存 %@", "Cleared %@ of shader cache"),
        .recipeApply: ("一键应用食谱", "Apply Recipe"),
        .recipeGeneric: ("没有这款游戏的专属食谱，可按类型套用预设。", "This game has no dedicated recipe. A category preset can still be applied."),
        .recipeAntiCheat: ("只给启动器窗口写虚拟桌面，不注入 DXVK，也不打开 ESync/FSync。Vanguard 和 BattlEye 不会在 Wine 里运行，也不会被关闭或绕过。", "This recipe only uses a virtual desktop for the launcher window. It does not inject DXVK or enable ESync/FSync. Vanguard and BattlEye do not run under Wine and are not disabled or bypassed."),
        .recipeOnline: ("已写入单机渲染偏好。在线对战的反作弊不会被关闭或绕过。", "Single-player render preferences are saved. Online anti-cheat is not disabled or bypassed."),
        .recipeSinglePlayer: ("已按 DirectX 版本写好 DXVK、ESync，以及 CrossOver 下的 D3DMetal / MetalFX 偏好。不会往游戏里插帧，也不会下载 VC++。", "DXVK, ESync, and the CrossOver D3DMetal / MetalFX preference are saved for this DirectX version. Frames are not inserted into the game, and VC++ is not downloaded."),
        .recipeLight: ("轻量游戏只打开 DXVK，不启用多线程同步。", "This lighter game enables DXVK only, without multithreaded sync."),
        .recipeSteamClient: ("Steam 客户端本身不走 DXVK，避免盖掉游戏自己的渲染设置。", "The Steam client itself does not use DXVK, so it does not override a game's renderer."),
        .graphicsBackend: ("图形后端", "Graphics Backend"),
        .graphicsSync: ("同步机制", "Sync"),
        .syncOff: ("关闭", "Off"),
        .archiveBottleHint: ("打包当前 Wine 容器、游戏库和渲染食谱。下面的存档 zip 只含存档目录，两份备份互不影响。", "Packs the current Wine container, library, and render recipes. The save zip below contains only save folders, and the two backups stay separate."),
        .saveSyncSection: ("存档同步", "Save Sync"),
        .saveSyncScope: ("只扫描 Documents、Saved Games、AppData/Roaming 和 LocalLow。不复制游戏本体，也不动原来的存档 zip。", "Scans Documents, Saved Games, AppData/Roaming, and LocalLow only. Game files are not copied, and the existing save zip is left as it is."),
        .saveSyncScan: ("重新扫描", "Scan Again"),
        .saveSyncFound: ("找到 %@ 处存档目录", "Found %@ save folders"),
        .saveSyncEmpty: ("容器里还没有这些存档目录。", "Those save folders are not in the container yet."),
        .saveSyncBackup: ("备份到文件夹", "Back Up to Folder"),
        .saveSyncBackupDone: ("存档已加密写入所选位置。", "Saves were encrypted and written to the chosen location."),
        .saveSyncFailed: ("这次存档操作没有完成，容器里的进度没有被覆盖。", "The save operation did not finish, and progress in the container was not overwritten."),
        .saveSynciCloud: ("同步到 iCloud Drive", "Sync to iCloud Drive"),
        .saveSynciCloudMissing: ("没有找到 iCloud Drive，这次没有上传。", "iCloud Drive was not found, so nothing was uploaded."),
        .saveSyncVault: ("存入本机加密库", "Save to Local Vault"),
        .saveSyncVaultPlain: ("这台 Mac 还没有游戏库密钥，这次按未加密文件保存。", "This Mac has no library key yet, so this copy was saved without encryption."),
        .saveSyncNewerCloud: ("iCloud Drive 里有较新的存档。启动前要先恢复吗？不恢复也会直接开游戏。", "iCloud Drive has a newer save. Restore it before launch? The game still starts if you skip."),
        .saveSyncRestoreBeforeLaunch: ("先恢复再启动", "Restore, Then Launch"),
        .saveSyncRestored: ("已把云端存档写回容器。恢复前的进度留在本机加密库。", "The cloud save was written back into the container. The previous progress remains in the local vault."),
        .saveSyncSkip: ("直接启动", "Launch Anyway"),
        .perfNoInject: ("FPS、GPU、温度不可用", "FPS, GPU, and temperature unavailable"),
        .otaSection: ("组件检查", "Components"),
        .otaCheck: ("检查 GitHub 标签", "Check GitHub Tag"),
        .otaWineReady: ("本机已有 wine64。固定使用校验过的 Whisky v3.1.1，不会在后台换成别的版本。", "wine64 is already on this Mac. It stays on the verified Whisky v3.1.1 build and is not replaced in the background."),
        .otaWineMissing: ("还没有 wine64。可以下载那一份已经校验过的运行时。", "wine64 is missing. The already verified runtime can be downloaded."),
        .otaNoReplace: ("GitHub 上仍是已校验的 v3.1.1，没有需要替换的包。", "GitHub still shows the verified v3.1.1 tag. There is no package to replace."),
        .otaNewerUnverified: ("GitHub 标签是 %@。它还没有做和现有 Wine 一样的 SHA-256 固定，所以不会下载或替换。", "The GitHub tag is %@. It does not have the same pinned SHA-256 as the current Wine build, so it is not downloaded or installed."),
        .otaDXVK: ("DXVK 不是单独安装包。已授权时由启动参数打开。", "DXVK is not a separate installer. When licensed, launch turns it on with environment variables."),
        .otaMoltenVKFound: ("Wine 的 lib 目录里已有 MoltenVK，不会另外替换。", "MoltenVK is already in the Wine lib folder and is not replaced."),
        .otaMoltenVKMissing: ("当前 Wine 目录里没有单独的 MoltenVK，也不会从网上另拉一份。", "This Wine folder has no separate MoltenVK, and one is not downloaded."),
        .otaD3DMetal: ("D3DMetal 随 CrossOver 提供。Vesta 不下载、不替换它。", "D3DMetal comes with CrossOver. Vesta does not download or replace it."),
        .otaD3DMetalWine: ("当前不是 CrossOver，没有 D3DMetal 可更新。", "This Mac is not using CrossOver, so there is no D3DMetal to update."),
        .otaInstallPinned: ("下载已校验的 Wine", "Download Verified Wine"),
        .otaFailed: ("这次检查没有完成。", "The check did not finish."),
        .bindLocalApp: ("关联本机 App", "Link Local App"),
        .bindLocalAppHint: ("自动扫描没找到时，可以选择本机已有的 .app。关联后状态会显示为已安装。", "If the scan does not find it, choose an .app already on this Mac. Once linked, the status shows as installed."),
        .bindLocalAppInvalid: ("请选择一个 .app 应用。", "Choose an .app bundle."),
        .feedbackPane: ("💬 意见反馈", "💬 Send Feedback"),
        .feedbackTitle: ("意见反馈与建议", "Send Feedback"),
        .feedbackBody: ("有问题、想法或建议，可以直接写给团队。系统邮件会自动填好收件人和主题，你只需写内容并发送。", "Questions or ideas can go straight to the team. Mail opens with the address and subject filled in, so you can write and send."),
        .feedbackSend: ("发送建议/反馈", "Send Feedback"),
        .importDropHint: ("将 Windows 游戏 .exe 文件、.app 或文件夹拖拽至此处", "Drop a Windows .exe, an .app, or a game folder here"),
        .importDropReady: ("松开即可导入", "Release to import"),
        .cleanJunk: ("清理缓存与临时文件", "Clean Cache and Temporary Files"),
        .cleanJunkHint: ("清理 Wine 日志、临时目录，以及超过三周未使用的着色器缓存。不会删除游戏和存档。", "Removes Wine logs, temporary files, and shader cache unused for three weeks. Games and saves stay."),
        .cleanJunkDone: ("已释放 %@", "Freed %@")
    ]

    /// 日文和韩文。没有收录的词条回退到英文。
    private static let eastAsian: [L10nKey: (ja: String, ko: String)] = [
        .library: ("ライブラリ", "게임 라이브러리"),
        .settings: ("設定", "설정"),
        .about: ("ℹ️ 情報", "ℹ️ 정보"),
        .macZone: ("🍎 macOS 特区", "🍎 macOS 전용"),
        .macGames: ("🎮 大作ゲーム", "🎮 대작 게임"),
        .macTools: ("🛠️ 便利ツール", "🛠️ 유틸리티"),
        .importExe: ("ゲーム / コンテナアプリを追加", "게임 / 컨테이너 앱 가져오기"),
        .searchApps: ("アプリやパブリッシャーを検索", "앱 또는 퍼블리셔 검색"),
        .hardwareSummary: ("Mac ハードウェアの概要", "Mac 하드웨어 요약"),
        .running: ("実行中", "실행 중"),
        .notRunning: ("未実行", "실행 안 됨"),
        .preferences: ("環境設定", "환경 설정"),
        .general: ("⚙️ 一般", "⚙️ 일반"),
        .graphics: ("🖥️ グラフィックス", "🖥️ 그래픽"),
        .appearance: ("外観", "보기 모드"),
        .systemAppearance: ("システムに連動", "시스템 동기화"),
        .languageMenu: ("🌐 言語", "🌐 언어"),
        .filterAll: ("すべて", "전체"),
        .filterGame: ("ゲーム", "게임"),
        .filterOffice: ("ビジネス", "오피스"),
        .filterTool: ("ツール", "도구"),
        .trialRemaining: ("試用期間中 · 残り %d 日", "체험판 사용 중 · %d일 남음"),
        .sidebarMain: ("メイン", "주요 기능"),
        .sidebarCategories: ("カテゴリ", "분류"),
        .sidebarSettings: ("設定", "설정"),
        .enterLicense: ("ライセンスキーを入力", "라이선스 키 입력"),
        .getLicense: ("ライセンスを取得", "라이선스 받기"),
        .translationEngine: ("変換エンジン", "변환 엔진"),
        .translationHint: ("DXVK は多くの DirectX ゲーム向けです。Metal はシステムの既定です。D3DMetal は Apple の変換です。", "DXVK는 대부분의 DirectX 게임에 맞습니다. Metal은 시스템 기본 그래픽입니다. D3DMetal은 Apple 변환입니다."),
        .diagnostics: ("🩺 ハードウェアと環境", "🩺 하드웨어와 환경"),
        .repairEnvironment: ("環境を修復 / 設定", "환경 복구 / 설정"),
        .performanceMode: ("性能モード", "성능 모드"),
        .balancedMode: ("画質バランス", "화질 균형"),
        .profileHint: ("性能モードは DXVK です。画質バランスは D3DMetal です。", "성능 모드는 DXVK입니다. 화질 균형은 D3DMetal입니다."),
        .licensePrompt: ("ライセンスキーを入力", "라이선스 키 입력"),
        .buyLicense: ("ライセンスを購入", "라이선스 구매"),
        .activateOnline: ("オンラインで有効化", "온라인 활성화"),
        .activated: ("ライセンス有効 / 買い切り", "라이선스 유효 / 평생"),
        .recentGames: ("最近のゲーム", "최근 게임"),
        .noRecentGames: ("最近起動したゲームはありません", "최근 실행한 게임이 없습니다"),
        .libraryShortcuts: ("ライブラリ", "라이브러리")
    ]

    private struct Phrase {
        var fr: String
        var it: String
        var es: String
    }

    /// 法文、意大利文和西班牙文。没有收录的词条回退到英文，避免字典里重复键。
    private static let romance: [L10nKey: Phrase] = [
        .library: Phrase(fr: "Bibliothèque", it: "Libreria", es: "Biblioteca"),
        .settings: Phrase(fr: "Réglages", it: "Impostazioni", es: "Ajustes"),
        .about: Phrase(fr: "ℹ️ À propos", it: "ℹ️ Informazioni", es: "ℹ️ Acerca de"),
        .launchGame: Phrase(fr: "Lancer le jeu", it: "Avvia il gioco", es: "Iniciar juego"),
        .installViaSteam: Phrase(fr: "Installer via Steam", it: "Installa tramite Steam", es: "Instalar con Steam"),
        .downloadSetup: Phrase(fr: "Télécharger / Installer", it: "Scarica / Installa", es: "Descargar / Instalar"),
        .diskSufficient: Phrase(fr: "Espace disque suffisant", it: "Spazio su disco sufficiente", es: "Espacio en disco suficiente"),
        .diskInsufficient: Phrase(fr: "Espace disque insuffisant", it: "Spazio su disco insufficiente", es: "Espacio en disco insuficiente"),
        .localContainer: Phrase(fr: "Conteneur local", it: "Contenitore locale", es: "Contenedor local"),
        .steamLinkage: Phrase(fr: "Liaison Steam", it: "Collegamento Steam", es: "Vinculación con Steam"),
        .appNotFound: Phrase(fr: "Application introuvable", it: "Applicazione non trovata", es: "Aplicación no encontrada"),
        .installInContainerFirst: Phrase(fr: "Installez d'abord le jeu dans le conteneur.", it: "Installa prima il gioco nel contenitore.", es: "Instala primero el juego en el contenedor."),
        .installed: Phrase(fr: "Installé", it: "Installato", es: "Instalado"),
        .inLibrary: Phrase(fr: "Dans la bibliothèque", it: "In libreria", es: "En la biblioteca"),
        .notInstalled: Phrase(fr: "Non installé", it: "Non installato", es: "No instalado"),
        .notRunning: Phrase(fr: "Non lancé", it: "Non in esecuzione", es: "No en ejecución"),
        .running: Phrase(fr: "En cours", it: "In esecuzione", es: "En ejecución"),
        .launching: Phrase(fr: "Lancement", it: "Avvio", es: "Iniciando"),
        .launchingNow: Phrase(fr: "Lancement…", it: "Avvio…", es: "Iniciando…"),
        .ready: Phrase(fr: "Prêt", it: "Pronto", es: "Listo"),
        .stopped: Phrase(fr: "Arrêté", it: "Interrotto", es: "Detenido"),
        .version: Phrase(fr: "Version", it: "Versione", es: "Versión"),
        .publisher: Phrase(fr: "Éditeur", it: "Editore", es: "Editor"),
        .kind: Phrase(fr: "Type", it: "Tipo", es: "Tipo"),
        .platform: Phrase(fr: "Plateforme", it: "Piattaforma", es: "Plataforma"),
        .category: Phrase(fr: "Catégorie", it: "Categoria", es: "Categoría"),
        .installStatus: Phrase(fr: "État d'installation", it: "Stato di installazione", es: "Estado de instalación"),
        .container: Phrase(fr: "Conteneur", it: "Contenitore", es: "Contenedor"),
        .lastRun: Phrase(fr: "Dernier lancement", it: "Ultima esecuzione", es: "Última ejecución"),
        .noContainer: Phrase(fr: "Aucun conteneur", it: "Nessun contenitore", es: "Sin contenedor"),
        .notRunYet: Phrase(fr: "Jamais lancé", it: "Mai avviato", es: "Aún no ejecutado"),
        .today: Phrase(fr: "Aujourd'hui %@", it: "Oggi %@", es: "Hoy %@"),
        .overviewGame: Phrase(fr: "📖 Aperçu", it: "📖 Panoramica", es: "📖 Descripción"),
        .overviewApp: Phrase(fr: "📖 Aperçu", it: "📖 Panoramica", es: "📖 Descripción"),
        .hardwareTitle: Phrase(fr: "💻 Configuration et prérequis", it: "💻 Hardware e requisiti", es: "💻 Hardware y requisitos"),
        .pcSpecs: Phrase(fr: "🪟 Configuration PC officielle", it: "🪟 Requisiti PC ufficiali", es: "🪟 Requisitos oficiales de PC"),
        .macSpecs: Phrase(fr: "🍎 Configuration Mac recommandée", it: "🍎 Configurazione Mac consigliata", es: "🍎 Configuración Mac recomendada"),
        .notProvided: Phrase(fr: "Non indiqué", it: "Non specificato", es: "No indicado"),
        .tuningTips: Phrase(fr: "⚠️ Notes et réglages", it: "⚠️ Note e ottimizzazione", es: "⚠️ Notas y ajustes"),
        .installPath: Phrase(fr: "Chemin d'installation", it: "Percorso di installazione", es: "Ruta de instalación"),
        .diskFree: Phrase(fr: "Espace disponible : %@ Go", it: "Spazio disponibile: %@ GB", es: "Espacio disponible: %@ GB"),
        .diskRequired: Phrase(fr: "Requis : %@ Go", it: "Richiesto: %@ GB", es: "Necesario: %@ GB"),
        .diskTotal: Phrase(fr: "Disque total : %@ Go", it: "Disco totale: %@ GB", es: "Disco total: %@ GB"),
        .diskEnoughBody: Phrase(fr: "Ce disque a %@ Go libres, assez pour les %@ Go requis. Vous pouvez le télécharger.", it: "Questo disco ha %@ GB liberi, sufficienti per i %@ GB richiesti. Puoi scaricarlo.", es: "Este disco tiene %@ GB libres, suficientes para los %@ GB necesarios. Puedes descargarlo."),
        .diskShortBody: Phrase(fr: "Il ne reste que %@ Go, ce qui est insuffisant (%@ Go requis). Libérez de l'espace ou changez l'emplacement.", it: "Restano solo %@ GB, non basta (%@ GB richiesti). Libera spazio o scegli un altro percorso.", es: "Solo quedan %@ GB, no es suficiente (%@ GB necesarios). Libera espacio o elige otra ubicación."),
        .refreshFiles: Phrase(fr: "🔄 Actualiser les fichiers locaux", it: "🔄 Aggiorna i file locali", es: "🔄 Actualizar archivos locales"),
        .needInstall: Phrase(fr: "Installation requise", it: "Installazione necessaria", es: "Instalación necesaria"),
        .wakeSteam: Phrase(fr: "Ouvrir Steam pour télécharger", it: "Apri Steam per scaricare", es: "Abrir Steam para descargar"),
        .cancel: Phrase(fr: "Annuler", it: "Annulla", es: "Cancelar"),
        .buySteam: Phrase(fr: "Obtenir sur Steam", it: "Ottieni su Steam", es: "Conseguir en Steam"),
        .appStore: Phrase(fr: "Obtenir sur l'App Store", it: "Ottieni sull'App Store", es: "Conseguir en el App Store"),
        .goDownload: Phrase(fr: "Télécharger", it: "Scarica", es: "Descargar"),
        .stop: Phrase(fr: "Arrêter", it: "Interrompi", es: "Detener"),
        .nativeMac: Phrase(fr: "macOS natif", it: "macOS nativo", es: "macOS nativo"),
        .searchApps: Phrase(fr: "Rechercher des apps ou des éditeurs", it: "Cerca app o editori", es: "Buscar apps o editores"),
        .importExe: Phrase(fr: "Importer un jeu / une app", it: "Importa gioco / app", es: "Importar juego / app"),
        .preferences: Phrase(fr: "Préférences", it: "Preferenze", es: "Preferencias"),
        .general: Phrase(fr: "⚙️ Général", it: "⚙️ Generale", es: "⚙️ General"),
        .graphics: Phrase(fr: "🖥️ Graphismes", it: "🖥️ Grafica", es: "🖥️ Gráficos"),
        .appearance: Phrase(fr: "Apparence", it: "Aspetto", es: "Apariencia"),
        .systemAppearance: Phrase(fr: "Système", it: "Sistema", es: "Sistema"),
        .light: Phrase(fr: "Clair", it: "Chiaro", es: "Claro"),
        .dark: Phrase(fr: "Sombre", it: "Scuro", es: "Oscuro"),
        .languageMenu: Phrase(fr: "🌐 Langue", it: "🌐 Lingua", es: "🌐 Idioma"),
        .filterAll: Phrase(fr: "Tout", it: "Tutti", es: "Todo"),
        .filterGame: Phrase(fr: "Jeux", it: "Giochi", es: "Juegos"),
        .filterOffice: Phrase(fr: "Bureautique", it: "Ufficio", es: "Oficina"),
        .filterTool: Phrase(fr: "Outils", it: "Strumenti", es: "Herramientas"),
        .trialRemaining: Phrase(fr: "Essai · %d jours restants", it: "Prova · %d giorni rimasti", es: "Prueba · %d días restantes"),
        .hardwareSummary: Phrase(fr: "Résumé du Mac", it: "Hardware del Mac", es: "Hardware del Mac"),
        .macZone: Phrase(fr: "🍎 Zone macOS", it: "🍎 Area macOS", es: "🍎 Zona macOS"),
        .macGames: Phrase(fr: "🎮 Grands jeux", it: "🎮 Grandi giochi", es: "🎮 Grandes juegos"),
        .macTools: Phrase(fr: "🛠️ Utilitaires", it: "🛠️ Utilità", es: "🛠️ Utilidades"),
        .fpsOverlay: Phrase(fr: "Fenêtre FPS", it: "Overlay FPS", es: "Ventana FPS"),
        .backupSection: Phrase(fr: "Sauvegardes", it: "Backup e salvataggi", es: "Copias y partidas"),
        .backupNow: Phrase(fr: "Sauvegarder", it: "Esegui backup", es: "Crear copia"),
        .restoreBackup: Phrase(fr: "Restaurer", it: "Ripristina", es: "Restaurar"),
        .exportSave: Phrase(fr: "Exporter", it: "Esporta", es: "Exportar"),
        .detailOverview: Phrase(fr: "Détails", it: "Dettagli", es: "Detalles"),
        .detailMods: Phrase(fr: "Mods", it: "Mod", es: "Mods"),
        .launchMethod: Phrase(fr: "Mode de lancement", it: "Modalità di avvio", es: "Modo de inicio"),
        .selectAppTitle: Phrase(fr: "Aucune app sélectionnée", it: "Nessuna app selezionata", es: "Ninguna app seleccionada"),
        .selectAppHint: Phrase(fr: "Choisissez une app dans la liste pour voir ses détails et la lancer.", it: "Scegli un'app nell'elenco per vedere i dettagli e avviarla.", es: "Elige una app de la lista para ver sus detalles y abrirla."),
        .showAll: Phrase(fr: "Tout afficher", it: "Mostra tutto", es: "Mostrar todo"),
        .noApps: Phrase(fr: "Aucune app", it: "Nessuna app", es: "Ninguna app"),
        .scanning: Phrase(fr: "Analyse…", it: "Scansione…", es: "Buscando…"),
        .scanLocal: Phrase(fr: "Analyser les jeux locaux", it: "Cerca giochi locali", es: "Buscar juegos locales"),
        .appCount: Phrase(fr: "%d apps", it: "%d app", es: "%d apps"),
        .runningCount: Phrase(fr: "%d en cours", it: "%d in esecuzione", es: "%d en ejecución"),
        .ok: Phrase(fr: "OK", it: "OK", es: "Aceptar"),
        .close: Phrase(fr: "Fermer", it: "Chiudi", es: "Cerrar"),
        .activate: Phrase(fr: "Activer", it: "Attiva", es: "Activar"),
        .licenseHeading: Phrase(fr: "Licence", it: "Licenza", es: "Licencia"),
        .productName: Phrase(fr: "Bibliothèque et conteneurs", it: "Libreria e contenitori", es: "Biblioteca y contenedores"),
        .sidebarMain: Phrase(fr: "Principal", it: "Principale", es: "Principal"),
        .sidebarCategories: Phrase(fr: "Catégories", it: "Categorie", es: "Categorías"),
        .sidebarSettings: Phrase(fr: "Réglages", it: "Impostazioni", es: "Ajustes"),
        .enterLicense: Phrase(fr: "Saisir la clé", it: "Inserisci il codice", es: "Introducir la clave"),
        .getLicense: Phrase(fr: "Obtenir une licence", it: "Ottieni una licenza", es: "Obtener una licencia"),
        .translationEngine: Phrase(fr: "Moteur de traduction", it: "Motore di traduzione", es: "Motor de traducción"),
        .translationHint: Phrase(fr: "DXVK convient à la plupart des jeux DirectX. Metal utilise le graphisme du système. D3DMetal utilise le traducteur d'Apple.", it: "DXVK va bene per la maggior parte dei giochi DirectX. Metal usa la grafica di sistema. D3DMetal usa il traduttore di Apple.", es: "DXVK encaja con la mayoría de juegos DirectX. Metal usa los gráficos del sistema. D3DMetal usa el traductor de Apple."),
        .diagnostics: Phrase(fr: "🩺 Matériel et environnement", it: "🩺 Hardware e ambiente", es: "🩺 Hardware y entorno"),
        .repairEnvironment: Phrase(fr: "Réparer / configurer", it: "Ripara / configura", es: "Reparar / configurar"),
        .performanceMode: Phrase(fr: "Performance", it: "Prestazioni", es: "Rendimiento"),
        .balancedMode: Phrase(fr: "Qualité équilibrée", it: "Qualità bilanciata", es: "Calidad equilibrada"),
        .profileHint: Phrase(fr: "Performance utilise DXVK. La qualité équilibrée utilise D3DMetal.", it: "Prestazioni usa DXVK. La qualità bilanciata usa D3DMetal.", es: "Rendimiento usa DXVK. La calidad equilibrada usa D3DMetal."),
        .licensePrompt: Phrase(fr: "Saisir la clé de licence", it: "Inserisci la chiave", es: "Introducir la clave"),
        .buyLicense: Phrase(fr: "Acheter une licence", it: "Acquista una licenza", es: "Comprar una licencia"),
        .activateOnline: Phrase(fr: "Activer en ligne", it: "Attiva online", es: "Activar en línea"),
        .activated: Phrase(fr: "Licence valide / à vie", it: "Licenza valida / a vita", es: "Licencia válida / de por vida"),
        .recentGames: Phrase(fr: "Jeux récents", it: "Giochi recenti", es: "Juegos recientes"),
        .noRecentGames: Phrase(fr: "Aucun jeu lancé récemment", it: "Nessun gioco avviato di recente", es: "Ningún juego iniciado recientemente"),
        .libraryShortcuts: Phrase(fr: "Bibliothèque", it: "Libreria", es: "Biblioteca")
    ]
}

struct L10nText: View {
    @EnvironmentObject private var language: LanguageManager
    let key: L10nKey

    var body: some View {
        Text(language.text(key))
    }
}

struct AppEnglishCopy {
    var name: String
    var summary: String
    var description: String
    var notice: String
}

enum SampleCopy {
    static func english(forName name: String) -> AppEnglishCopy? {
        copies[name]
    }

    static func displayName(_ name: String, language: AppLanguage) -> String {
        guard language == .english, let copy = english(forName: name) else { return name }
        return copy.name
    }

    static func specs(_ text: String, language: AppLanguage) -> String {
        guard language == .english else { return text }
        return text
            .replacingOccurrences(of: "统一内存", with: "unified memory")
            .replacingOccurrences(of: "或更高", with: "or newer")
            .replacingOccurrences(of: "轻量容器", with: "lightweight bottle")
            .replacingOccurrences(of: "容器", with: "bottle")
            .replacingOccurrences(of: "内存", with: "memory")
    }

    private static let copies: [String: AppEnglishCopy] = [
        "Steam": AppEnglishCopy(
            name: "Steam",
            summary: "Valve's game platform. Open the store, library, and installed Windows games inside a container.",
            description: "Valve's digital storefront. Sign in, browse the store, manage your library, and let official games handle downloads and cloud saves. Steam inside the container performs the ownership check and launch for Windows games.",
            notice: "1. The Steam client itself is light.\n2. Before launching inside a container, confirm that the Gaming bottle has DXVK enabled."
        ),
        "黑神话：悟空 (Black Myth: Wukong)": AppEnglishCopy(
            name: "Black Myth: Wukong",
            summary: "An action RPG from Game Science, installed in the Gaming bottle's Steam library.",
            description: "An action role-playing game rooted in Chinese mythology. You play the Destined One and set out on a dangerous, wondrous journey to the west in search of a lost legend. Built with Unreal Engine 5, the combat is fast and deep, and the Windows build can run through a Mac compatibility layer.",
            notice: "1. Enable D3DMetal plus ESync or FSync in the container.\n2. In game, turn on FSR, set the render scale to 67%, and disable v-sync."
        ),
        "赛博朋克 2077 (Cyberpunk 2077)": AppEnglishCopy(
            name: "Cyberpunk 2077",
            summary: "An open-world RPG in Night City. The executable is in the Steam library's x64 folder.",
            description: "An open-world action-adventure RPG. Night City is huge, glamorous, and dangerous. You play the mercenary V, chasing a one-of-a-kind implant. The game offers wide freedom and a striking cyberpunk look.",
            notice: "1. A short hitch while shaders load the first time is expected.\n2. Use the Medium preset and turn on FSR 2.1."
        ),
        "艾尔登法环 (Elden Ring)": AppEnglishCopy(
            name: "Elden Ring",
            summary: "FromSoftware's open-world action game. The executable is in the Game folder.",
            description: "FromSoftware's open-world action game. After the Shattering, you are a Tarnished crossing wilderness, castles, and underground ruins in search of the Elden Ring. Combat rewards timing, and exploration is full of risk and reward.",
            notice: "1. Enable D3DMetal in the container.\n2. The first visit may stutter while shaders compile.\n3. Lower shadows and the quality preset to hold the frame rate."
        ),
        "GTA 5 (Grand Theft Auto V)": AppEnglishCopy(
            name: "Grand Theft Auto V",
            summary: "Rockstar's open-world game, launched from GTA5.exe in the Gaming bottle.",
            description: "Rockstar's modern open-world city. You switch between three protagonists in Los Santos and follow a crime story that spans years, from street work to planned scores. Driving, shooting, and city life stay very open.",
            notice: "1. Enable DXVK or D3DMetal.\n2. Population density and shadows affect frame rate the most."
        ),
        "荒野大镖客：救赎 2 (Red Dead Redemption 2)": AppEnglishCopy(
            name: "Red Dead Redemption 2",
            summary: "Rockstar's Western open world, installed in the Gaming bottle's Steam library.",
            description: "Rockstar's epic open-world Western. You play Arthur Morgan of the Van der Linde gang, riding, robbing, and running across the American frontier in a story about honor, loyalty, and survival.",
            notice: "1. Use a compatible DXVK or Vulkan layer.\n2. Lower shadows and volumetric fog for a large gain in smoothness."
        ),
        "博德之门 3 (Baldur's Gate 3)": AppEnglishCopy(
            name: "Baldur's Gate 3",
            summary: "Larian's role-playing game. The executable is in the Baldur's Gate 3 bin folder.",
            description: "Larian Studios' role-playing game. In a Dungeons & Dragons world you build a party and explore freely. Every choice can change the story.",
            notice: "1. The game is large. Keep at least 150 GB free on an SSD.\n2. Act 3 is heavy on the CPU. Reduce crowd effects if needed."
        ),
        "怪物猎人：世界 (Monster Hunter: World)": AppEnglishCopy(
            name: "Monster Hunter: World",
            summary: "Capcom's action game, launched from MonsterHunterWorld.exe in the Gaming bottle.",
            description: "Capcom's cooperative hunting game. You investigate a new continent, track enormous monsters, and build weapons and armor from what you gather. Each hunt depends on terrain, weak points, and teamwork.",
            notice: "1. Enable D3DMetal in the container.\n2. During large monster fights, lower shadows and effects to stay smooth."
        ),
        "巫师 3：狂猎 (The Witcher 3: Wild Hunt)": AppEnglishCopy(
            name: "The Witcher 3: Wild Hunt",
            summary: "CD PROJEKT RED's role-playing game. The executable is in the x64 folder.",
            description: "CD PROJEKT RED's fantasy role-playing game. Geralt of Rivia searches for his adopted daughter Ciri across a war-torn continent, caught between kingdoms, monsters, and personal choices. Signs, swords, and alchemy offer many ways to fight.",
            notice: "1. Enable D3DMetal and turn on FSR in the game.\n2. Hair and shadows are expensive. Lower those first."
        ),
        "星露谷物语 (Stardew Valley)": AppEnglishCopy(
            name: "Stardew Valley",
            summary: "A farm-life simulation installed in the Gaming bottle's Steam library.",
            description: "A gentle farm-life simulation. You inherit a run-down farm in Pelican Town, then grow crops, fish, mine, and get to know the town. The pace is slow, and the seasons turn on their own.",
            notice: "1. Requirements are low. DXVK in the container is enough.\n2. If the window aspect is wrong, switch to borderless windowed mode."
        ),
        "生化危机 4：重制版 (Resident Evil 4)": AppEnglishCopy(
            name: "Resident Evil 4",
            summary: "Capcom's native macOS remake. It opens the local .app and does not use Wine.",
            description: "Capcom's full modern remake of the survival-horror classic. In a hostile European village, agent Leon S. Kennedy searches for the kidnapped president's daughter. The macOS version uses Metal 3 for sharp image quality and tense gunplay.",
            notice: "Native macOS support, with Metal 3 acceleration and MetalFX dynamic resolution."
        ),
        "死亡搁浅 导演剪辑版 (Death Stranding Director's Cut)": AppEnglishCopy(
            name: "Death Stranding Director's Cut",
            summary: "Kojima Productions' native macOS release. The system opens it when it is installed.",
            description: "Hideo Kojima's open-world game. In a future wasteland you play Sam Porter Bridges, carrying cargo across a ruined America to reconnect isolated communities. MetalFX upscaling is supported.",
            notice: "Native macOS support. Turn on MetalFX Quality mode in the game for a steadier frame rate."
        ),
        "博德之门 3 (Baldur's Gate 3 - Native)": AppEnglishCopy(
            name: "Baldur's Gate 3 (macOS)",
            summary: "The native macOS edition of Baldur's Gate 3, listed separately from the Windows bottle version.",
            description: "Larian Studios' role-playing game. In a Dungeons & Dragons world you build a party and explore freely. Every choice can change the story. This edition is a native macOS app and does not need Wine.",
            notice: "1. This is the native macOS edition and does not need a Wine container.\n2. Keep at least 150 GB free. In Act 3, lower crowd effects if needed."
        ),
        "无人深空 (No Man's Sky - Apple Silicon Native)": AppEnglishCopy(
            name: "No Man's Sky",
            summary: "Hello Games' Apple silicon native build. The store page opens when it is not installed.",
            description: "Hello Games' space exploration game. You fly, land, gather, and trade across a generated universe, build bases, and meet other travelers. The Apple silicon build renders planets with Metal.",
            notice: "1. The Apple silicon build uses Metal directly.\n2. Dynamic resolution in the graphics menu trades sharpness for a steadier frame rate."
        ),
        "Microsoft Word (Mac 原生版)": AppEnglishCopy(
            name: "Microsoft Word (Mac)",
            summary: "The native macOS word processor. It opens Microsoft Word.app on this Mac.",
            description: "Microsoft's word processor for writing documents, reports, and letters, with styles, comments, and common Office file formats. The macOS version runs directly on Apple silicon.",
            notice: "A native macOS office app with support for Apple silicon."
        ),
        "Microsoft Excel (Mac 原生版)": AppEnglishCopy(
            name: "Microsoft Excel (Mac)",
            summary: "The native macOS spreadsheet app. It opens Microsoft Excel.app on this Mac.",
            description: "Microsoft's spreadsheet app for tables, formulas, charts, and PivotTables. The macOS version does not need a container.",
            notice: "A native macOS spreadsheet app."
        ),
        "Microsoft PowerPoint (Mac 原生版)": AppEnglishCopy(
            name: "Microsoft PowerPoint (Mac)",
            summary: "The native macOS presentation app. It opens Microsoft PowerPoint.app on this Mac.",
            description: "Microsoft's presentation app for slides, animation, and slideshows. The macOS version opens common PowerPoint files directly.",
            notice: "A native macOS presentation app."
        ),
        "Microsoft Word (Windows 容器版)": AppEnglishCopy(
            name: "Microsoft Word (Windows)",
            summary: "The Windows edition of Word, run in the Office container.",
            description: "The Windows edition of Word running in the Office container. Use it when you need Windows macros, a specific add-in, or a layout that matches the Windows version. Licensing stays with official Office.",
            notice: "The Windows edition of Word, run through a Wine container."
        ),
        "Microsoft Excel (Windows 容器版)": AppEnglishCopy(
            name: "Microsoft Excel (Windows)",
            summary: "The Windows edition of Excel, run in the Office container.",
            description: "The Windows edition of Excel running in the Office container. Use it for Windows macros, add-ins, or complex workbooks. Formulas and charts match the Windows release.",
            notice: "The Windows edition of Excel, run through a Wine container."
        ),
        "Microsoft PowerPoint": AppEnglishCopy(
            name: "Microsoft PowerPoint (Windows)",
            summary: "The Windows edition of PowerPoint. Run it in the Office container.",
            description: "The Windows edition of PowerPoint running in the Office container. Use it for decks that depend on Windows fonts, animation, or add-ins.",
            notice: "For building slide decks and playing animations."
        ),
        "Notepad++ (Windows 容器版)": AppEnglishCopy(
            name: "Notepad++ (Windows)",
            summary: "The Windows edition of Notepad++, run in the Tools container.",
            description: "A light Windows text and code editor. It starts quickly, uses little memory, and is suited to configs, logs, and scripts, with syntax coloring and tabs.",
            notice: "A classic lightweight Windows code editor."
        ),
        "无畏契约（国服）": AppEnglishCopy(
            name: "VALORANT (China)",
            summary: "The Tencent China client. Accounts and servers stay separate.",
            description: "VALORANT in mainland China is operated by Tencent Games. It is the same 5v5 tactical shooter: aim and agent abilities decide each round. The China client uses Tencent’s own launcher, currently game 13.06 and launcher 2.17.3. Download the Windows installer in a browser, then bind the client to a Wine bottle.",
            notice: "Download the Tencent China client in your browser, then bind it to Wine to run."
        ),
        "瓦罗兰特（亚服）": AppEnglishCopy(
            name: "VALORANT (Asia-Pacific)",
            summary: "Riot’s Asia-Pacific client.",
            description: "The Asia-Pacific edition uses Riot’s official client and connects to the AP servers. Gunfights depend on crosshair placement and recoil; agent abilities scout, smoke, and control space. This installer is only for the AP shard. Download it in a browser, then bind it to Wine.",
            notice: "Download the Asia-Pacific Riot client in your browser, then bind it to Wine to run."
        ),
        "瓦罗兰特（美服）": AppEnglishCopy(
            name: "VALORANT (Americas)",
            summary: "Riot’s North America client.",
            description: "The Americas edition uses Riot’s official client and connects to the NA servers. Economy, utility, and positioning decide rounds; abilities change the pace, and aim still wins the duel. Download the NA installer, then bind it to Wine.",
            notice: "Download the Americas Riot client in your browser, then bind it to Wine to run."
        ),
        "瓦罗兰特（欧服）": AppEnglishCopy(
            name: "VALORANT (Europe)",
            summary: "Riot’s Europe client.",
            description: "The Europe edition uses Riot’s official client and connects to the EU servers. Fixed maps, round economy, and precise gunplay are the core of this 5v5 shooter. Download the EU installer, then bind it to Wine.",
            notice: "Download the Europe Riot client in your browser, then bind it to Wine to run."
        ),
        "绝地求生 (PUBG)": AppEnglishCopy(
            name: "PUBG: BATTLEGROUNDS",
            summary: "A hundred-player battle royale. Drop in, gear up, and survive the closing zone.",
            description: "KRAFTON’s battle royale. Up to one hundred players parachute onto the same map, scavenge weapons, and fight as the safe zone shrinks. Positioning, cover, and listening matter as much as aim. Download the Windows client in a browser, then drag the installer into Vesta and bind it to Wine.",
            notice: "Download the Windows client in your browser. When it finishes, drag the installer into Vesta and bind it to Wine."
        )
    ]
}

extension WindowsApp {
    func localizedName(_ language: AppLanguage) -> String {
        guard language == .english, let copy = SampleCopy.english(forName: name) else { return name }
        return copy.name
    }

    func localizedSummary(_ language: AppLanguage) -> String {
        guard language == .english, let copy = SampleCopy.english(forName: name), !copy.summary.isEmpty else { return summary }
        return copy.summary
    }

    func localizedDescription(_ language: AppLanguage) -> String {
        guard language == .english, let copy = SampleCopy.english(forName: name), !copy.description.isEmpty else { return description }
        return copy.description
    }

    func localizedNotice(_ language: AppLanguage) -> String? {
        guard language == .english, let copy = SampleCopy.english(forName: name), !copy.notice.isEmpty else { return noticeText }
        return copy.notice
    }

    func localizedCategory(_ language: AppLanguage) -> String {
        let source = category.isEmpty ? kind.rawValue : category
        switch source {
        case "游戏":
            return L10n.string(.filterGame, language: language)
        case "工具":
            return L10n.string(.filterTool, language: language)
        case "办公":
            return L10n.string(.filterOffice, language: language)
        case "平台":
            switch language {
            case .chinese: return source
            case .english: return "Platform"
            case .japanese: return "プラットフォーム"
            case .korean: return "플랫폼"
            case .french: return "Plateforme"
            case .italian: return "Piattaforma"
            case .spanish: return "Plataforma"
            }
        default:
            return source
        }
    }

    func localizedKind(_ language: AppLanguage) -> String {
        switch kind {
        case .game:
            switch language {
            case .chinese: return kind.title
            case .english: return "Game"
            case .japanese: return "ゲーム"
            case .korean: return "게임"
            case .french: return "Jeu"
            case .italian: return "Gioco"
            case .spanish: return "Juego"
            }
        case .office:
            switch language {
            case .chinese: return kind.title
            case .english: return "Office"
            case .japanese: return "ビジネス"
            case .korean: return "오피스"
            case .french: return "Bureautique"
            case .italian: return "Ufficio"
            case .spanish: return "Oficina"
            }
        case .utility:
            switch language {
            case .chinese: return kind.title
            case .english: return "Utility"
            case .japanese: return "ツール"
            case .korean: return "도구"
            case .french: return "Utilitaire"
            case .italian: return "Utilità"
            case .spanish: return "Utilidad"
            }
        }
    }

    func localizedPublisher(_ language: AppLanguage) -> String {
        if language == .english && publisher == "本地导入" {
            return L10n.string(.importedPublisher, language: .english)
        }
        return publisher
    }

    func regionTitle(_ language: AppLanguage) -> String {
        switch regionCode {
        case "cn": return L10n.string(.regionCN, language: language)
        case "ap": return L10n.string(.regionAP, language: language)
        case "na": return L10n.string(.regionNA, language: language)
        case "eu": return L10n.string(.regionEU, language: language)
        default: return ""
        }
    }

    func regionDownloadTitle(_ language: AppLanguage) -> String? {
        switch regionCode {
        case "cn": return L10n.string(.downloadCNClient, language: language)
        case "ap": return L10n.string(.downloadAPClient, language: language)
        case "na": return L10n.string(.downloadNAClient, language: language)
        case "eu": return L10n.string(.downloadEUClient, language: language)
        default: return nil
        }
    }

    func regionDownloadGuide(_ language: AppLanguage) -> String? {
        if ambientStyle == "pubg" {
            return L10n.string(.downloadGuidePUBG, language: language)
        }
        let key: L10nKey?
        switch regionCode {
        case "cn": key = .downloadGuideCN
        case "ap": key = .downloadGuideAP
        case "na": key = .downloadGuideNA
        case "eu": key = .downloadGuideEU
        default: key = nil
        }
        guard let key else { return nil }
        return L10n.string(key, language: language)
    }

    func localizedLastRun(_ language: AppLanguage) -> String {
        if lastRunText == "尚未运行" {
            return L10n.string(.notRunYet, language: language)
        }
        if lastRunText.hasPrefix("今天 ") {
            return L10n.format(.today, language, String(lastRunText.dropFirst("今天 ".count)))
        }
        return lastRunText
    }
}
