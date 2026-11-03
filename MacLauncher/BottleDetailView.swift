//
//  BottleDetailView.swift
//
//  右侧容器详情：Windows 版本、已装软件，以及「设为默认」。
//

import SwiftUI

struct BottleDetailHost: View {
    @Binding var bottles: [Bottle]
    let selectedID: Bottle.ID?
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        if let index = selectedIndex {
            BottleDetailView(bottle: $bottles[index], onMakeDefault: makeDefault)
        } else {
            PlaceholderPane(
                title: language.text(.bottleMissingTitle),
                systemImage: "cylinder.split.1x2",
                message: language.text(.bottleMissingHint)
            )
        }
    }

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return bottles.firstIndex { $0.id == selectedID }
    }

    private func makeDefault() {
        guard let selectedID else { return }
        for index in bottles.indices {
            bottles[index].isDefault = bottles[index].id == selectedID
        }
    }
}

struct BottleDetailView: View {
    @Binding var bottle: Bottle
    let onMakeDefault: () -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        ScrollView {
            detailStack
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: 20) {
            BottleDetailHeader(bottle: bottle)
            Text(language.text(.bottleIntro))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            BottleProgramSection(names: bottle.programNames)
            BottleGraphicsSection(bottle: $bottle)
            BottleManageBar(bottle: bottle)
            BottleBackupSection(bottleName: bottle.name)
            BottleArchiveSection()
            defaultButton
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var defaultButton: some View {
        Button(action: onMakeDefault) {
            Label(buttonTitle, systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(bottle.isDefault)
    }

    private var buttonTitle: String {
        bottle.isDefault ? language.text(.currentDefault) : language.text(.setDefault)
    }
}

private struct BottleArchiveSection: View {
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        GroupBox(language.text(.archiveExport)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(language.text(.archiveBottleHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VestaArchiveButtons()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }
}

private struct BottleGraphicsSection: View {
    @Binding var bottle: Bottle
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var license = LicenseManager.shared
    @State private var showsPro = false

    var body: some View {
        GroupBox(language.text(.advancedGraphics)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(language.text(.enableDXVKShort), isOn: $bottle.enablesDXVK)
                    .disabled(!license.hasProAccess)
                Toggle(language.text(.metal3), isOn: $bottle.enablesMetal3)
                    .disabled(!license.hasProAccess)
                Toggle("Esync", isOn: $bottle.enablesEsync)
                    .disabled(!license.hasProAccess)
                if !license.hasProAccess {
                    Text(language.text(.proLockedHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(language.text(.enterLicense)) { showsPro = true }
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showsPro) {
            VestaAuthMembershipView()
                .environmentObject(language)
        }
    }
}

private struct BottleDetailHeader: View {
    let bottle: Bottle
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            IconBadge(systemName: "cylinder.split.1x2", tint: .teal, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(bottle.name)
                    .font(.title.weight(.semibold))
                Text(bottle.windowsVersion)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(bottle.wineVersion)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    defaultBadge
                    if bottle.enablesDXVK {
                        InlineBadge(title: "DXVK")
                    }
                    if bottle.enablesMetal3 {
                        InlineBadge(title: "Metal 3")
                    }
                    if bottle.enablesEsync {
                        InlineBadge(title: "Esync")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var defaultBadge: some View {
        if bottle.isDefault {
            InlineBadge(title: language.text(.defaultBottle))
        }
    }
}

private struct BottleManageBar: View {
    let bottle: Bottle
    @State private var message = ""
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: openCDrive) {
                Label(language.text(.openCDrive), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(action: runWine) {
                Label(language.text(.wineConsole), systemImage: "terminal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openCDrive() {
        message = BottleActions.openCDrive(named: bottle.name)
    }

    private func runWine() {
        message = BottleActions.runWineConsole(named: bottle.name, enablesDXVK: bottle.enablesDXVK)
    }
}

private struct BottleProgramSection: View {
    let names: [String]
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        GroupBox(language.text(.installedSoftware)) {
            if names.isEmpty {
                Text(language.text(.emptyBottle))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                programList
            }
        }
    }

    private var programList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Label(SampleCopy.displayName(name, language: language.currentLanguage), systemImage: "app.fill")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
