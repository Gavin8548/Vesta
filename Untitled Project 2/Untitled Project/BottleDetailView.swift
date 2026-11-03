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
                Text(language.text(.graphicsBackend))
                    .font(.subheadline.weight(.semibold))
                Picker(language.text(.graphicsBackend), selection: backendBinding) {
                    Text("DXVK").tag(BottleGraphicsBackend.dxvk)
                    Text("DXMT").tag(BottleGraphicsBackend.dxmt)
                    Text("D3DMetal").tag(BottleGraphicsBackend.d3dmetal)
                }
                .pickerStyle(.segmented)
                .disabled(!license.hasProAccess)
                Text(backendNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text(.graphicsSync))
                    .font(.subheadline.weight(.semibold))
                Picker(language.text(.graphicsSync), selection: syncBinding) {
                    Text(language.text(.presetMsync)).tag(BottleSyncMode.msync)
                    Text("ESync").tag(BottleSyncMode.esync)
                    Text(language.text(.syncOff)).tag(BottleSyncMode.off)
                }
                .pickerStyle(.segmented)
                .disabled(!license.hasProAccess)
                Text(language.text(.presetMsyncHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(language.text(.bottleDisableRetina), isOn: retinaBinding)
                Text(language.text(.bottleDisableRetinaHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(language.text(.bottleShaderCache), isOn: cacheBinding)
                Text(language.text(.bottleShaderCacheHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .onAppear {
            BottleTuningStore.load(into: &bottle)
        }
        .sheet(isPresented: $showsPro) {
            VestaAuthMembershipView()
                .environmentObject(language)
        }
    }

    private var backendBinding: Binding<BottleGraphicsBackend> {
        Binding(
            get: { bottle.graphicsBackend },
            set: { newValue in
                bottle.graphicsBackend = newValue
                BottleTuningStore.save(bottle)
            }
        )
    }

    private var syncBinding: Binding<BottleSyncMode> {
        Binding(
            get: { bottle.syncMode },
            set: { newValue in
                bottle.syncMode = newValue
                BottleTuningStore.save(bottle)
            }
        )
    }

    private var retinaBinding: Binding<Bool> {
        Binding(
            get: { bottle.disablesRetina },
            set: { newValue in
                bottle.disablesRetina = newValue
                BottleTuningStore.save(bottle)
            }
        )
    }

    private var cacheBinding: Binding<Bool> {
        Binding(
            get: { bottle.enablesShaderCache },
            set: { newValue in
                bottle.enablesShaderCache = newValue
                BottleTuningStore.save(bottle)
            }
        )
    }

    private var backendNote: String {
        switch bottle.graphicsBackend {
        case .dxvk:
            return language.text(.dxvkBottleHint)
        case .dxmt:
            return language.text(.presetDXMTHint)
        case .d3dmetal:
            return language.text(.presetD3DMetalWine)
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
                    if bottle.enablesDXMT {
                        InlineBadge(title: "DXMT")
                    }
                    if bottle.enablesMetal3 {
                        InlineBadge(title: "D3DMetal")
                    }
                    if bottle.enablesMsync {
                        InlineBadge(title: "MSync")
                    }
                    if bottle.enablesEsync {
                        InlineBadge(title: "ESync")
                    }
                    if bottle.disablesRetina {
                        InlineBadge(title: "96 DPI")
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
