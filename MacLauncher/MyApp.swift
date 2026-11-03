import AppKit
import SwiftUI

struct MyApp: App {
    @NSApplicationDelegateAdaptor(VestaAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Vesta") {
            ContentView()
                .environmentObject(LanguageManager.shared)
        }
        .defaultSize(width: 920, height: 580)
        .windowResizability(.contentMinSize)
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
