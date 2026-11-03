//
//  BottleListView.swift
//
//  容器列表，以及新建容器的表单。
//

import SwiftUI

struct BottleListView: View {
    let bottles: [Bottle]
    @Binding var query: String
    @Binding var selectedID: Bottle.ID?
    let onImport: () -> Void
    let onDropImport: (URL, Bool) -> Void
    let onCreate: () -> Void
    @EnvironmentObject private var language: LanguageManager

    private var visible: [Bottle] {
        bottles.filtered(query: query)
    }

    private var subtitle: String {
        language.format(.bottleCount, visible.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserHeader(
                subtitle: subtitle,
                query: $query,
                searchPrompt: language.text(.searchBottles),
                onImport: onImport,
                onDropImport: onDropImport,
                secondaryTitle: language.text(.newBottle),
                secondarySymbol: "plus",
                onSecondary: onCreate
            )
            Divider()
            listBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(language.text(.bottles))
    }

    @ViewBuilder
    private var listBody: some View {
        if visible.isEmpty {
            emptyState
        } else {
            BottleCardList(bottles: visible, selectedID: $selectedID)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            PlaceholderPane(
                title: language.text(.noBottles),
                systemImage: "cylinder.split.1x2",
                message: language.text(.noBottlesHint),
                buttonTitle: language.text(.newBottle),
                action: onCreate
            )
        } else {
            PlaceholderPane(
                title: language.text(.noBottleMatch),
                systemImage: "magnifyingglass",
                message: language.text(.noBottleMatchHint)
            )
        }
    }
}

private struct BottleCardList: View {
    let bottles: [Bottle]
    @Binding var selectedID: Bottle.ID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(bottles) { bottle in
                    BottleCard(bottle: bottle, isSelected: bottle.id == selectedID) {
                        selectedID = bottle.id
                    }
                }
            }
            .padding(16)
        }
        .onScrollPhaseChange { _, phase in
            LibraryScrollGate.shared.setIdle(phase == .idle)
        }
        .onDisappear {
            LibraryScrollGate.shared.setIdle(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BottleCard: View {
    let bottle: Bottle
    let isSelected: Bool
    let onSelect: () -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        Button(action: onSelect) {
            SelectableCard(isSelected: isSelected) {
                cardBody
            }
        }
        .buttonStyle(.plain)
    }

    private var cardBody: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: "cylinder.split.1x2", tint: .teal, size: 44)
            textBlock
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(bottle.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                defaultBadge
            }
            Text(bottle.windowsVersion)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(softwareLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var defaultBadge: some View {
        if bottle.isDefault {
            InlineBadge(title: language.text(.defaultBadge))
        }
    }

    private var softwareLine: String {
        let count = language.format(.softwareCount, bottle.programNames.count)
        return bottle.enablesDXVK ? "\(count) · DXVK / Metal" : count
    }
}

struct NewBottleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageManager
    @State private var name = ""
    @State private var version = Bottle.versionOptions[0]
    @State private var enablesDXVK = false
    @State private var presetID = GamePresetLibrary.action.id
    @State private var showsPro = false
    @ObservedObject private var license = LicenseManager.shared
    let onCreate: (NewBottleDraft) -> Void

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.text(.newBottle))
                .font(.title2.weight(.semibold))
            Text(language.text(.newBottleHint))
                .foregroundStyle(.secondary)
            TextField(language.text(.bottleNamePrompt), text: $name)
                .textFieldStyle(.roundedBorder)
            versionPicker
            presetPicker
            Toggle(language.text(.enableDXVK), isOn: $enablesDXVK)
                .disabled(!license.hasProAccess)
            Text(license.hasProAccess ? language.text(.dxvkBottleHint) : language.text(.proLockedHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !license.hasProAccess {
                Button(language.text(.enterLicense)) { showsPro = true }
            }
            actions
        }
        .padding(20)
        .frame(width: 420)
        .sheet(isPresented: $showsPro) {
            VestaAuthMembershipView()
                .environmentObject(language)
        }
    }

    private var presetPicker: some View {
        Picker(language.text(.presetSection), selection: $presetID) {
            ForEach(GamePresetLibrary.tagPresets) { preset in
                Text(language.text(GamePresetLibrary.titleKey(for: preset.id))).tag(preset.id)
            }
        }
        .onChange(of: presetID) { _, newID in
            guard let preset = GamePresetLibrary.preset(id: newID) else { return }
            enablesDXVK = preset.dxvkEnabled
        }
    }

    private var versionPicker: some View {
        Picker(language.text(.windowsVersion), selection: $version) {
            ForEach(Bottle.versionOptions, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .pickerStyle(.menu)
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button(language.text(.cancel), role: .cancel) {
                dismiss()
            }
            Button(language.text(.create), action: create)
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func create() {
        let acceleration = license.hasProAccess && enablesDXVK
        let preset = GamePresetLibrary.preset(id: presetID)
        onCreate(NewBottleDraft(
            name: name,
            windowsVersion: version,
            enablesDXVK: acceleration,
            enablesMetal3: preset?.d3dMetalEnabled ?? false,
            presetID: presetID
        ))
        dismiss()
    }
}
