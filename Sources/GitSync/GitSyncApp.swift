// GitSyncApp.swift
// GitSync macOS 菜单栏应用入口

import SwiftUI

@main
struct GitSyncApp: App {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var historyStore = SyncHistoryStore()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var notificationService = NotificationService()

    /// 自动同步服务（延迟初始化，依赖其他 StateObject）
    @State private var autoSyncService: AutoSyncService?

    var body: some Scene {
        // 菜单栏常驻图标，macOS 13+ MenuBarExtra
        // 图标根据同步状态动态变化
        MenuBarExtra {
            MenuBarView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
                .environmentObject(networkMonitor)
                .environmentObject(notificationService)
        } label: {
            // 状态栏图标：根据同步状态变化
            // TODO: 本地化辅助功能描述
            Image(systemName: statusBarIconName)
        }
        .menuBarExtraStyle(.window)

        // 设置窗口
        Settings {
            SettingsView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
        }
        .onAppear {
            setupAutoSyncService()
        }
    }

    /// 初始化并启动自动同步服务
    private func setupAutoSyncService() {
        guard autoSyncService == nil else { return }
        let service = AutoSyncService(
            projectStore: projectStore,
            historyStore: historyStore,
            notificationService: notificationService,
            networkMonitor: networkMonitor
        )
        autoSyncService = service
    }

    /// 根据项目同步状态动态计算状态栏图标
    private var statusBarIconName: String {
        // 优先使用 AutoSyncService 的状态
        if let service = autoSyncService {
            switch service.appStatus {
            case .syncing:
                return "arrow.triangle.2.circlepath"
            case .conflict:
                return "exclamationmark.circle.fill"
            case .noNetwork:
                return "wifi.slash"
            case .hasUpdate:
                return "arrow.down.circle.fill"
            case .idle:
                break
            }
        }

        let statuses = projectStore.projects.map { $0.syncStatus }
        if statuses.contains(.syncing) {
            return "arrow.triangle.2.circlepath"
        }
        if statuses.contains(.error) || statuses.contains(.conflict) {
            return "exclamationmark.circle.fill"
        }
        return "arrow.triangle.2.circlepath"
    }
}

// MARK: - 菜单栏主视图

struct MenuBarView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var notificationService: NotificationService
    @State private var searchText = ""

    /// 自动同步间隔（分钟）
    @AppStorage("autoSyncInterval") private var autoSyncInterval = 5.0
    /// 是否启用自动同步
    @AppStorage("autoSyncEnabled") private var autoSyncEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                // TODO: String(localized: "search_placeholder")
                TextField(String(localized: "搜索项目..."), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 项目列表
            if filteredProjects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    // TODO: String(localized:)
                    Text(String(localized: "暂无项目"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(String(localized: "在设置中添加 Git 仓库"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredProjects) { project in
                            ProjectRowView(project: project)
                                .environmentObject(projectStore)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            Divider()

            // 底部操作栏
            HStack {
                // 网络状态指示
                if !networkMonitor.isConnected {
                    Image(systemName: networkMonitor.iconName)
                        .foregroundColor(.red)
                        .help(networkMonitor.statusDescription)
                }

                Button(String(localized: "全部同步")) {
                    Task {
                        await performSyncAll()
                    }
                }
                .disabled(projectStore.projects.isEmpty || !networkMonitor.isConnected)

                Spacer()

                Button(String(localized: "设置")) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }

                Button(String(localized: "退出")) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
        }
        .frame(width: 320)
    }

    /// 按搜索关键词过滤项目
    private var filteredProjects: [SyncProject] {
        projectStore.filterProjects(searchText: searchText)
    }

    /// 同步所有项目（通过 SyncEngine 直接调用）
    private func performSyncAll() async {
        let syncEngine = SyncEngine(gitService: .shared, historyStore: historyStore)
        for project in projectStore.projects {
            projectStore.updateSyncStatus(for: project.id, status: .syncing, message: String(localized: "同步中..."))
            let result = await syncEngine.syncProject(project)
            switch result {
            case .success(let message):
                projectStore.updateSyncStatus(for: project.id, status: .synced, message: message)
            case .upToDate:
                projectStore.updateSyncStatus(for: project.id, status: .synced, message: String(localized: "已是最新"))
            case .conflict(let details):
                projectStore.updateSyncStatus(for: project.id, status: .conflict, message: String(localized: "冲突：\(details)"))
            case .error(let message):
                projectStore.updateSyncStatus(for: project.id, status: .error, message: message)
            }
        }
    }
}

// MARK: - 项目行视图

struct ProjectRowView: View {
    let project: SyncProject
    @EnvironmentObject var projectStore: ProjectStore

    var body: some View {
        HStack(spacing: 10) {
            // 同步状态图标
            Image(systemName: project.syncStatus.iconName)
                .foregroundColor(project.syncStatus.color)
                .frame(width: 20)

            // 项目信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(project.name)
                        .font(.system(.body, weight: .medium))
                    if project.isOwnRepo {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if project.forkedFrom != nil {
                        Image(systemName: "tuningfork")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                Text(project.owner)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !project.lastSyncMessage.isEmpty {
                    Text(project.lastSyncMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 操作按钮
            VStack(spacing: 4) {
                Button {
                    Task {
                        await syncSingleProject(project)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                // TODO: String(localized:)
                .help(String(localized: "同步此项目"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // 双击打开本地目录
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.localPath)
        }
        .contextMenu {
            Button(String(localized: "在 Finder 中打开")) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.localPath)
            }
            Button(String(localized: "在终端中打开")) {
                NSWorkspace.shared.open(URL(fileURLWithPath: project.localPath))
            }
            Divider()
            Button(String(localized: "复制 GitHub URL")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(project.remoteURL, forType: .string)
            }
            Divider()
            Button(String(localized: "删除项目"), role: .destructive) {
                projectStore.deleteProject(project)
            }
        }
    }

    /// 同步单个项目（通过 SyncEngine）
    private func syncSingleProject(_ project: SyncProject) async {
        let syncEngine = SyncEngine(gitService: .shared)
        projectStore.updateSyncStatus(for: project.id, status: .syncing, message: String(localized: "同步中..."))
        let result = await syncEngine.syncProject(project)
        switch result {
        case .success(let message):
            projectStore.updateSyncStatus(for: project.id, status: .synced, message: message)
        case .upToDate:
            projectStore.updateSyncStatus(for: project.id, status: .synced, message: String(localized: "已是最新"))
        case .conflict(let details):
            projectStore.updateSyncStatus(for: project.id, status: .conflict, message: String(localized: "冲突：\(details)"))
        case .error(let message):
            projectStore.updateSyncStatus(for: project.id, status: .error, message: message)
        }
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore
    @AppStorage("defaultSyncPath") private var defaultSyncPath = NSHomeDirectory() + "/GitHub"
    @AppStorage("autoSyncInterval") private var autoSyncInterval = 5.0
    @AppStorage("autoSyncEnabled") private var autoSyncEnabled = true
    @AppStorage("githubToken") private var githubToken = ""
    @State private var showingTokenAlert = false

    var body: some View {
        TabView {
            // 通用设置
            Form {
                Section(String(localized: "同步目录")) {
                    HStack {
                        // TODO: String(localized:)
                        TextField(String(localized: "默认路径"), text: $defaultSyncPath)
                            .textFieldStyle(.roundedBorder)
                        Button(String(localized: "选择")) {
                            if let path = pickDirectory() {
                                defaultSyncPath = path
                            }
                        }
                    }
                    Text(String(localized: "新项目将默认保存到此目录"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(String(localized: "自动同步")) {
                    Toggle(String(localized: "启用自动同步"), isOn: $autoSyncEnabled)
                    if autoSyncEnabled {
                        Picker(String(localized: "同步间隔"), selection: $autoSyncInterval) {
                            Text(String(localized: "每 1 分钟")).tag(1.0)
                            Text(String(localized: "每 5 分钟")).tag(5.0)
                            Text(String(localized: "每 15 分钟")).tag(15.0)
                            Text(String(localized: "每 1 小时")).tag(60.0)
                        }
                    }
                }
            }
            .tabItem { Label(String(localized: "通用"), systemImage: "gear") }
            .frame(width: 400, height: 250)

            // GitHub 设置
            Form {
                Section(String(localized: "GitHub Token")) {
                    SecureField("Personal Access Token", text: $githubToken)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(String(localized: "获取 Token")) {
                            NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens")!)
                        }
                        Button(String(localized: "测试连接")) {
                            showingTokenAlert = true
                        }
                        .disabled(githubToken.isEmpty)
                    }

                    Text(String(localized: "需要 repo 权限（Fine-grained Token 推荐）"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tabItem { Label("GitHub", systemImage: "person.circle") }
            .frame(width: 400, height: 200)

            // 项目管理
            VStack {
                if projectStore.projects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text(String(localized: "暂无项目"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(projectStore.projects) { project in
                            HStack {
                                Circle()
                                    .fill(project.syncStatus.color)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading) {
                                    Text(project.name).font(.headline)
                                    Text(project.remoteURL).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "删除"), role: .destructive) {
                                    projectStore.deleteProject(project)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .tabItem { Label(String(localized: "项目"), systemImage: "folder") }
            .frame(width: 400, height: 300)
        }
        .frame(width: 500, height: 400)
        .alert(String(localized: "测试连接"), isPresented: $showingTokenAlert) {
            Button(String(localized: "确定")) {}
        } message: {
            Text(String(localized: "Token 验证功能将在下次同步时自动测试"))
        }
    }

    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
