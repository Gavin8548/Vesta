//
//  SupportedGamesPane.swift
//
//  引擎管理里的兼容游戏名单。分类来自内置目录。
//  提示跟着当前选中的 wine64 变，但不把未实测的游戏写成完美运行。
//

import SwiftUI

private struct EngineGameLink: Sendable {
    var id: UUID
    var name: String
    var steamAppID: String
    var platformMac: Bool
}

private enum SupportedFilter: String, CaseIterable, Identifiable {
    case all
    case native
    case tunable
    case blocked

    var id: String { rawValue }

    func key() -> L10nKey {
        switch self {
        case .all: return .filterAll
        case .native: return .tierNative
        case .tunable: return .tierTunable
        case .blocked: return .tierBlocked
        }
    }
}

struct SupportedGamesPane: View {
    var engines: [EngineInstall]
    @Binding var selectedPath: String
    @EnvironmentObject private var language: LanguageManager
    @State private var filter: SupportedFilter = .all
    @State private var query = ""
    @State private var links: [EngineGameLink] = []
    @State private var note = ""
    @State private var explained: CompatibilityRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            engineBanner
            filterBar
            if rows.isEmpty {
                Text(language.text(.supportedEmpty))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { record in
                    gameRow(record)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .background(.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadLinks() }
        .sheet(item: $explained) { record in
            noteSheet(record)
        }
    }

    private var engineBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            if engines.isEmpty {
                Text(language.text(.engineNoteMissing))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(language.text(.engineUse), selection: $selectedPath) {
                    ForEach(engines) { engine in
                        Text(engine.title).tag(engine.path)
                    }
                }
                .labelsHidden()
                Text(engineNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            TextField(language.text(.supportedSearch), text: $query)
                .textFieldStyle(.roundedBorder)
            Picker(language.text(.filterAll), selection: $filter) {
                ForEach(SupportedFilter.allCases) { item in
                    Text(language.text(item.key())).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
        .padding(.horizontal, 20)
    }

    private func gameRow(_ record: CompatibilityRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    tierBadge(record.tier)
                    Text(record.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(statusLine(record.tier))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if record.tier != .blocked {
                Button(applyTitle(record), action: { apply(record) })
                    .disabled(selectedEngine == nil && !(record.tier == .native && link(for: record)?.platformMac == true))
            }
            Button(language.text(.tuningNotes)) {
                explained = record
            }
        }
        .padding(.vertical, 6)
    }

    private func noteSheet(_ record: CompatibilityRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            tierBadge(record.tier)
            Text(record.title)
                .font(.title2.weight(.semibold))
            Text(detail(record))
                .fixedSize(horizontal: false, vertical: true)
            Text(statusLine(record.tier))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(engineNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if record.tier != .blocked {
                    Button(applyTitle(record), action: { apply(record) })
                        .disabled(selectedEngine == nil && !(record.tier == .native && link(for: record)?.platformMac == true))
                }
                Button(language.text(.supportedClose)) {
                    explained = nil
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 440, alignment: .leading)
    }

    private var rows: [CompatibilityRecord] {
        let base: [CompatibilityRecord]
        switch filter {
        case .all:
            base = GameCompatibilityCatalog.records
        case .native:
            base = GameCompatibilityCatalog.records(in: .native)
        case .tunable:
            base = GameCompatibilityCatalog.records(in: .tunable)
        case .blocked:
            base = GameCompatibilityCatalog.records(in: .blocked)
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        return base.filter { record in
            record.title.localizedCaseInsensitiveContains(needle)
                || record.aliases.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    private var selectedEngine: EngineInstall? {
        engines.first { $0.path == selectedPath }
    }

    private var engineNote: String {
        guard let engine = selectedEngine else { return language.text(.engineNoteMissing) }
        switch engine.kind {
        case "crossover":
            return language.text(.engineNoteCrossover)
        case "gptk":
            return language.text(.engineNoteGPTK)
        default:
            return language.text(.engineNoteWine)
        }
    }

    private func statusLine(_ tier: CompatibilityTier) -> String {
        switch tier {
        case .native:
            return language.text(.statusNative)
        case .tunable:
            let kind = selectedEngine?.kind ?? ""
            if kind == "crossover" || kind == "gptk" {
                return language.text(.statusTunableSpecial)
            }
            return language.text(.statusTunableWine)
        case .blocked:
            return language.text(.statusBlocked)
        }
    }

    private func detail(_ record: CompatibilityRecord) -> String {
        if language.currentLanguage == .chinese {
            return record.reason
        }
        switch record.tier {
        case .native: return language.text(.tuningNative)
        case .tunable: return language.text(.tuningTunable)
        case .blocked: return language.text(.tuningBlocked)
        }
    }

    private func applyTitle(_ record: CompatibilityRecord) -> String {
        if record.tier == .native, link(for: record)?.platformMac == true {
            return language.text(.clearEngine)
        }
        return language.text(.applyEngine)
    }

    private func tierBadge(_ tier: CompatibilityTier) -> some View {
        Text(language.text(tierKey(tier)))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tierColor(tier))
            .background(tierColor(tier).opacity(0.16), in: Capsule())
    }

    private func tierKey(_ tier: CompatibilityTier) -> L10nKey {
        switch tier {
        case .native: return .tierNative
        case .tunable: return .tierTunable
        case .blocked: return .tierBlocked
        }
    }

    private func tierColor(_ tier: CompatibilityTier) -> Color {
        switch tier {
        case .native: return .green
        case .tunable: return .orange
        case .blocked: return .red
        }
    }

    private func link(for record: CompatibilityRecord) -> EngineGameLink? {
        if !record.steamAppID.isEmpty, let hit = links.first(where: { $0.steamAppID == record.steamAppID }) {
            return hit
        }
        return links.first { item in
            GameCompatibilityCatalog.match(name: item.name, steamAppID: item.steamAppID)?.title == record.title
        }
    }

    private func apply(_ record: CompatibilityRecord) {
        guard record.tier != .blocked else { return }
        guard let linked = link(for: record) else {
            note = language.text(.applyEngineMissing)
            return
        }
        if record.tier == .native, linked.platformMac {
            EngineDesk.setOverride(nil, for: linked.id)
            note = language.text(.clearEngineDone)
            return
        }
        guard let engine = selectedEngine else {
            note = language.text(.engineNoteMissing)
            return
        }
        EngineDesk.setOverride(engine.path, for: linked.id)
        note = language.text(.applyEngineDone)
    }

    private func loadLinks() {
        guard links.isEmpty else { return }
        var programs = WindowsApp.samples.filter { app in
            !GameRemoval.isBlocked(app.name) && !GameRemoval.isHidden(app.playtimeKey)
        }
        AppLibraryStore.load(into: &programs)
        links = programs.map { app in
            EngineGameLink(
                id: app.id,
                name: app.name,
                steamAppID: app.steamAppID ?? "",
                platformMac: app.platform == .macOS
            )
        }
    }
}
