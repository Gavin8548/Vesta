//
//  SidebarView.swift
//
//  左侧只保留游戏库、macOS 专区和设置。
//  Windows 专区和容器管理不在这里出现。
//

import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        List(selection: $selection) {
            Section(language.text(.sidebarMain)) {
                row(.allApps, systemImage: "sparkles")
            }
            Section(language.text(.sidebarCategories)) {
                row(.favorites, systemImage: "star.fill")
                row(.macGames, systemImage: "gamecontroller")
                row(.macTools, systemImage: "wrench.and.screwdriver")
            }
            Section(language.text(.sidebarSettings)) {
                row(.settings, systemImage: "gearshape")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationTitle("")
        .toolbar(removing: .title)
        .toolbarBackground(.background, for: .windowToolbar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VestaHeaderView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
        .background(.background)
        .onAppear(perform: leaveHiddenSections)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            LicenseStatusBadge()
            SidebarHardwareRow()
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(.background)
    }

    private func row(_ destination: SidebarDestination, systemImage: String) -> some View {
        Label(title(for: destination), systemImage: systemImage)
            .tag(destination)
    }

    private func title(for destination: SidebarDestination) -> String {
        destination.localizedTitle(language.currentLanguage)
    }

    /// 侧边栏不再提供 Windows 专区和容器管理，避免选中项停在看不见的栏目上。
    private func leaveHiddenSections() {
        switch selection {
        case .allApps, .macGames, .macTools, .settings, .favorites:
            break
        case .macOS:
            selection = .macGames
        case .windows, .windowsGames, .windowsTools, .bottles:
            selection = .allApps
        }
    }
}

struct VestaHeaderView: View {
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            logo
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Vesta")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    proBadge
                }
                Text("Native macOS Game Hub")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background)
        .contentShape(Rectangle())
        .onHover { hover in
            guard hover != isHovered else { return }
            isHovered = hover
        }
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .shadow(color: .orange.opacity(isHovered ? 0.6 : 0.3), radius: isHovered ? 8 : 4, x: 0, y: 2)
            Image(systemName: "flame.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
    }

    private var proBadge: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.2), Color.red.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundStyle(.orange)
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.4), lineWidth: 0.5)
            )
    }
}

private struct SidebarHardwareRow: View {
    @State private var hardware: MacHardware?
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cpu.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(.hardwareSummary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summaryText)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            guard hardware == nil else { return }
            hardware = await Task.detached(priority: .utility) {
                MacHardware.current
            }.value
        }
    }

    private var summaryText: String {
        guard let hardware else { return "…" }
        let chip = hardware.chip == "Apple 芯片" ? language.text(.appleChip) : hardware.chip
        let memory = SampleCopy.specs(hardware.memory, language: language.currentLanguage)
        return "\(chip) / \(memory)"
    }
}
