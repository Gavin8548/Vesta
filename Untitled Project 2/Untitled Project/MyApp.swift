import AppKit
import Combine
import SwiftUI

@MainActor
final class AppearanceController: ObservableObject {
    @Published var preference: AppearancePreference = .light {
        didSet {
            guard preference != oldValue else { return }
            VestaMainWindow.applyAppearance(preference)
        }
    }
}

extension AppearancePreference {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(VestaAppDelegate.self) private var appDelegate
    @StateObject private var appearance = AppearanceController()
    @AppStorage("MyApp.showsMenuBar") private var showsMenuBar = true
    @State private var menuBarVisible = false
    @State private var menuBarReady = false

    var body: some Scene {
        WindowGroup("Vesta") {
            ContentView()
                .environmentObject(LanguageManager.shared)
                .environmentObject(appearance)
                .background(.background)
                .preferredColorScheme(appearance.preference.colorScheme)
                .task {
                    await Task.yield()
                    menuBarVisible = showsMenuBar
                    await Task.yield()
                    menuBarReady = true
                }
                .onChange(of: showsMenuBar) { _, value in
                    guard menuBarVisible != value else { return }
                    menuBarVisible = value
                }
                .onChange(of: menuBarVisible) { _, value in
                    guard menuBarReady, showsMenuBar != value else { return }
                    showsMenuBar = value
                }
        }
        .defaultSize(width: 920, height: 580)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Vesta", systemImage: "flame.fill", isInserted: $menuBarVisible) {
            MenuBarLaunchRoot()
        }
    }
}

/// 点击顶栏后才读取最近游戏。场景构建期间不碰单例。
private struct MenuBarLaunchRoot: View {
    @State private var live = false

    var body: some View {
        Group {
            if live {
                VestaMenuBarLauncher()
                    .environmentObject(LanguageManager.shared)
            }
        }
        .task {
            await Task.yield()
            live = true
        }
    }
}

/// 打开系统自带的关闭、最小化、缩放和全屏。不额外加按钮，也不把窗口锁死在固定尺寸。
@MainActor
enum VestaMainWindow {
    static func enableNativeControls() {
        for window in NSApp.windows where window.canBecomeMain && !window.isSheet {
            var mask = window.styleMask
            mask.formUnion([.titled, .closable, .miniaturizable, .resizable])
            window.styleMask = mask
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            window.standardWindowButton(.closeButton)?.isEnabled = true
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
            window.standardWindowButton(.zoomButton)?.isEnabled = true
            window.contentMinSize = NSSize(width: 920, height: 580)
        }
    }

    /// 标题栏、侧边栏毛玻璃和系统控件只认窗口外观。这里把它和 SwiftUI 的色彩模式对齐。
    static func applyAppearance(_ preference: AppearancePreference) {
        let appearance = preference.nsAppearance
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
}

nonisolated final class VestaAppDelegate: NSObject, NSApplicationDelegate {
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        if VestaDevelopmentAccess.enabled {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            WineProcessCleanup.cleanStaleLocks()
            let report = BundleIntegrity.verify()
            guard !report.signatureValid else { return }
            DispatchQueue.main.async {
                VestaNotice.show(
                    title: L10n.string(.integrityFailedTitle, language: L10n.savedLanguage()),
                    message: L10n.string(.integrityFailedBody, language: L10n.savedLanguage())
                )
            }
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        let credits = LaunchSessionStore.shared.consumeOpenPlaytime()
        if !credits.isEmpty {
            MainActor.assumeIsolated {
                AppLibraryStore.creditPlaytime(credits)
            }
        }
        WineProcessCleanup.terminateLingeringWine()
    }
}
