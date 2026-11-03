import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var iconName: String
    var isRunning: Bool
    var statusText: String
    var category: String
    var executablePath: String?

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String,
        isRunning: Bool,
        statusText: String,
        category: String,
        executablePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.isRunning = isRunning
        self.statusText = statusText
        self.category = category
        self.executablePath = executablePath
    }
}

enum NavigationMenu: Hashable {
    case allApps
    case gameController
    case utilityTools
}

struct ContentView: View {
    @State private var selectedMenu: NavigationMenu? = .allApps
    @State private var searchText = ""
    @State private var selectedFilter = "全部"
    @State private var isShowingFileImporter = false
    @State private var selectedFilePath = ""
    @State private var selectedAppID: UUID?
    @State private var isShowingLogin = false
    @State private var signedInAccount: String?

    @State private var appsList = [
        AppItem(name: "Steam", iconName: "play.fill", isRunning: true, statusText: "运行中", category: "工具"),
        AppItem(name: "黑神话：悟空 (Black Myth: Wukong)", iconName: "gamecontroller.fill", isRunning: false, statusText: "未运行", category: "游戏"),
        AppItem(name: "赛博朋克 2077 (Cyberpunk 2077)", iconName: "bolt.fill", isRunning: false, statusText: "未运行", category: "游戏"),
        AppItem(name: "Office 办公套件 (.exe)", iconName: "doc.plaintext.fill", isRunning: false, statusText: "未运行", category: "办公")
    ]

    private var filteredApps: [AppItem] {
        appsList.filter { app in
            matchesMenu(app) && matchesSearch(app)
        }
    }

    private var selectedApp: AppItem? {
        appsList.first { $0.id == selectedAppID }
    }

    private var exeContentTypes: [UTType] {
        if let exe = UTType(filenameExtension: "exe") {
            return [exe]
        }
        return [.data]
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            library
        } detail: {
            detail
        }
        .background(.background)
        .sheet(isPresented: $isShowingLogin) {
            GlobalPhoneLoginView { phone in
                signedInAccount = phone
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedMenu) {
            NavigationLink(value: NavigationMenu.allApps) {
                Label("🌟 应用/游戏库", systemImage: "sparkles")
            }

            Section("🍎 macOS 专区") {
                NavigationLink(value: NavigationMenu.gameController) {
                    Label("🎮 游戏大作", systemImage: "gamecontroller")
                }
                NavigationLink(value: NavigationMenu.utilityTools) {
                    Label("🛠️ 实用工具", systemImage: "wrench.and.screwdriver")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.background)
        .navigationTitle("Mac 启动器")
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                Button {
                    isShowingLogin = true
                } label: {
                    HStack {
                        Image(systemName: signedInAccount == nil ? "clock.fill" : "person.crop.circle.fill")
                        Text(signedInAccount ?? "试用期中 · 剩余 14 天")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cpu.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac 硬件摘要")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Apple M3 Pro / 18GB 统一内存")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding()
        }
    }

    private var library: some View {
        VStack(spacing: 14) {
            Button {
                isShowingFileImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("导入 .exe 软件")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索应用或发行商", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if selectedMenu == .allApps || selectedMenu == nil {
                Picker("分类", selection: $selectedFilter) {
                    Text("全部").tag("全部")
                    Text("游戏").tag("游戏")
                    Text("办公").tag("办公")
                    Text("工具").tag("工具")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if filteredApps.isEmpty {
                ContentUnavailableView(
                    "没有匹配的应用",
                    systemImage: "magnifyingglass",
                    description: Text("换个关键词，或导入一个 .exe 软件。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedAppID) {
                    ForEach(filteredApps) { app in
                        appRow(app)
                            .tag(app.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 380)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: exeContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importExecutable(at: url)
            }
        }
    }

    private var detail: some View {
        Group {
            if let app = selectedApp {
                appDetail(app)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("Windows 软件兼容中心")
                        .font(.title)
                        .bold()
                    Text("在右侧直接查看应用的运行门槛、所属容器以及调优技巧。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if !selectedFilePath.isEmpty {
                        Text("已成功挂载的 EXE 路径:\n\(selectedFilePath)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 380, ideal: 520)
    }

    private func appRow(_ app: AppItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: app.iconName)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .fontWeight(.medium)
                Text("\(app.category) · Windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(app.statusText)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(app.isRunning ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                .foregroundStyle(app.isRunning ? .green : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 4)
    }

    private func appDetail(_ app: AppItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: app.iconName)
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("\(app.category) · Windows")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(app.statusText)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(app.isRunning ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                        .foregroundStyle(app.isRunning ? .green : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Button(app.isRunning ? "停止" : "启动") {
                    toggleRunning(app)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(compatibilityNotes(for: app), id: \.title) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(note.body)
                                .font(.body)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let path = app.executablePath {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已挂载的 EXE 路径")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func matchesMenu(_ app: AppItem) -> Bool {
        switch selectedMenu {
        case .gameController:
            return app.category == "游戏"
        case .utilityTools:
            return app.category == "工具"
        default:
            return selectedFilter == "全部" || app.category == selectedFilter
        }
    }

    private func matchesSearch(_ app: AppItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return app.name.localizedCaseInsensitiveContains(query)
            || app.category.localizedCaseInsensitiveContains(query)
    }

    private func compatibilityNotes(for app: AppItem) -> [(title: String, body: String)] {
        switch app.category {
        case "游戏":
            return [
                ("运行门槛", "Apple M 系列 · macOS 14+ · 建议 16GB 统一内存"),
                ("所属容器", "Windows 游戏容器"),
                ("调优技巧", "开启高性能模式，关闭垂直同步以降低延迟。")
            ]
        case "办公":
            return [
                ("运行门槛", "Apple M 系列 · macOS 14+ · 内存占用极低"),
                ("所属容器", "Windows 办公容器"),
                ("调优技巧", "开启文件关联与字体平滑，适合长时间使用。")
            ]
        default:
            return [
                ("运行门槛", "Apple M 系列 · macOS 14+"),
                ("所属容器", "Windows 工具容器"),
                ("调优技巧", "保持容器常驻，可缩短下次启动时间。")
            ]
        }
    }

    private func toggleRunning(_ app: AppItem) {
        guard let index = appsList.firstIndex(where: { $0.id == app.id }) else { return }
        appsList[index].isRunning.toggle()
        appsList[index].statusText = appsList[index].isRunning ? "运行中" : "未运行"
    }

    private func importExecutable(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let path = url.path
        selectedFilePath = path

        if let existing = appsList.first(where: { $0.executablePath == path }) {
            selectedAppID = existing.id
            selectedMenu = .allApps
            selectedFilter = "全部"
            return
        }

        let imported = AppItem(
            name: url.deletingPathExtension().lastPathComponent,
            iconName: "square.and.arrow.down.fill",
            isRunning: false,
            statusText: "已导入",
            category: category(forImportedFileNamed: url.lastPathComponent),
            executablePath: path
        )
        appsList.insert(imported, at: 0)
        selectedAppID = imported.id
        selectedMenu = .allApps
        selectedFilter = "全部"
    }

    private func category(forImportedFileNamed name: String) -> String {
        let lowered = name.lowercased()
        let officeHints = ["office", "word", "excel", "powerpoint", "outlook", "wps"]
        if officeHints.contains(where: { lowered.contains($0) }) {
            return "办公"
        }
        return "工具"
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.light)
}
