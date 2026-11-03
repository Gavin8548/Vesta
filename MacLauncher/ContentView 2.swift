//
//  ContentView.swift
//
//  两栏根视图：固定侧边栏，右侧是列表和详情。
//  具体界面在这些文件里，每个文件的 body 都保持很短，方便编译器分别推断类型：
//  SidebarView.swift、AppListView.swift、AppDetailView.swift、
//  BottleListView.swift、BottleDetailView.swift、SettingsView.swift、
//  LibraryComponents.swift、Models.swift
//
//  部署目标：macOS 14.0 及以上。
//

import SwiftUI

struct ContentView: View {
    @State private var section: SidebarDestination = .allApps
    @State private var programs = WindowsApp.samples
    @State private var bottles = Bottle.samples
    @State private var selectedProgramID: WindowsApp.ID? = WindowsApp.samples.first?.id
    @State private var selectedBottleID: Bottle.ID? = Bottle.samples.first?.id
    @State private var programQuery = ""
    @State private var bottleQuery = ""
    @State private var libraryCategory: LibraryCategory = .all
    @State private var settingsPane: SettingsPane = .general

    @State private var isPresentingNewBottle = false
    @State private var showsImportError = false
    @State private var importError = ""

    @State private var appearance: AppearancePreference = .system
    @State private var restoresLastBottle = true
    @AppStorage("MyApp.showsMenuBar") private var showsRunningInMenuBar = true
    @State private var enablesDXVK = true
    @State private var enablesRetina = true
    @State private var didLoadLibrary = false
    @State private var lifetimeWatch: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            EngineProgressBanner()
            splitView
        }
            .frame(minWidth: 920, idealWidth: 920, maxWidth: .infinity, minHeight: 580, idealHeight: 580, maxHeight: .infinity)
            .preferredColorScheme(appearance.colorScheme)
            .modifier(importChrome)
            .onChange(of: section) { _, newSection in
                focusSelection(for: newSection)
            }
            .onChange(of: selectedProgramID) { _, newID in
                matchBottle(to: newID)
            }
            .onAppear {
                VestaMainWindow.enableNativeControls()
                loadLibrary()
                pushRunningStatus()
                verifyStoredEngineAndPrefix()
                ensurePresetBottles()
                matchBottle(to: selectedProgramID)
                syncPerformanceOverlay()
                PerformanceOverlayService.shared.startIfNeeded()
                reconcileProcessLifetimes()
                syncLifetimeWatch(programs.contains { $0.isRunning || $0.isLaunching })
            }
            .onChange(of: programs.contains(where: \.isRunning)) { _, _ in
                pushRunningStatus()
                syncPerformanceOverlay()
            }
            .onChange(of: showsRunningInMenuBar) { _, _ in
                pushRunningStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .windowsAppDidExit)) { note in
                handleProcessExit(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .vestaLibraryRestored)) { _ in
                reloadLibraryFromBackup()
            }
            .onChange(of: programs.contains { $0.isRunning || $0.isLaunching }) { _, active in
                syncLifetimeWatch(active)
            }
            .onChange(of: scenePhase) { _, phase in
                let windowActive = phase == .active
                PerformanceOverlayService.shared.setWindowActive(windowActive)
                if windowActive {
                    syncLifetimeWatch(programs.contains { $0.isRunning || $0.isLaunching })
                } else {
                    lifetimeWatch?.cancel()
                    lifetimeWatch = nil
                }
            }
            .onDisappear {
                lifetimeWatch?.cancel()
                lifetimeWatch = nil
            }
    }

    @ViewBuilder
    private var splitView: some View {
        let columns = VestaColumns()
        HStack(spacing: 0) {
            SidebarView(selection: $section)
                .frame(width: columns.sidebar)
                .layoutPriority(1)
            Divider()
            mainColumns(listWidth: columns.list)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mainColumns(listWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            MainListColumn(
                section: $section,
                programs: $programs,
                bottles: bottles,
                programQuery: $programQuery,
                bottleQuery: $bottleQuery,
                libraryCategory: $libraryCategory,
                selectedProgramID: $selectedProgramID,
                selectedBottleID: $selectedBottleID,
                settingsPane: $settingsPane,
                onImport: presentImporter,
                onDropImport: { url, started in
                    importSelection(url, securityScopeStarted: started)
                },
                onCreateBottle: presentNewBottle
            )
            .frame(width: listWidth)
            Divider()
            MainDetailColumn(
                section: section,
                programs: $programs,
                selectedProgramID: selectedProgramID,
                bottles: $bottles,
                selectedBottleID: $selectedBottleID,
                settingsPane: settingsPane,
                appearance: $appearance,
                restoresLastBottle: $restoresLastBottle,
                showsRunningInMenuBar: $showsRunningInMenuBar,
                enablesDXVK: $enablesDXVK,
                enablesRetina: $enablesRetina
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importChrome: ImportChrome {
        ImportChrome(
            isPresentingNewBottle: $isPresentingNewBottle,
            showsImportError: $showsImportError,
            importError: importError,
            onCreateBottle: addBottle
        )
    }

    private func presentImporter() {
        guard let url = ImportPanel.choose() else { return }
        importSelection(url)
    }

    /// 面板选择和拖拽共用这一条路径。拖拽会提前打开安全作用域，这里只负责在解析结束后关闭。
    private func importSelection(_ url: URL, securityScopeStarted: Bool = false) {
        let accessing = securityScopeStarted || url.startAccessingSecurityScopedResource()
        let bottle = bottles.first(where: \.isDefault) ?? bottles.first
        let bottleName = bottle?.name ?? "Bottle"
        let bottleID = bottle?.id
        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                LibraryImport.load(url, bottleName: bottleName)
            }.value
            switch loaded {
            case .failure(let failure):
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                presentImportError(importFailureMessage(failure))
            case .success(let item):
                commitImport(item, bottleID: bottleID)
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }

    private func presentNewBottle() {
        isPresentingNewBottle = true
    }

    /// 切换侧边栏时，让右侧详情仍然对应列表里可见的那一项。
    private func focusSelection(for section: SidebarDestination) {
        if section.showsApps {
            let visible = programs.filtered(
                query: programQuery,
                onlyRunning: false,
                category: libraryCategory,
                platform: section.platformFilter,
                catalog: section.catalog,
                favoritesOnly: section.favoritesOnly
            )
            keepProgramSelection(in: visible)
            return
        }
        switch section {
        case .bottles:
            let visible = bottles.filtered(query: bottleQuery)
            keepBottleSelection(in: visible)
        case .settings:
            break
        default:
            break
        }
    }

    /// 游戏退出由通知立刻更新。只有确实有进程在跑时，才每 8 秒补一次核对。
    private func syncLifetimeWatch(_ active: Bool) {
        lifetimeWatch?.cancel()
        lifetimeWatch = nil
        guard active, scenePhase == .active else { return }
        lifetimeWatch = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                reconcileProcessLifetimes()
            }
        }
    }
    /// 只有还活着的 Wine 进程才保持「运行中」。没有进程时立刻回到「就绪」。
    private func reconcileProcessLifetimes() {
        let ready = L10n.string(.ready, language: L10n.savedLanguage())
        let stoppedChinese = L10n.string(.stopped, language: .chinese)
        let stoppedEnglish = L10n.string(.stopped, language: .english)
        for index in programs.indices {
            guard programs[index].platform != .macOS else { continue }
            let id = programs[index].id
            let alive = LaunchSessionStore.shared.trackedIsRunning(id) == true
            if alive {
                guard !programs[index].isRunning else { continue }
                programs[index].isRunning = true
                programs[index].isLaunching = false
                programs[index].launchMessage = L10n.string(.running, language: L10n.savedLanguage())
                continue
            }
            if programs[index].isLaunching, LaunchSessionStore.shared.trackedIsRunning(id) == nil {
                continue
            }
            guard programs[index].isRunning || programs[index].isLaunching else { continue }
            programs[index].isRunning = false
            programs[index].isLaunching = false
            if programs[index].launchMessage != stoppedChinese, programs[index].launchMessage != stoppedEnglish {
                programs[index].launchMessage = ready
            }
        }
    }

    /// 后台进程结束后，把对应软件从「运行中」拿掉。用户刚点过停止时保留「已停止」。
    private func handleProcessExit(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? UUID,
              let index = programs.firstIndex(where: { $0.id == id }) else { return }
        if let elapsed = note.userInfo?["elapsed"] as? TimeInterval, elapsed > 0 {
            programs[index].playtimeSeconds += elapsed
            AppLibraryStore.save(programs)
        }
        LaunchSessionStore.shared.endLaunchClaim(id)
        guard programs[index].isRunning || programs[index].isLaunching else { return }
        programs[index].isRunning = false
        programs[index].isLaunching = false
        if programs[index].launchMessage == L10n.string(.stopped, language: .chinese)
            || programs[index].launchMessage == L10n.string(.stopped, language: .english) {
            return
        }
        if let status = note.userInfo?["status"] as? Int, status != 0 {
            let log = note.userInfo?["log"] as? String ?? ""
            programs[index].launchMessage = AppLauncher.exitSummary(status: status, log: log)
            return
        }
        programs[index].launchMessage = L10n.string(.ready, language: L10n.savedLanguage())
    }

    private func pushRunningStatus() {
        let sessions = programs.filter(\.isRunning).map { RunningSession(id: $0.id, name: $0.name) }
        VestaStatusItem.shared.update(sessions: sessions, enabled: showsRunningInMenuBar)
    }

    private func syncPerformanceOverlay() {
        let running = programs.contains(where: \.isRunning)
        guard PerformanceOverlayService.shared.gameIsRunning != running else { return }
        PerformanceOverlayService.shared.gameIsRunning = running
    }

    private func keepProgramSelection(in visible: [WindowsApp]) {
        if let selectedProgramID, visible.contains(where: { $0.id == selectedProgramID }) {
            return
        }
        selectedProgramID = visible.first?.id
    }

    /// 保证 Gaming、Office 这些预置容器一直在列表里，避免详情页说找不到它们。
    private func ensurePresetBottles() {
        for sample in Bottle.samples where bottles.matching(name: sample.name) == nil && bottles.matching(name: sample.id) == nil {
            bottles.append(sample)
        }
    }

    /// 选中应用后，按它的容器名选中 Gaming、Office 等对应瓶子。
    private func matchBottle(to appID: WindowsApp.ID?) {
        guard let appID, let app = programs.first(where: { $0.id == appID }) else { return }
        guard let name = app.bottle, let bottle = bottles.matching(name: name) else { return }
        selectedBottleID = bottle.id
    }

    private func keepBottleSelection(in visible: [Bottle]) {
        if let selectedBottleID, visible.contains(where: { $0.id == selectedBottleID }) {
            return
        }
        selectedBottleID = visible.first?.id
    }

    private func commitImport(_ item: LibraryImport.Item, bottleID: String?) {
        let language = L10n.savedLanguage()
        let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? L10n.string(.unnamedApp, language: language) : trimmed
        let source = URL(fileURLWithPath: item.sourcePath)
        let appID = programs.first { $0.isUserImported && $0.absolutePath == item.sourcePath }?.id ?? UUID()
        let iconPath = AppLibraryStore.saveIcon(for: source, id: appID)
        let bottleName = item.isMacApp ? nil : (bottles.first { $0.id == bottleID }?.name ?? "Bottle")
        var app = makeImportedApp(
            id: appID,
            name: resolvedName,
            path: item.installPath,
            bottleName: bottleName,
            bookmark: item.bookmark,
            isMacApp: item.isMacApp
        )
        app.absolutePath = item.sourcePath
        app.customIconName = iconPath ?? programs.first { $0.id == appID }?.customIconName
        if let previous = programs.first(where: { $0.id == appID }) {
            app.playtimeSeconds = previous.playtimeSeconds
            app.isFavorite = previous.isFavorite
        }
        if !item.isMacApp, GamePresetStore.saved(for: app) == nil {
            let preset = GameRecipeManager.preset(
                name: app.name,
                steamAppID: app.steamAppID,
                tags: app.displayTags,
                platform: app.platform
            )
            GamePresetStore.apply(preset, to: app, host: HostEngine.resolved())
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            if let bottleID, let index = bottles.firstIndex(where: { $0.id == bottleID }), !item.isMacApp {
                if !bottles[index].programNames.contains(resolvedName) {
                    bottles[index].programNames.append(resolvedName)
                }
            }
            if let index = programs.firstIndex(where: { $0.id == appID }) {
                programs[index] = app
            } else {
                programs.insert(app, at: 0)
            }
            programQuery = ""
            libraryCategory = .all
            selectedProgramID = app.id
            section = .allApps
        }
        AppLibraryStore.save(programs)
    }

    private func importFailureMessage(_ failure: LibraryImport.Failure) -> String {
        switch failure {
        case .unsupported:
            return L10n.string(.chooseExe, language: L10n.savedLanguage())
        case .copyFailed(let message):
            return message
        }
    }

    /// 启动时只核对硬盘上的引擎和容器，文件还在就保持就绪，不触发下载。
    private func verifyStoredEngineAndPrefix() {
        DispatchQueue.global(qos: .utility).async {
            _ = WineLocator.savedEngineIfPresent()
            _ = WinePrefixStore.resolve()
        }
    }

    private func reloadLibraryFromBackup() {
        programs = WindowsApp.samples
        didLoadLibrary = false
        loadLibrary()
    }

    private func loadLibrary() {
        guard !didLoadLibrary else { return }
        didLoadLibrary = true
        AppLibraryStore.load(into: &programs)
        if selectedProgramID == nil || !programs.contains(where: { $0.id == selectedProgramID }) {
            selectedProgramID = programs.first?.id
        }
    }

    private func makeImportedApp(id: UUID, name: String, path: String, bottleName: String?, bookmark: Data?, isMacApp: Bool) -> WindowsApp {
        let language = L10n.savedLanguage()
        var app = WindowsApp(
            id: id,
            name: name,
            publisher: L10n.string(.importedPublisher, language: language),
            version: "—",
            kind: .game,
            category: "游戏",
            summary: L10n.string(isMacApp ? .importedMacSummary : .importedSummary, language: language),
            bottleName: isMacApp ? nil : bottleName,
            platform: isMacApp ? .macOS : .windows,
            installPath: path,
            importBookmark: bookmark,
            iconName: "app.fill",
            symbolName: "app.fill",
            tint: .teal,
            isRunning: false,
            lastRunText: "尚未运行"
        )
        app.isUserImported = true
        return app
    }

    private func presentImportError(_ message: String) {
        importError = message
        showsImportError = true
    }

    private func addBottle(_ draft: NewBottleDraft) {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let bottle = Bottle(
            id: UUID().uuidString,
            name: trimmed,
            windowsVersion: draft.windowsVersion,
            wineVersion: "Wine 9.0",
            programNames: [],
            isDefault: bottles.isEmpty,
            enablesDXVK: draft.enablesDXVK,
            enablesMetal3: draft.enablesMetal3,
            enablesEsync: (GamePresetLibrary.preset(id: draft.presetID)?.esyncEnabled ?? false) && LicenseGate.shared.allowsAdvanced()
        )
        if !draft.presetID.isEmpty {
            GamePresetStore.rememberBottle(draft.presetID, name: trimmed)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            bottles.append(bottle)
            bottleQuery = ""
            selectedBottleID = bottle.id
            section = .bottles
        }
        BottleActions.prepareLocalPrefix(named: bottle.name)
    }
}

// MARK: - 中间栏切换

/// 侧边栏和列表保持紧凑定宽，详情吃掉剩余宽度。
private struct VestaColumns {
    let sidebar: CGFloat = 210
    let list: CGFloat = 320
}

private struct MainListColumn: View {
    @Binding var section: SidebarDestination
    @Binding var programs: [WindowsApp]
    let bottles: [Bottle]
    @Binding var programQuery: String
    @Binding var bottleQuery: String
    @Binding var libraryCategory: LibraryCategory
    @Binding var selectedProgramID: WindowsApp.ID?
    @Binding var selectedBottleID: Bottle.ID?
    @Binding var settingsPane: SettingsPane
    let onImport: () -> Void
    let onDropImport: (URL, Bool) -> Void
    let onCreateBottle: () -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        pages
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pages: some View {
        switch section {
        case .bottles:
            BottleListView(
                bottles: bottles,
                query: $bottleQuery,
                selectedID: $selectedBottleID,
                onImport: onImport,
                onDropImport: onDropImport,
                onCreate: onCreateBottle
            )
        case .settings:
            SettingsListView(selection: $settingsPane)
        default:
            AppListView(
                programs: $programs,
                onlyRunning: false,
                platform: section.platformFilter,
                catalog: section.catalog,
                favoritesOnly: section.favoritesOnly,
                listTitle: localizedSectionTitle,
                query: $programQuery,
                category: $libraryCategory,
                selectedID: $selectedProgramID,
                onImport: onImport,
                onDropImport: onDropImport,
                onShowAllApps: showAllApps
            )
        }
    }

    private var localizedSectionTitle: String {
        switch section {
        case .allApps: return "🌟 " + language.text(.library)
        case .macOS: return language.text(.macZone)
        case .macGames: return language.text(.macGames)
        case .macTools: return language.text(.macTools)
        case .windows: return language.text(.windowsZone)
        case .windowsGames: return language.text(.windowsGames)
        case .windowsTools: return language.text(.windowsTools)
        case .bottles: return language.text(.bottles)
        case .settings: return language.text(.settings)
        case .favorites: return "⭐ " + language.text(.favorites)
        }
    }

    private func showAllApps() {
        section = .allApps
    }
}

// MARK: - 右侧栏切换

private struct MainDetailColumn: View {
    let section: SidebarDestination
    @Binding var programs: [WindowsApp]
    let selectedProgramID: WindowsApp.ID?
    @Binding var bottles: [Bottle]
    @Binding var selectedBottleID: Bottle.ID?
    let settingsPane: SettingsPane
    @Binding var appearance: AppearancePreference
    @Binding var restoresLastBottle: Bool
    @Binding var showsRunningInMenuBar: Bool
    @Binding var enablesDXVK: Bool
    @Binding var enablesRetina: Bool

    var body: some View {
        pages
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pages: some View {
        switch section {
        case .bottles:
            BottleDetailHost(bottles: $bottles, selectedID: selectedBottleID)
        case .settings:
            SettingsDetailView(
                pane: settingsPane,
                appearance: $appearance,
                restoresLastBottle: $restoresLastBottle,
                showsRunningInMenuBar: $showsRunningInMenuBar,
                enablesDXVK: $enablesDXVK,
                enablesRetina: $enablesRetina
            )
        default:
            AppDetailHost(
                programs: $programs,
                bottles: $bottles,
                selectedBottleID: $selectedBottleID,
                selectedID: selectedProgramID
            )
        }
    }
}

// MARK: - 导入与新建

/// 文件面板、新建容器和错误提示单独做一层，不堆在根视图的 body 上。
private struct ImportChrome: ViewModifier {
    @Binding var isPresentingNewBottle: Bool
    @Binding var showsImportError: Bool
    let importError: String
    let onCreateBottle: (NewBottleDraft) -> Void
    @EnvironmentObject private var language: LanguageManager

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresentingNewBottle) {
                NewBottleSheet(onCreate: onCreateBottle)
            }
            .alert(language.text(.importFailed), isPresented: $showsImportError) {
                Button(language.text(.ok), role: .cancel) {}
            } message: {
                Text(importError)
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(LanguageManager.shared)
            .frame(width: 1180, height: 740)
    }
}
