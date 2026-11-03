//
//  AppListView.swift
//
//  中间栏的软件列表：导入按钮、搜索框，以及可点选的软件卡片。
//

import SwiftUI

struct AppListView: View {
    @Binding var programs: [WindowsApp]
    let onlyRunning: Bool
    let platform: AppPlatform?
    let catalog: AppCatalog?
    let favoritesOnly: Bool
    let listTitle: String
    @Binding var query: String
    @Binding var category: LibraryCategory
    @Binding var selectedID: WindowsApp.ID?
    let onImport: () -> Void
    let onDropImport: (URL, Bool) -> Void
    let onShowAllApps: () -> Void
    @State private var isScanning = false
    @EnvironmentObject private var language: LanguageManager

    private var visible: [WindowsApp] {
        programs.filtered(query: query, onlyRunning: onlyRunning, category: category, platform: platform, catalog: catalog, favoritesOnly: favoritesOnly)
    }

    private var navigationTitle: String {
        listTitle
    }

    private var subtitle: String {
        if onlyRunning {
            return language.format(.runningCount, visible.count)
        }
        return language.format(.appCount, visible.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserHeader(
                subtitle: subtitle,
                query: $query,
                searchPrompt: language.text(.searchApps),
                onImport: onImport,
                onDropImport: onDropImport
            )
            LibraryFilterBar(category: $category, isScanning: isScanning, onScan: scan)
            Divider()
            listBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(navigationTitle)
        .onChange(of: category) { _, _ in
            keepSelectionVisible()
        }
        .onChange(of: programs.map(\.isFavorite)) { _, _ in
            keepSelectionVisible()
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if visible.isEmpty {
            emptyState
        } else {
            AppCardGrid(apps: visible, selectedID: $selectedID, onToggleFavorite: toggleFavorite, onBindMacApp: bindMacApp)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if hasQuery {
            noSearchResult
        } else if favoritesOnly && category == .all {
            favoritesEmpty
        } else if catalog != nil || (category != .all && !onlyRunning) {
            categoryEmpty
        } else if onlyRunning {
            nothingRunning
        } else {
            libraryEmpty
        }
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var noSearchResult: some View {
        PlaceholderPane(
            title: language.text(.noMatch),
            systemImage: "magnifyingglass",
            message: language.text(.noMatchHint)
        )
    }

    private var favoritesEmpty: some View {
        PlaceholderPane(
            title: language.text(.favoritesEmpty),
            systemImage: "star",
            message: language.text(.favoritesEmptyHint)
        )
    }

    private func toggleFavorite(_ id: WindowsApp.ID) {
        guard let index = programs.firstIndex(where: { $0.id == id }) else { return }
        programs[index].isFavorite.toggle()
        AppLibraryStore.save(programs)
    }

    private func bindMacApp(_ id: WindowsApp.ID, _ url: URL) {
        guard url.pathExtension.lowercased() == "app" else {
            VestaNotice.show(title: language.text(.bindLocalApp), message: language.text(.bindLocalAppInvalid))
            return
        }
        guard let index = programs.firstIndex(where: { $0.id == id }) else { return }
        programs[index].platform = .macOS
        programs[index].installPath = url.path
        programs[index].absolutePath = url.path
        programs[index].importBookmark = ImportedFileAccess.bookmark(for: url)
        AppLauncher.invalidateInstallCache()
        AppLibraryStore.save(programs)
    }

    private var categoryEmpty: some View {
        PlaceholderPane(
            title: language.text(.emptyCategory),
            systemImage: "line.3.horizontal.decrease.circle",
            message: language.text(.emptyCategoryHint)
        )
    }

    private func keepSelectionVisible() {
        if let selectedID, visible.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = visible.first?.id
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        LibraryRowStatusCache.clear()
        let targets = programs.map {
            LibraryScanTarget(id: $0.id, installPath: $0.installPath, isMacApp: $0.platform == .macOS)
        }
        Task {
            let updates = await Task.detached(priority: .userInitiated) {
                LocalLibraryScan.scan(targets)
            }.value
            var changed = false
            for update in updates {
                guard let index = programs.firstIndex(where: { $0.id == update.id }) else { continue }
                guard update.isInstalled, programs[index].installPath != update.installPath else { continue }
                programs[index].installPath = update.installPath
                if programs[index].platform == .macOS {
                    programs[index].absolutePath = update.installPath
                }
                changed = true
            }
            if changed {
                AppLibraryStore.save(programs)
            }
            AppLauncher.invalidateInstallCache()
            SteamLibrary.invalidate()
            isScanning = false
        }
    }

    private var nothingRunning: some View {
        PlaceholderPane(
            title: language.text(.nothingRunning),
            systemImage: "play.circle",
            message: language.text(.nothingRunningHint),
            buttonTitle: language.text(.showAll),
            action: onShowAllApps
        )
    }

    private var libraryEmpty: some View {
        PlaceholderPane(
            title: language.text(.noApps),
            systemImage: "square.and.arrow.down",
            message: language.text(.noAppsHint),
            buttonTitle: language.text(.importExe),
            action: onImport
        )
    }
}

private struct LibraryFilterBar: View {
    @Binding var category: LibraryCategory
    let isScanning: Bool
    let onScan: () -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LibraryCategory.allCases) { item in
                        FilterChip(title: categoryTitle(item), isOn: category == item) {
                            category = item
                        }
                    }
                }
            }
            scanButton
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var scanButton: some View {
        Button(action: onScan) {
            scanLabel
        }
        .disabled(isScanning)
        .help(language.text(.scanHelp))
    }

    private func categoryTitle(_ item: LibraryCategory) -> String {
        switch item {
        case .all: return language.text(.filterAll)
        case .action: return language.text(.filterAction)
        case .rpg: return language.text(.filterRPG)
        case .shooter: return language.text(.filterShooter)
        case .online: return language.text(.filterOnline)
        case .utility: return language.text(.filterTool)
        }
    }

    @ViewBuilder
    private var scanLabel: some View {
        if isScanning {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(language.text(.scanning))
            }
        } else {
            Label(language.text(.scanLocal), systemImage: "arrow.triangle.2.circlepath")
        }
    }
}

private struct AppCardGrid: View {
    let apps: [WindowsApp]
    @Binding var selectedID: WindowsApp.ID?
    let onToggleFavorite: (WindowsApp.ID) -> Void
    let onBindMacApp: (WindowsApp.ID, URL) -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(apps) { app in
                    let face = LibraryCardFace.make(app: app, language: language)
                    AppItemRow(
                        face: face,
                        isSelected: app.id == selectedID,
                        onToggleFavorite: {
                            onToggleFavorite(app.id)
                        },
                        onBindMacApp: { url in
                            onBindMacApp(app.id, url)
                        }
                    ) {
                        selectedID = app.id
                    }
                    .equatable()
                }
            }
            .padding(12)
        }
        .onScrollPhaseChange { _, phase in
            LibraryScrollGate.shared.setIdle(phase == .idle)
        }
        .onDisappear {
            LibraryScrollGate.shared.setIdle(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(minimum: 220), spacing: 10)]
    }
}

private struct LibraryCardFace: Equatable {
    var name: String
    var publisher: String
    var playtime: String
    var kindLine: String
    var categoryLine: String
    var tags: [String]
    var tint: Color
    var sources: [AppIconSource]
    var fillsIcon: Bool
    var isFavorite: Bool
    var isRunning: Bool
    var isLaunching: Bool
    var status: String
    var platformName: String
    var platformSymbol: String
    var help: String
    var showsBind: Bool
    var bindTitle: String
    var installed: String
    var inLibrary: String
    var absent: String
    var installPath: String
    var statusKey: String
    var checksInstall: Bool
    var platform: AppPlatform
    var bottle: String?
    var steamAppID: String?

    static func make(app: WindowsApp, language: LanguageManager) -> LibraryCardFace {
        let lang = language.currentLanguage
        let name = app.localizedName(lang)
        let platformName = app.bottle ?? "macOS"
        let windowsPath = AppLauncher.looksLikeWindowsPath(app.installPath)
        return LibraryCardFace(
            name: name,
            publisher: app.publisher,
            playtime: app.playtimeTitle(language: lang),
            kindLine: app.localizedKind(lang),
            categoryLine: app.category.isEmpty ? "" : app.localizedCategory(lang),
            tags: app.displayTags,
            tint: app.tint.color,
            sources: app.iconSources,
            fillsIcon: app.iconFillsFrame,
            isFavorite: app.isFavorite,
            isRunning: app.isRunning,
            isLaunching: app.isLaunching,
            status: language.text(app.isLaunching || app.isRunning ? .running : .notRunning),
            platformName: platformName,
            platformSymbol: app.bottle == nil ? "desktopcomputer" : "cylinder",
            help: language.format(.detailHelp, name),
            showsBind: app.platform == .macOS,
            bindTitle: language.text(.bindLocalApp),
            installed: language.text(.installed),
            inLibrary: language.text(.inLibrary),
            absent: language.text(.notInstalled),
            installPath: app.installPath,
            statusKey: "\(app.platform.rawValue)\n\(app.installPath)\n\(app.bottle ?? "")\n\(app.steamAppID ?? "")",
            checksInstall: app.platform == .macOS || !windowsPath || LaunchSafety.backgroundServicesEnabled,
            platform: app.platform,
            bottle: app.bottle,
            steamAppID: app.steamAppID
        )
    }
}

private struct AppItemRow: View, Equatable {
    let face: LibraryCardFace
    let isSelected: Bool
    let onToggleFavorite: () -> Void
    let onBindMacApp: (URL) -> Void
    let onSelect: () -> Void

    static func == (lhs: AppItemRow, rhs: AppItemRow) -> Bool {
        lhs.face == rhs.face && lhs.isSelected == rhs.isSelected
    }

    @State private var availability: SteamCatalogStatus?

    var body: some View {
        SelectableCard(isSelected: isSelected) {
            cardBody
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .help(face.help)
        .contextMenu {
            if face.showsBind {
                Button(face.bindTitle, action: chooseMacApp)
            }
        }
        .task(id: face.installPath) {
            await LibraryScrollGate.shared.waitUntilIdle()
            guard !Task.isCancelled else { return }
            await resolveAvailability()
        }
    }

    private func chooseMacApp() {
        guard let url = MacAppPicker.choose() else { return }
        onBindMacApp(url)
    }

    private func resolveAvailability() async {
        guard face.checksInstall else { return }
        if let cached = LibraryRowStatusCache.status(for: face.statusKey) {
            if availability != cached {
                availability = cached
            }
            return
        }
        let platform = face.platform
        let path = face.installPath
        let bottle = face.bottle
        let steamID = face.steamAppID
        let status: SteamCatalogStatus = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let value = resolvedLibraryStatus(platform: platform, path: path, bottle: bottle, steamAppID: steamID)
                continuation.resume(returning: value)
            }
        }
        guard !Task.isCancelled, LibraryScrollGate.shared.isIdle else { return }
        LibraryRowStatusCache.store(status, for: face.statusKey)
        availability = status
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            meta
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(
                sources: face.sources,
                tint: face.tint,
                size: 44,
                cornerRadius: 14,
                fillsFrame: face.fillsIcon,
                pausesWhileScrolling: true
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(face.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    FavoriteStarButton(isFavorite: face.isFavorite, action: onToggleFavorite)
                }
                Text(face.publisher)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(face.playtime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !face.tags.isEmpty {
                    TagCapsuleRow(tags: face.tags, tint: face.tint)
                }
            }
            Spacer(minLength: 8)
            statusLabel
        }
    }

    private var statusLabel: some View {
        Group {
            if face.isLaunching {
                LaunchingStatusText(fallback: face.status, tint: .orange)
            } else {
                Text(face.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(face.isRunning ? Color.green : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((face.isRunning ? Color.green : Color.secondary).opacity(0.15), in: Capsule())
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 8) {
            Text(face.kindLine)
            if !face.categoryLine.isEmpty {
                Text("·")
                Text(face.categoryLine)
                    .lineLimit(1)
            }
            Text("·")
            Text(availabilityText)
                .foregroundStyle(availabilityColor)
            Text("·")
            Label(face.platformName, systemImage: face.platformSymbol)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var availabilityText: String {
        switch availability {
        case .installed: return face.installed
        case .inLibrary: return face.inLibrary
        case .absent, .none: return face.absent
        }
    }

    private var availabilityColor: Color {
        switch availability {
        case .installed: return .green
        case .inLibrary: return .orange
        case .absent, .none: return .secondary
        }
    }
}

/// 安装状态按路径记住。滑回去时不再扫一遍容器和 Steam 清单。
private enum LibraryRowStatusCache {
    private static let lock = NSLock()
    private static var values: [String: SteamCatalogStatus] = [:]

    static func status(for key: String) -> SteamCatalogStatus? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    static func store(_ status: SteamCatalogStatus, for key: String) {
        lock.lock()
        values[key] = status
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }
}
