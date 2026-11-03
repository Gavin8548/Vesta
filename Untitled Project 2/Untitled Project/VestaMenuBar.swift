//
//  VestaMenuBar.swift
//
//  顶栏快捷启动。最近游戏来自 RecentLaunchStore，和主窗口共用同一份记录。
//

import SwiftUI

struct VestaMenuBarLauncher: View {
    @ObservedObject private var recents = RecentLaunchStore.shared
    @EnvironmentObject private var language: LanguageManager
    @State private var running: [UUID] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(.menuRecent))
                .font(.headline)
            if recents.recents.isEmpty {
                Text(language.text(.menuEmpty))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recents.recents) { item in
                    Button(recents.title(for: item, language: language.currentLanguage)) {
                        recents.launch(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !running.isEmpty {
                Divider()
                ForEach(running, id: \.self) { id in
                    Button(language.text(.menuStop)) {
                        AppLauncher.stop(appID: id)
                        refreshRunning()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .onAppear(perform: refreshRunning)
        .onChange(of: recents.recents) { _, _ in
            refreshRunning()
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowsAppDidExit)) { _ in
            refreshRunning()
        }
    }

    private func refreshRunning() {
        running = LaunchSessionStore.shared.runningIDs()
    }
}
