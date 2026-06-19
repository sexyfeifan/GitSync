// MainDashboardView.swift
// 主界面：项目仪表盘

import SwiftUI

struct ProjectDetailInfo: Identifiable, Hashable {
    let id: UUID
    let project: SyncProject
    var localInfo: GitService.LocalRepoInfo?
    var githubRepo: GitHubRepo?
    var readme: String?
    var isLoading: Bool = true

    static func == (lhs: ProjectDetailInfo, rhs: ProjectDetailInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MainDashboardView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var notificationService: NotificationService

    @State private var projectInfos: [UUID: ProjectDetailInfo] = [:]
    @State private var selectedProjectID: UUID?
    @State private var showSettings = false
    @State private var showAddProject = false
    @State private var newProjectURL = ""
    @State private var addProjectError: String?
    @State private var isAddingProject = false
    @State private var addProgressMessage = ""

    @State private var isSyncingAll = false
    @State private var syncAllTask: Task<Void, Never>?
    @State private var syncProgress = ""
    @State private var syncingProjectIDs: Set<UUID> = []

    @State private var showDeleteAlert = false
    @State private var projectToDelete: SyncProject?

    private var selectedInfo: ProjectDetailInfo? {
        guard let id = selectedProjectID else { return nil }
        return projectInfos[id]
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if projectStore.projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .frame(minWidth: 270)
        } detail: {
            if let info = selectedInfo {
                ProjectDetailView(info: info, onSync: { project in
                    Task { await syncSingleProject(project) }
                })
            } else {
                placeholderDetail
            }
        }
        .frame(minWidth: 840, minHeight: 540)
        .onAppear { loadAllProjectInfo() }
        .onChange(of: projectStore.projects.count) { _ in loadAllProjectInfo() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
                .environmentObject(networkMonitor)
                .environmentObject(notificationService)
        }
        .sheet(isPresented: $showAddProject) { addProjectSheet }
        .alert(String(localized: "删除项目"), isPresented: $showDeleteAlert) {
            Button(String(localized: "取消"), role: .cancel) { projectToDelete = nil }
            Button(String(localized: "仅删除记录")) {
                if let p = projectToDelete { projectStore.deleteProject(p); projectInfos.removeValue(forKey: p.id) }
                projectToDelete = nil
            }
            Button(String(localized: "删除记录和本地文件"), role: .destructive) {
                if let p = projectToDelete { projectStore.deleteProject(p, deleteLocalFiles: true); projectInfos.removeValue(forKey: p.id) }
                projectToDelete = nil
            }
        } message: {
            if let p = projectToDelete {
                Text(String(localized: "确定要删除「\(p.name)」吗？\n本地路径：\(p.localPath)"))
            }
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(String(localized: "项目"))
                .font(.headline)
            Spacer()

            if isSyncingAll {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(syncProgress).font(.caption2).foregroundColor(.secondary)
                }
            }

            Text("\(projectStore.projects.count)")
                .font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)

            Button {
                syncAllTask = Task { await syncAll() }
            } label: {
                Image(systemName: isSyncingAll ? "stop.circle" : "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(projectStore.projects.isEmpty || !networkMonitor.isConnected)
            .help(isSyncingAll ? String(localized: "取消同步") : String(localized: "全部同步"))

            Button { showAddProject = true } label: {
                Image(systemName: "plus").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help(String(localized: "添加项目"))

            Button { showSettings = true } label: {
                Image(systemName: "gear").font(.caption)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "设置"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36)).foregroundColor(.secondary.opacity(0.5))
            Text(String(localized: "还没有项目")).font(.title3).foregroundColor(.secondary)
            Button { showAddProject = true } label: {
                Label(String(localized: "添加第一个项目"), systemImage: "plus.circle.fill")
            }
            .controlSize(.regular).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 项目列表

    private var projectList: some View {
        List(projectStore.projects, selection: $selectedProjectID) { project in
            projectListRow(project)
                .tag(project.id)
                .contextMenu { projectContextMenu(project) }
        }
    }

    // MARK: - 详情占位

    private var placeholderDetail: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48)).foregroundColor(.secondary.opacity(0.4))
            Text(String(localized: "选择一个项目查看详情"))
                .font(.title3).foregroundColor(.secondary)
            Text(String(localized: "左侧列表点击项目，查看 README、版本、提交等详细信息"))
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func projectContextMenu(_ project: SyncProject) -> some View {
        Button {
            Task { await syncSingleProject(project) }
        } label: {
            Label(String(localized: "同步"), systemImage: "arrow.clockwise")
        }
        .disabled(!networkMonitor.isConnected || syncingProjectIDs.contains(project.id))

        Divider()

        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.localPath)
        } label: {
            Label(String(localized: "在 Finder 中打开"), systemImage: "folder")
        }

        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: project.localPath))
        } label: {
            Label(String(localized: "在终端中打开"), systemImage: "terminal")
        }

        Button {
            if let url = cleanGitHubURL(project.remoteURL) { NSWorkspace.shared.open(url) }
        } label: {
            Label(String(localized: "打开 GitHub 页面"), systemImage: "safari")
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.remoteURL, forType: .string)
        } label: {
            Label(String(localized: "复制远程地址"), systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            projectToDelete = project
            showDeleteAlert = true
        } label: {
            Label(String(localized: "删除项目"), systemImage: "trash")
        }
    }

    // MARK: - 项目列表行

    @ViewBuilder
    private func projectListRow(_ project: SyncProject) -> some View {
        let info = projectInfos[project.id]
        let isSyncing = syncingProjectIDs.contains(project.id)
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: project.syncStatus.iconName)
                    .foregroundColor(project.syncStatus.color)
                    .frame(width: 16)
                if isSyncing {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(project.name)
                        .font(.system(.body, weight: .medium)).lineLimit(1)
                    if let lang = info?.githubRepo?.language {
                        LanguageBadge(language: lang)
                    }
                }
                HStack(spacing: 6) {
                    if let local = info?.localInfo {
                        Label(local.branch, systemImage: "arrow.triangle.branch")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(local.commitHash)
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                    }
                    if let stars = info?.githubRepo?.stargazersCount, stars > 0 {
                        Label("\(stars)", systemImage: "star.fill")
                            .font(.caption2).foregroundColor(.yellow)
                    }
                }
            }
            Spacer()
            if info?.isLoading == true && !isSyncing {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 添加项目弹窗

    private var addProjectSheet: some View {
        VStack(spacing: 16) {
            Text(String(localized: "添加 Git 项目")).font(.headline)
            TextField(String(localized: "GitHub 仓库 URL（HTTPS 或 SSH）"), text: $newProjectURL)
                .textFieldStyle(.roundedBorder).disabled(isAddingProject)
            if let error = addProjectError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.red)
                }
            }
            if isAddingProject {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(addProgressMessage).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack {
                Button(String(localized: "取消")) {
                    if !isAddingProject { resetAddSheet(); showAddProject = false }
                }
                .keyboardShortcut(.cancelAction).disabled(isAddingProject)
                Button(String(localized: "添加")) { Task { await addProject() } }
                .keyboardShortcut(.defaultAction).disabled(newProjectURL.isEmpty || isAddingProject)
            }
        }
        .padding().frame(width: 460)
    }

    private func resetAddSheet() {
        newProjectURL = ""; addProjectError = nil; isAddingProject = false; addProgressMessage = ""
    }

    private func addProject() async {
        addProjectError = nil; addProgressMessage = String(localized: "解析 URL...")
        var url = newProjectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasPrefix("git@github.com:") {
            url = "https://github.com/" + url.replacingOccurrences(of: "git@github.com:", with: "")
        }
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        guard let parsed = GitHubService.parseRepoURL(url) else {
            addProjectError = String(localized: "无法解析 URL"); return
        }
        let settings = AppSettings.shared
        let localPath = settings.defaultSyncPath + "/" + parsed.name
        let localURL = URL(fileURLWithPath: localPath)
        if projectStore.projects.contains(where: { $0.localPath == localPath }) {
            addProjectError = String(localized: "该项目已添加：\(parsed.name)"); return
        }
        isAddingProject = true
        if FileManager.default.fileExists(atPath: localPath) {
            if GitService.shared.isGitRepository(at: localURL) {
                addProgressMessage = String(localized: "正在备份本地仓库...")
                let backupResult = await BackupService.shared.createBackup(sourceURL: localURL, projectName: parsed.name)
                let needsBackup: Bool
                switch backupResult { case .success: needsBackup = false; case .failure: needsBackup = true }
                addProgressMessage = String(localized: "正在导入项目...")
                let remote = await GitService.shared.remoteURL(at: localURL) ?? url
                let project = SyncProject(name: parsed.name, remoteURL: remote, localPath: localPath, owner: parsed.owner, needsInitialBackup: needsBackup)
                projectStore.addProject(project)
                isAddingProject = false; resetAddSheet(); showAddProject = false
            } else {
                isAddingProject = false; addProjectError = String(localized: "本地目录已存在但不是 Git 仓库")
            }
            return
        }
        addProgressMessage = String(localized: "正在克隆仓库...")
        let result = await GitService.shared.clone(url: url, to: localURL)
        isAddingProject = false
        switch result {
        case .success:
            let project = SyncProject(name: parsed.name, remoteURL: url, localPath: localPath, owner: parsed.owner)
            projectStore.addProject(project); resetAddSheet(); showAddProject = false
        case .failure(let error):
            addProjectError = String(localized: "克隆失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 同步操作

    private func syncAll() async {
        if isSyncingAll { syncAllTask?.cancel(); isSyncingAll = false; syncProgress = ""; return }
        isSyncingAll = true
        let syncEngine = SyncEngineFactory.shared(historyStore: historyStore, projectStore: projectStore)
        let handler = SyncResultHandler(syncEngine: syncEngine, projectStore: projectStore)
        let projects = projectStore.projects
        for (i, project) in projects.enumerated() {
            guard !Task.isCancelled else { break }
            syncProgress = "\(i + 1)/\(projects.count) \(project.name)"
            syncingProjectIDs.insert(project.id)
            _ = await handler.syncSingleProject(project)
            syncingProjectIDs.remove(project.id)
            // 刷新项目详情
            projectInfos.removeValue(forKey: project.id)
        }
        isSyncingAll = false; syncProgress = ""
        loadAllProjectInfo()
    }

    private func syncSingleProject(_ project: SyncProject) async {
        guard !syncingProjectIDs.contains(project.id) else { return }
        syncingProjectIDs.insert(project.id)
        let syncEngine = SyncEngineFactory.shared(historyStore: historyStore, projectStore: projectStore)
        let handler = SyncResultHandler(syncEngine: syncEngine, projectStore: projectStore)
        _ = await handler.syncSingleProject(project)
        syncingProjectIDs.remove(project.id)
        projectInfos.removeValue(forKey: project.id)
        await loadProjectInfo(project)
    }

    // MARK: - 数据加载（并发限制 5）

    private func loadAllProjectInfo() {
        let toLoad = projectStore.projects.filter { projectInfos[$0.id] == nil }
        guard !toLoad.isEmpty else { return }
        for p in toLoad { projectInfos[p.id] = ProjectDetailInfo(id: p.id, project: p, isLoading: true) }
        Task {
            let maxConcurrency = 5
            await withTaskGroup(of: Void.self) { group in
                var index = 0
                // 先启动 maxConcurrency 个任务
                let initialBatch = min(maxConcurrency, toLoad.count)
                for i in 0..<initialBatch {
                    let project = toLoad[i]
                    group.addTask { await self.loadProjectInfo(project) }
                }
                index = initialBatch
                // 每完成一个再启动一个
                for await _ in group {
                    if index < toLoad.count {
                        let project = toLoad[index]
                        index += 1
                        group.addTask { await self.loadProjectInfo(project) }
                    }
                }
            }
        }
    }

    private func loadProjectInfo(_ project: SyncProject) async {
        let gitService = GitService.shared
        let localInfo: GitService.LocalRepoInfo? = await withTaskGroup(of: GitService.LocalRepoInfo?.self) { group in
            group.addTask { await gitService.localRepoInfo(at: project.localURL) }
            group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000); return nil }
            let r = await group.next() ?? nil; group.cancelAll(); return r
        }
        var githubRepo: GitHubRepo?; var readme: String?
        if let parsed = GitHubService.parseRepoURL(project.remoteURL) {
            // 在进入 TaskGroup 前创建实例，避免 @MainActor 初始化上下文问题
            let gh = GitHubService()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { if case .success(let r) = await gh.fetchRepo(owner: parsed.owner, name: parsed.name) { githubRepo = r } }
                group.addTask { readme = await gh.fetchREADME(owner: parsed.owner, name: parsed.name) }
                group.addTask { try? await Task.sleep(nanoseconds: 8_000_000_000) }
                await group.next(); group.cancelAll()
            }
        }
        let info = ProjectDetailInfo(id: project.id, project: project, localInfo: localInfo, githubRepo: githubRepo, readme: readme, isLoading: false)
        await MainActor.run { projectInfos[project.id] = info }
    }

    // MARK: - 工具

    private func cleanGitHubURL(_ raw: String) -> URL? {
        var s = raw
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if s.hasPrefix("git@github.com:") { s = "https://github.com/" + s.replacingOccurrences(of: "git@github.com:", with: "") }
        return URL(string: s)
    }
}
