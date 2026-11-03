import AppKit
import SwiftUI

@main
struct MacLauncherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(.background)
                .preferredColorScheme(.light)
                .onAppear(perform: applyLightWindowAppearance)
        }
        .defaultSize(width: 1180, height: 760)
    }

    private func applyLightWindowAppearance() {
        let appearance = NSAppearance(named: .aqua)
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
}
