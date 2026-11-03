//
//  AppDetailView.swift
//
//  右侧软件详情。绿色「运行 (Run)」会交给 AppLauncher：
//  macOS 程序走 NSWorkspace / Process，Windows 程序用标准 wine64。
//

import AppKit
import SwiftUI

/// 根据选中的 id 取出绑定。单独做成一个很小的视图，避免在根视图里写 if let Binding。
struct AppDetailHost: View {
    @Binding var programs: [WindowsApp]
    @Binding var bottles: [Bottle]
    @Binding var selectedBottleID: Bottle.ID?
    let selectedID: WindowsApp.ID?
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        if let index = selectedIndex {
            AppDetailView(
                program: $programs[index],
                bottles: $bottles,
                selectedBottleID: $selectedBottleID,
                onFavoriteChange: {
                    AppLibraryStore.save(programs)
                },
                onLibraryChange: {
                    AppLibraryStore.save(programs)
                }
            )
        } else {
            PlaceholderPane(
                title: language.text(.selectAppTitle),
                systemImage: "macwindow",
                message: language.text(.selectAppHint)
            )
        }
    }

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return programs.firstIndex { $0.id == selectedID }
    }
}

struct AppDetailView: View {
    @Binding var program: WindowsApp
    @Binding var bottles: [Bottle]
    @Binding var selectedBottleID: Bottle.ID?
    var onFavoriteChange: () -> Void = {}
    var onLibraryChange: () -> Void = {}
    @EnvironmentObject private var language: LanguageManager
    @State private var detailTab = AppDetailTab.overview

    /// 用当前绑定的 bottles，按名称不区分大小写查找，不读静态样本。
    private var matchedBottle: Bottle? {
        matchingBottle(in: bottles, for: program)
    }

    var body: some View {
        VStack(spacing: 0) {
            HeroBanner(program: program, onToggleFavorite: toggleFavorite)
            ScrollView {
                lowerDetails
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: clearStaleMissingError)
        .onChange(of: bottles.map(\.name)) { _, _ in
            clearStaleMissingError()
        }
        .onChange(of: program.bottleName) { _, _ in
            clearStaleMissingError()
        }
    }

    private func applyPreset(_ preset: GamePreset) {
        GamePresetStore.apply(preset, to: program, host: HostEngine.resolved())
        guard let name = program.bottle else { return }
        guard let index = bottles.firstIndex(where: { bottle in
            bottle.name.compare(name, options: .caseInsensitive) == .orderedSame
                || bottle.id.compare(name, options: .caseInsensitive) == .orderedSame
        }) else { return }
        let advanced = LicenseGate.shared.allowsAdvanced()
        if preset.dxvkEnabled && advanced {
            bottles[index].enablesDXVK = true
        }
        if preset.d3dMetalEnabled {
            bottles[index].enablesMetal3 = true
        }
        if preset.esyncEnabled && advanced {
            bottles[index].enablesEsync = true
        }
    }

    private func toggleFavorite() {
        program.isFavorite.toggle()
        onFavoriteChange()
    }

    private func clearStaleMissingError() {
        guard matchedBottle != nil else { return }
        if program.launchMessage.contains("未找到容器") || program.launchMessage.contains("was not found") {
            program.launchMessage = ""
        }
    }

    /// 海报单独占顶部，这里只放发行商和简介，不再向上探进海报。
    private var lowerDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            if program.supportsMods {
                detailTabPicker
            }
            detailBody
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var detailTabPicker: some View {
        Picker(language.text(.detailOverview), selection: $detailTab) {
            Text(language.text(.detailOverview)).tag(AppDetailTab.overview)
            Text(language.text(.detailMods)).tag(AppDetailTab.mods)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var detailBody: some View {
        if program.supportsMods && detailTab == .mods {
            ModLibrarySection(program: program)
        } else {
            overviewDetails
        }
    }

    private var overviewDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorefrontFacts(program: program)
            OverviewCard(program: program)
            if program.platform == .windows {
                HostEnginePicker()
                GamePresetCard(program: program, host: HostEngine.resolved(), onApply: applyPreset)
                SaveSyncCard(bottleName: program.bottle ?? "")
                PerformanceOverlaySwitch()
            }
            AppActionBar(program: $program, bottles: $bottles, onLibraryChange: onLibraryChange)
            AppInfoSection(program: program)
            MacRequirementCards(
                pcSpecs: SampleCopy.specs(program.pcMinSpecs, language: language.currentLanguage),
                macSpecs: SampleCopy.specs(program.macMinSpecs, language: language.currentLanguage),
                notice: program.localizedNotice(language.currentLanguage)
            )
            MatchedBottleSection(
                program: $program,
                bottles: $bottles,
                selectedBottleID: $selectedBottleID
            )
        }
    }
}

private enum AppDetailTab: Hashable {
    case overview
    case mods
}

private struct OverviewCard: View {
    let program: WindowsApp
    @EnvironmentObject private var language: LanguageManager

    private var bodyText: String {
        program.localizedDescription(language.currentLanguage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        if program.kind == .game || program.category == "游戏" {
            return language.text(.overviewGame)
        }
        return language.text(.overviewApp)
    }

    var body: some View {
        if !bodyText.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(bodyText)
                    .font(.body)
                    .lineSpacing(7)
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vestaGlass(cornerRadius: 18)
        }
    }
}

/// 选择本机已经安装的标准 Wine 或 CrossOver。运行游戏仍调用 wine64。
private struct HostEnginePicker: View {
    @EnvironmentObject private var language: LanguageManager
    @State private var engine: HostEngine = HostEngine.resolved() ?? .wine

    private var choices: [HostEngine] { HostEngine.installed() }

    var body: some View {
        if !choices.isEmpty {
            picker
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(language.text(.hostEngine))
                    .font(.headline)
                Spacer(minLength: 12)
                Picker(language.text(.hostEngine), selection: $engine) {
                    ForEach(choices) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .labelsHidden()
            }
            Text(language.text(.hostEngineHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear(perform: load)
        .onChange(of: engine) { _, newValue in
            guard choices.contains(newValue) else { return }
            HostEngine.remember(newValue)
        }
    }

    private func load() {
        guard let resolved = HostEngine.resolved(), engine != resolved else { return }
        engine = resolved
    }
}

/// 详情页上的 DXVK / Metal / D3DMetal 切换。只影响这款 Windows 游戏的启动参数。
private struct StorefrontFacts: View {
    let program: WindowsApp
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            fact(language.text(.publisher), program.localizedPublisher(language.currentLanguage), "building.2")
            fact(language.text(.version), program.version, "number")
            regionFact
            statusFact
        }
    }

    @ViewBuilder
    private var regionFact: some View {
        let title = program.regionTitle(language.currentLanguage)
        if !title.isEmpty {
            fact(language.text(.regionLabel), title, "globe")
        }
    }

    private var statusFact: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(language.text(.installStatus), systemImage: "dot.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            StatusCapsule(isRunning: program.isRunning, isLaunching: program.isLaunching)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vestaGlass(cornerRadius: 14)
    }

    private func fact(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vestaGlass(cornerRadius: 14)
    }
}

private struct AppInfoSection: View {
    let program: WindowsApp
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text(.appInfo))
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                DetailRow(title: language.text(.version), value: program.version)
                DetailRow(title: language.text(.publisher), value: program.localizedPublisher(language.currentLanguage))
                regionRow
                DetailRow(title: language.text(.kind), value: program.localizedKind(language.currentLanguage))
                DetailRow(title: language.text(.platform), value: platformTitle)
                DetailRow(
                    title: language.text(.category),
                    value: program.localizedCategory(language.currentLanguage).isEmpty
                        ? program.localizedKind(language.currentLanguage)
                        : program.localizedCategory(language.currentLanguage)
                )
                DetailRow(
                    title: language.text(.installStatus),
                    value: availabilityTitle,
                    valueColor: program.availabilityColor
                )
                DetailRow(title: language.text(.container), value: bottleLabel)
                DetailRow(title: language.text(.lastRun), value: program.localizedLastRun(language.currentLanguage))
                InstallPathRow(path: program.installPath)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vestaGlass()
    }

    @ViewBuilder
    private var regionRow: some View {
        let title = program.regionTitle(language.currentLanguage)
        if !title.isEmpty {
            DetailRow(title: language.text(.regionLabel), value: title)
        }
    }

    private var platformTitle: String {
        program.platform == .macOS ? "macOS" : "Windows"
    }

    private var bottleLabel: String {
        guard let name = program.bottle else { return language.text(.noContainer) }
        if language.currentLanguage == .english && name == "未分配容器" {
            return language.text(.unassignedBottle)
        }
        return name
    }

    private var availabilityTitle: String {
        switch program.libraryStatus {
        case .installed: return language.text(.installed)
        case .inLibrary: return language.text(.inLibrary)
        case .absent: return language.text(.notInstalled)
        }
    }
}

private struct MacRequirementCards: View {
    let pcSpecs: String
    let macSpecs: String
    let notice: String?
    @EnvironmentObject private var language: LanguageManager

    private var pcText: String {
        pcSpecs.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var macText: String {
        macSpecs.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var noticeBody: String {
        notice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var isVisible: Bool {
        !pcText.isEmpty || !macText.isEmpty || !noticeBody.isEmpty
    }

    var body: some View {
        if isVisible {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text(.hardwareTitle))
                .font(.headline)
            HStack(alignment: .top, spacing: 12) {
                specColumn(
                    title: language.text(.pcSpecs),
                    text: pcText.isEmpty ? language.text(.notProvided) : pcText,
                    tint: .secondary
                )
                specColumn(
                    title: language.text(.macSpecs),
                    text: macText.isEmpty ? language.text(.notProvided) : macText,
                    tint: .blue
                )
            }
            if !noticeBody.isEmpty {
                noticeBlock
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vestaGlass()
    }

    private func specColumn(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .vestaGlass(cornerRadius: 12)
    }

    private var noticeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text(.tuningTips))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(noticeBody)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .vestaGlass(cornerRadius: 12)
    }
}

private struct InstallPathRow: View {
    let path: String
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.text(.installPath))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MatchedBottleSection: View {
    @Binding var program: WindowsApp
    @Binding var bottles: [Bottle]
    @Binding var selectedBottleID: Bottle.ID?
    @State private var isBinding = false
    @EnvironmentObject private var language: LanguageManager

    /// 只比较容器名称，忽略大小写。数据来自传入的 bottles 绑定。
    private var matchedBottle: Bottle? {
        matchingBottle(in: bottles, for: program)
    }

    var body: some View {
        GroupBox(language.text(.bottleSection)) {
            if program.platform == .macOS && program.bottle == nil {
                Text(language.text(.macNeedsNoBottle))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let matchedBottle {
                matchedContent(matchedBottle)
            } else {
                missingContent
            }
        }
        .sheet(isPresented: $isBinding) {
            BindBottleSheet(bottles: bottles) { bottle in
                bind(bottle)
            }
        }
    }

    private func matchedContent(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(title: language.text(.bottleName), value: bottle.name)
            DetailRow(title: language.text(.bottleIdentifier), value: bottle.id)
            DetailRow(title: language.text(.bottleSystem), value: bottle.windowsVersion)
            DetailRow(title: "Wine", value: bottle.wineVersion)
            DetailRow(title: "DXVK", value: bottle.enablesDXVK ? language.text(.dxvkOn) : language.text(.dxvkOff))
        }
        .padding(.top, 4)
    }

    private var missingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.format(.missingBottle, program.bottle ?? language.text(.unnamed)))
                .foregroundStyle(.secondary)
            Button(language.text(.createBottle), action: createBottle)
                .buttonStyle(.borderedProminent)
            Button(language.text(.bindBottle)) {
                isBinding = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func createBottle() {
        let name = program.bottle ?? "Gaming"
        let bottle = Bottle(
            id: name,
            name: name,
            windowsVersion: Bottle.versionOptions.first ?? "Windows 11 64-bit",
            wineVersion: "Wine 9.0",
            programNames: [program.name],
            isDefault: bottles.isEmpty,
            enablesDXVK: program.kind == .game
        )
        bottles.append(bottle)
        program.bottleName = bottle.name
        selectedBottleID = bottle.id
        BottleActions.prepareLocalPrefix(named: bottle.name)
    }

    private func bind(_ bottle: Bottle) {
        program.bottleName = bottle.name
        selectedBottleID = bottle.id
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        if !bottles[index].programNames.contains(program.name) {
            bottles[index].programNames.append(program.name)
        }
    }
}

private struct BindBottleSheet: View {
    let bottles: [Bottle]
    let onSelect: (Bottle) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text(.bindBottle))
                .font(.title2.weight(.semibold))
            if bottles.isEmpty {
                Text(language.text(.noBottlesHere))
                    .foregroundStyle(.secondary)
            } else {
                List(bottles) { bottle in
                    Button {
                        onSelect(bottle)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bottle.name)
                            Text("\(bottle.windowsVersion) · \(bottle.wineVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button(language.text(.cancel), role: .cancel) { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 380, height: 360)
    }
}

private struct StorageSpaceCard: View {
    let requiredGB: Double
    let installPath: String
    @EnvironmentObject private var language: LanguageManager
    @State private var snapshot = StorageSnapshot(totalStorageGB: 0, freeStorageGB: 0)

    var body: some View {
        cardContent
            .task(id: installPath) {
                await monitorDisk()
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        if requiredGB > 0, snapshot.totalStorageGB > 0 {
            card(snapshot)
        }
    }

    /// 磁盘容量不在 body 里读取。后台服务开启时，至少隔 30 秒再测一次。
    private func monitorDisk() async {
            guard LaunchSafety.backgroundServicesEnabled else { return }
            let path = installPath
            let next = await Task.detached(priority: .utility) {
                StorageMonitor.measure(forPath: path)
            }.value
            if Task.isCancelled { return }
            snapshot = next
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                let latest = await Task.detached(priority: .utility) {
                    StorageMonitor.measure(forPath: path)
                }.value
                if Task.isCancelled { return }
                if StorageMonitor.gbText(latest.freeStorageGB) != StorageMonitor.gbText(snapshot.freeStorageGB)
                    || StorageMonitor.gbText(latest.totalStorageGB) != StorageMonitor.gbText(snapshot.totalStorageGB) {
                    snapshot = latest
                }
            }
        }

    private func card(_ snapshot: StorageSnapshot) -> some View {
        let enough = snapshot.freeStorageGB >= requiredGB
        let scale = max(snapshot.freeStorageGB, requiredGB, 1)
        let freeText = StorageMonitor.gbText(snapshot.freeStorageGB)
        let needText = StorageMonitor.gbText(requiredGB)
        let totalText = StorageMonitor.gbText(snapshot.totalStorageGB)
        return VStack(alignment: .leading, spacing: 8) {
            Text(enough ? "✅ " + language.text(.diskSufficient) : "⚠️ " + language.text(.diskInsufficient))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enough ? Color.green : Color.red)
            Text(message(enough: enough, freeText: freeText, needText: needText))
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            storageBar(snapshot: snapshot, enough: enough, scale: scale)
            HStack {
                Text(language.format(.diskFree, freeText))
                Spacer(minLength: 8)
                Text(language.format(.diskRequired, needText))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(language.format(.diskTotal, totalText))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((enough ? Color.green : Color.red).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func message(enough: Bool, freeText: String, needText: String) -> String {
        if enough {
            return language.format(.diskEnoughBody, freeText, needText)
        }
        return language.format(.diskShortBody, freeText, needText)
    }

    private func storageBar(snapshot: StorageSnapshot, enough: Bool, scale: Double) -> some View {
        let fraction = CGFloat(min(max(snapshot.freeStorageGB / scale, 0), 1))
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.08))
            Capsule()
                .fill(enough ? Color.green : Color.red)
                .scaleEffect(x: max(fraction, 0.02), y: 1, anchor: .leading)
        }
        .frame(height: 14)
    }
}

private struct AppActionBar: View {
    @Binding var program: WindowsApp
    @Binding var bottles: [Bottle]
    var onLibraryChange: () -> Void = {}
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var engineInstaller = WineEngineInstaller.shared
    @State private var showsMissingApp = false
    @State private var showsInstallGuide = false
    @State private var showsRebuildPrompt = false
    @State private var rebuildBottleName = ""
    @State private var detectionRevision = 0
    @State private var pendingLaunch: LaunchRequest?
    @State private var showsCloudRestore = false
    @State private var showsMacAppChoice = false

    private var matchedBottle: Bottle? {
        matchingBottle(in: bottles, for: program)
    }

    private var activeEngine: TranslationEngine {
        TranslationEngine.current(for: program, bottle: matchedBottle)
    }

    var body: some View {
        controls
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusLine
                .id(detectionRevision)
            Text(program.playtimeTitle(language: language.currentLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
            engineDownloadStatus
            StorageSpaceCard(requiredGB: program.requiredStorageGB, installPath: program.installPath)
            if program.supportsLaunchChoice {
                LaunchModePicker(program: $program)
            }
            HStack(spacing: 12) {
                if program.steamAppID != nil {
                    Button(language.text(.refreshFiles), action: refreshLocalDetection)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                OfficialDownloadButton(
                    urlString: program.downloadURL,
                    readyTitle: program.regionDownloadTitle(language.currentLanguage),
                    guideMessage: program.regionDownloadGuide(language.currentLanguage)
                )
                Spacer(minLength: 0)
                stopButton
                primaryButton
            }
        }
        .alert(language.text(.needInstall), isPresented: $showsInstallGuide) {
            Button(language.text(.wakeSteam), action: wakeSteamDownload)
            Button(language.text(.cancel), role: .cancel) {}
        } message: {
            Text(language.format(.installGuide, program.localizedName(language.currentLanguage)))
        }
        .alert(language.text(.appNotFound), isPresented: $showsMissingApp) {
            Button(language.text(.goDownload), action: openDownloadPage)
            Button(language.text(.cancel), role: .cancel) {}
        } message: {
            Text(language.text(.installInContainerFirst))
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowsAppDidExit)) { note in
            presentExitFailure(note)
        }
        .alert(language.text(.containerLostTitle), isPresented: $showsRebuildPrompt) {
            Button(language.text(.rebuildContainer), action: rebuildMissingContainer)
            Button(language.text(.cancel), role: .cancel) {}
        } message: {
            Text(language.format(.containerLostMessage, rebuildBottleName))
        }
        .alert(language.text(.bindLocalApp), isPresented: $showsMacAppChoice) {
            Button(language.text(.bindLocalApp), action: chooseMacApp)
            if program.downloadURL != nil {
                Button(language.text(.downloadSetup), action: openDownloadPage)
            }
            Button(language.text(.cancel), role: .cancel) {}
        } message: {
            Text(language.text(.bindLocalAppHint))
        }
        .alert(language.text(.saveSyncSection), isPresented: $showsCloudRestore) {
            Button(language.text(.saveSyncRestoreBeforeLaunch), action: restoreCloudThenLaunch)
            Button(language.text(.saveSyncSkip), action: launchPending)
        } message: {
            Text(language.text(.saveSyncNewerCloud))
        }
    }

    @ViewBuilder
    private var stopButton: some View {
        if program.isRunning {
            Button(language.text(.stop), action: stop)
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if program.platform == .macOS {
            nativeStatus
        } else if let bottle = matchedBottle {
            windowsStatus(bottle)
        } else {
            Text(language.format(.missingBottle, program.bottle ?? language.text(.unnamed)))
                .font(.callout)
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var nativeStatus: some View {
        HStack(spacing: 8) {
            if program.isLaunching {
                ProgressView()
                    .controlSize(.small)
            }
            Text(statusTitle)
                .foregroundStyle(statusColor)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(language.text(.nativeMac))
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(availabilityTitle)
                .foregroundStyle(program.availabilityColor)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func windowsStatus(_ bottle: Bottle) -> some View {
        HStack(spacing: 8) {
            if program.isLaunching {
                ProgressView()
                    .controlSize(.small)
            }
            Text(statusTitle)
                .foregroundStyle(statusColor)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(bottle.name)
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(bottle.enablesDXVK ? "DXVK / Metal" : bottle.windowsVersion)
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(availabilityTitle)
                .foregroundStyle(program.availabilityColor)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    @ViewBuilder
    private var engineDownloadStatus: some View {
        if engineInstaller.isDownloading {
            VStack(alignment: .leading, spacing: 6) {
                Text(engineInstaller.progressText(language))
                    .font(.callout)
                ProgressView(value: Double(engineInstaller.percent), total: 100)
                    .progressViewStyle(.linear)
            }
        }
    }

    private var statusTitle: String {
        if engineInstaller.isDownloading { return engineInstaller.progressText(language) }
        if program.isLaunching || program.isRunning { return language.text(.running) }
        let message = program.launchMessage
        if !message.isEmpty,
           message != language.text(.ready),
           message != language.text(.stopped),
           message != language.text(.running) {
            return message
        }
        return language.text(.ready)
    }

    private var availabilityTitle: String {
        switch program.libraryStatus {
        case .installed: return language.text(.installed)
        case .inLibrary: return language.text(.inLibrary)
        case .absent: return language.text(.notInstalled)
        }
    }

    private var statusColor: Color {
        if program.isLaunching { return .orange }
        if program.isRunning || program.isInstalled { return .green }
        if program.libraryStatus == .inLibrary { return .orange }
        return .secondary
    }

    private var steamID: String? {
        let id = program.steamAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { return nil }
        return id
    }

    private var isAppStoreLink: Bool {
        let raw = program.downloadURL?.lowercased() ?? ""
        return raw.contains("apps.apple.com") || raw.hasPrefix("macappstore:")
    }

    @ViewBuilder
    private var primaryButton: some View {
        if program.supportsLaunchChoice && program.launchMode == .container {
            StoreActionButton(
                title: runButtonTitle,
                systemImage: "play.fill",
                tint: .green,
                isBusy: isRunBusy,
                action: launch
            )
            .keyboardShortcut("r", modifiers: .command)
        } else {
            steamOrLocalButton
        }
    }

    @ViewBuilder
    private var steamOrLocalButton: some View {
        switch program.libraryStatus {
        case .installed where steamID != nil:
            StoreActionButton(
                title: runButtonTitle,
                systemImage: "play.fill",
                tint: .green,
                isBusy: isRunBusy,
                action: playViaSteam
            )
            .keyboardShortcut("r", modifiers: .command)
        case .inLibrary:
            StoreActionButton(
                title: language.text(.installViaSteam),
                systemImage: "arrow.down.circle.fill",
                tint: .blue,
                isBusy: program.isLaunching,
                action: installViaSteam
            )
        case .absent where steamID != nil:
            StoreActionButton(
                title: language.text(.buySteam),
                systemImage: "cart.fill",
                tint: .blue,
                isBusy: false,
                action: openSteamStore
            )
        case .installed, .absent:
            if program.isInstalled || program.downloadURL == nil || program.isRunning || program.isLaunching {
                RunButton(isBusy: isRunBusy, action: launch)
            } else if isAppStoreLink {
                StoreActionButton(
                    title: language.text(.appStore),
                    systemImage: "bag.fill",
                    tint: .blue,
                    isBusy: false,
                    action: openDownloadPage
                )
            } else if program.platform == .macOS && !program.isInstalled {
                StoreActionButton(
                    title: language.text(.downloadSetup),
                    systemImage: "arrow.down.circle",
                    tint: .blue,
                    isBusy: false,
                    action: { showsMacAppChoice = true }
                )
            } else if program.downloadURL != nil {
                StoreActionButton(
                    title: language.text(.downloadSetup),
                    systemImage: "arrow.down.circle",
                    tint: .blue,
                    isBusy: false,
                    action: openDownloadPage
                )
            }
        }
    }

    /// 已安装的 Steam 游戏交给官方客户端启动，由它做正版校验和云存档。
    private func playViaSteam() {
        openSteam(command: "run")
    }

    /// 已在库但还没下载时，只唤醒 Steam 的安装流程。
    private func installViaSteam() {
        openSteam(command: "install")
    }

    private func openSteam(command: String) {
        guard !isRunBusy, let id = steamID else { return }
        let link = "steam://\(command)/\(id)"
        if program.platform == .windows, let steamExe = SteamLibrary.bottleSteamExecutable(bottleName: program.bottle) {
            let tuning = GamePresetStore.launchTuning(for: program)
            let request = LaunchRequest(
                appID: program.id,
                name: program.name,
                installPath: steamExe,
                bottleName: matchedBottle?.name ?? program.bottle ?? "",
                enablesDXVK: activeEngine.enablesDXVK,
                enablesMetal3: activeEngine.enablesMetal3,
                enablesEsync: resolvedEsync(tuning.esync),
                bottleIsKnown: matchedBottle != nil,
                isMacApp: false,
                extraArguments: [link],
                successMessage: language.text(.steamBottleHandOff),
                usesVirtualDesktop: GamePresetStore.usesVirtualDesktop(for: program),
                playtimeKey: program.playtimeKey,
                enablesMetalFX: tuning.metalFX,
                enablesFsync: tuning.fsync
            )
            prepareLaunch(request)
            return
        }
        guard let url = URL(string: link), NSWorkspace.shared.open(url) else {
            if program.isInstalled {
                launch()
                return
            }
            program.launchMessage = language.text(.steamClientMissing)
            openSteamStore()
            return
        }
        program.launchMessage = command == "run" ? language.text(.steamHandOff) : language.text(.steamInstallHandOff)
    }

    private func openSteamStore() {
        guard let id = steamID, let url = SteamLibrary.storeURL(appID: id) else {
            openDownloadPage()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 容器模式：已安装就直接拉起 exe；未安装则引导到容器里的官方 Steam 下载。
    private var isRunBusy: Bool {
        program.isLaunching || program.isRunning
    }

    private var runButtonTitle: String {
        isRunBusy ? language.text(.running) : language.text(.launchGame)
    }

    private func launch() {
        guard !isRunBusy else { return }
        if program.platform == .macOS {
            launchMacApp()
            return
        }
        if program.supportsLaunchChoice && program.launchMode == .container {
            beginContainerExecutable()
            return
        }
        if let source = ImportedFileAccess.prepare(
            bookmark: program.importBookmark,
            fallback: program.installPath,
            id: program.id
        ) {
            program.installPath = source
        }
        beginContainerExecutable()
    }

    private func beginContainerExecutable() {
        let bottleName = matchedBottle?.name ?? program.bottle ?? ""
        let tuning = GamePresetStore.launchTuning(for: program)
        let request = LaunchRequest(
            appID: program.id,
            name: program.name,
            installPath: program.installPath,
            bottleName: bottleName,
            enablesDXVK: activeEngine.enablesDXVK,
            enablesMetal3: activeEngine.enablesMetal3,
            enablesEsync: resolvedEsync(tuning.esync),
            bottleIsKnown: matchedBottle != nil,
            isMacApp: false,
            successMessage: language.text(.directLaunch),
            directExecutable: true,
            usesVirtualDesktop: GamePresetStore.usesVirtualDesktop(for: program),
            playtimeKey: program.playtimeKey,
            enablesMetalFX: tuning.metalFX,
            enablesFsync: tuning.fsync
        )
        prepareLaunch(request)
    }

    private func resolvedEsync(_ presetEsync: Bool) -> Bool {
        if GamePresetStore.saved(for: program) != nil {
            return presetEsync
        }
        return presetEsync || (matchedBottle?.enablesEsync ?? false)
    }

    private func applySuggestedPresetIfNeeded() {
        guard program.platform == .windows else { return }
        guard GamePresetStore.saved(for: program) == nil else { return }
        let preset = GameRecipeManager.preset(
            name: program.name,
            steamAppID: program.steamAppID,
            tags: program.displayTags,
            platform: program.platform
        )
        GamePresetStore.apply(preset, to: program, host: HostEngine.resolved())
    }

    private func wakeSteamDownload() {
        applySuggestedPresetIfNeeded()
        openSteam(command: "install")
    }

    private func refreshLocalDetection() {
        SteamLibrary.invalidate()
        AppLauncher.invalidateInstallCache()
        detectionRevision += 1
        program.launchMessage = language.text(.filesRefreshed)
    }

    /// 路径存在就用 NSWorkspace 打开 .app；不存在则打开 App Store 或官网。
    private func launchMacApp() {
        let expanded = (program.installPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            if program.downloadURL != nil {
                openDownloadPage()
            } else {
                showsMissingApp = true
            }
            return
        }
        let request = LaunchRequest(
            appID: program.id,
            name: program.name,
            installPath: expanded,
            bottleName: "",
            enablesDXVK: false,
            enablesMetal3: false,
            enablesEsync: false,
            bottleIsKnown: false,
            isMacApp: true
        )
        begin(request)
    }

    private func presentExitFailure(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? UUID, id == program.id else { return }
        guard let status = note.userInfo?["status"] as? Int, status != 0 else { return }
        if program.launchMessage == language.text(.stopped) {
            return
        }
        let log = note.userInfo?["log"] as? String ?? ""
        let summary = AppLauncher.exitSummary(status: status, log: log)
        program.isRunning = false
        program.isLaunching = false
        program.launchMessage = VestaUserAlert.explain(summary)
        LaunchSessionStore.shared.endLaunchClaim(id)
        VestaUserAlert.present(summary)
    }

    private func prepareLaunch(_ request: LaunchRequest) {
        let bottle = request.bottleName
        Task {
            let newer = await Task.detached(priority: .utility) {
                SaveSyncManager.cloudIsNewer(bottleName: bottle)
            }.value
            if newer {
                pendingLaunch = request
                showsCloudRestore = true
            } else {
                begin(request)
            }
        }
    }

    private func restoreCloudThenLaunch() {
        guard let request = pendingLaunch else { return }
        pendingLaunch = nil
        let bottle = request.bottleName
        Task {
            let message = await Task.detached(priority: .utility) {
                SaveSyncManager.restoreNewestCloud(bottleName: bottle)
            }.value
            program.launchMessage = message
            begin(request)
        }
    }

    private func launchPending() {
        guard let request = pendingLaunch else { return }
        pendingLaunch = nil
        begin(request)
    }

    private func begin(_ request: LaunchRequest) {
        guard LaunchSessionStore.shared.claimLaunch(request.appID) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            program.isLaunching = true
            program.launchMessage = language.text(.running)
        }
        Task {
            let result = await AppLauncher.launch(request)
            let wineAlive = LaunchSessionStore.shared.trackedIsRunning(request.appID) == true
            let running = request.isMacApp ? result.succeeded : (result.succeeded && wineAlive)
            if !running || request.isMacApp {
                LaunchSessionStore.shared.endLaunchClaim(request.appID)
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                program.isLaunching = false
                program.isRunning = running
                if running {
                    program.launchMessage = language.text(.running)
                } else if !result.message.isEmpty {
                    program.launchMessage = VestaUserAlert.explain(result.message)
                    VestaUserAlert.present(result.message)
                } else {
                    program.launchMessage = language.text(.ready)
                }
                if running {
                    program.lastRunText = Self.formattedNow()
                    if LaunchSafety.backgroundServicesEnabled {
                        RecentLaunchStore.shared.remember(request)
                    }
                } else if result.needsRebuild {
                    rebuildBottleName = request.bottleName.isEmpty ? "Bottle" : request.bottleName
                    showsRebuildPrompt = true
                }
            }
        }
    }

    private func rebuildMissingContainer() {
        BottleActions.rebuildContainer(named: rebuildBottleName)
        program.launchMessage = language.text(.containerRebuilt)
    }

    private func chooseMacApp() {
        guard let url = MacAppPicker.choose() else { return }
        guard url.pathExtension.lowercased() == "app" else {
            VestaNotice.show(title: language.text(.bindLocalApp), message: language.text(.bindLocalAppInvalid))
            return
        }
        program.platform = .macOS
        program.installPath = url.path
        program.absolutePath = url.path
        program.importBookmark = ImportedFileAccess.bookmark(for: url)
        AppLauncher.invalidateInstallCache()
        onLibraryChange()
    }

    private func openDownloadPage() {
        applySuggestedPresetIfNeeded()
        guard let raw = program.downloadURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func stop() {
        LaunchSessionStore.shared.endLaunchClaim(program.id)
        AppLauncher.stop(appID: program.id)
        withAnimation(.easeInOut(duration: 0.2)) {
            program.isRunning = false
            program.isLaunching = false
            program.launchMessage = language.text(.stopped)
        }
    }

    private static func formattedNow() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return "今天 " + formatter.string(from: Date())
    }
}

/// 在当前瓶子数组里按名称查找，忽略大小写。
    private func matchingBottle(in bottles: [Bottle], for app: WindowsApp) -> Bottle? {
        guard let key = app.bottle?.lowercased(), !key.isEmpty else { return nil }
        return bottles.first(where: { $0.name.lowercased() == key })
    }

private struct LaunchModePicker: View {
    @Binding var program: WindowsApp
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(.launchMethod))
                .font(.subheadline.weight(.semibold))
            Picker(language.text(.launchMethod), selection: $program.launchMode) {
                ForEach(LaunchMode.allCases, id: \.self) { mode in
                    Text(title(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(hint(for: program.launchMode))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear(perform: restoreChoice)
        .onChange(of: program.launchMode) { _, mode in
            LaunchMode.remember(mode, for: program)
        }
    }

    private func title(for mode: LaunchMode) -> String {
        switch mode {
        case .container:
            return "🖥️ " + language.text(.localContainer)
        case .steam:
            return "🪟 " + language.text(.steamLinkage)
        }
    }

    private func hint(for mode: LaunchMode) -> String {
        switch mode {
        case .container: return language.text(.containerHint)
        case .steam: return language.text(.steamHint)
        }
    }

    private func restoreChoice() {
        guard let saved = LaunchMode.remembered(for: program) else { return }
        if program.launchMode != saved {
            program.launchMode = saved
        }
    }
}

private struct StoreActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.headline)
            .frame(minWidth: 168)
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.45 : 1)
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
        .fixedSize()
    }
}

private struct RunButton: View {
    let isBusy: Bool
    let action: () -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isBusy ? "hourglass" : "play.fill")
                Text(isBusy ? language.text(.running) : language.text(.launchGame))
            }
            .font(.headline)
            .frame(minWidth: 148)
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.45 : 1)
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .keyboardShortcut("r", modifiers: .command)
        .help(language.text(.runHelp))
    }
}
