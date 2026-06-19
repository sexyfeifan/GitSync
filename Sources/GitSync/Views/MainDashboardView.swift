// MainDashboardView.swift
// 主界面：项目仪表盘，展示所有已添加项目的详细状态

import SwiftUI

/// 项目聚合信息（本地 Git + GitHub API）
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

    private var selectedInfo: ProjectDetailInfo? {
        guard let id = selectedProjectID else { return nil }
        return projectInfos[id]
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // 顶部工具栏
                HStack {
                    Text(String(localized: "项目"))
                        .font(.headline)
                    Spacer()
                    Text("\(projectStore.projects.count)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                    Button {
                        showAddProject = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "添加项目"))
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "设置"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                if projectStore.projects.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(String(localized: "还没有项目"))
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Button {
                            showAddProject = true
                        } label: {
                            Label(String(localized: "添加第一个项目"), systemImage: "plus.circle.fill")
                        }
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(projectStore.projects, selection: $selectedProjectID) { project in
                        projectListRow(project)
                            .tag(project.id)
                    }
                }
            }
            .frame(minWidth: 260)
        } detail: {
            if let info = selectedInfo {
                ProjectDetailView(info: info)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(String(localized: "选择一个项目查看详情"))
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text(String(localized: "左侧列表点击项目，查看 README、版本、提交等详细信息"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear { loadAllProjectInfo() }
        .onChange(of: projectStore.projects.count) { _ in loadAllProjectInfo() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
                .environmentObject(networkMonitor)
                .environmentObject(notificationService)
        }
        .sheet(isPresented: $showAddProject) {
            addProjectSheet
        }
    }

    // MARK: - 添加项目弹窗

    private var addProjectSheet: some View {
        VStack(spacing: 16) {
            Text(String(localized: "添加 Git 项目"))
                .font(.headline)
            TextField(String(localized: "GitHub 仓库 URL（HTTPS 或 SSH）"), text: $newProjectURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isAddingProject)

            if let error = addProjectError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.red)
                }
            }

            if isAddingProject {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(addProgressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button(String(localized: "取消")) {
                    if !isAddingProject {
                        resetAddSheet()
                        showAddProject = false
                    }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isAddingProject)

                Button(String(localized: "添加")) {
                    Task { await addProject() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProjectURL.isEmpty || isAddingProject)
            }
        }
        .padding()
        .frame(width: 460)
    }

    private func resetAddSheet() {
        newProjectURL = ""
        addProjectError = nil
        isAddingProject = false
        addProgressMessage = ""
    }

    private func addProject() async {
        addProjectError = nil
        addProgressMessage = String(localized: "解析 URL...")

        var url = newProjectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasPrefix("git@github.com:") {
            url = "https://github.com/" + url.replacingOccurrences(of: "git@github.com:", with: "")
        }
        while url.hasSuffix("/") { url = String(url.dropLast()) }

        guard let parsed = GitHubService.parseRepoURL(url) else {
            addProjectError = String(localized: "无法解析 URL，请输入有效的 GitHub 仓库地址")
            return
        }

        let settings = AppSettings.shared
        let localPath = settings.defaultSyncPath + "/" + parsed.name
        let localURL = URL(fileURLWithPath: localPath)

        if projectStore.projects.contains(where: { $0.localPath == localPath }) {
            addProjectError = String(localized: "该项目已添加：\(parsed.name)")
            return
        }

        isAddingProject = true

        if FileManager.default.fileExists(atPath: localPath) {
            if GitService.shared.isGitRepository(at: localURL) {
                addProgressMessage = String(localized: "正在备份本地仓库...")
                let backupResult = await BackupService.shared.createBackup(sourceURL: localURL, projectName: parsed.name)
                let needsBackup: Bool
                switch backupResult {
                case .success: needsBackup = false
                case .failure: needsBackup = true
                }
                addProgressMessage = String(localized: "正在导入项目...")
                let remote = await GitService.shared.remoteURL(at: localURL) ?? url
                let project = SyncProject(name: parsed.name, remoteURL: remote, localPath: localPath, owner: parsed.owner, needsInitialBackup: needsBackup)
                projectStore.addProject(project)
                isAddingProject = false
                resetAddSheet()
                showAddProject = false
            } else {
                isAddingProject = false
                addProjectError = String(localized: "本地目录已存在但不是 Git 仓库")
            }
            return
        }

        addProgressMessage = String(localized: "正在克隆仓库...")
        let result = await GitService.shared.clone(url: url, to: localURL)
        isAddingProject = false

        switch result {
        case .success:
            let project = SyncProject(name: parsed.name, remoteURL: url, localPath: localPath, owner: parsed.owner)
            projectStore.addProject(project)
            resetAddSheet()
            showAddProject = false
        case .failure(let error):
            addProjectError = String(localized: "克隆失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 项目列表行

    @ViewBuilder
    private func projectListRow(_ project: SyncProject) -> some View {
        let info = projectInfos[project.id]
        HStack(spacing: 10) {
            Image(systemName: project.syncStatus.iconName)
                .foregroundColor(project.syncStatus.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(project.name)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)
                    if let lang = info?.githubRepo?.language {
                        LanguageBadge(language: lang)
                    }
                }
                HStack(spacing: 6) {
                    if let local = info?.localInfo {
                        Label(local.branch, systemImage: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(local.commitHash)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if let stars = info?.githubRepo?.stargazersCount, stars > 0 {
                        Label("\(stars)", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
            }
            Spacer()
            if info?.isLoading == true {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 数据加载（并发限制 5）

    private func loadAllProjectInfo() {
        let projectsToLoad = projectStore.projects.filter { projectInfos[$0.id] == nil }
        guard !projectsToLoad.isEmpty else { return }

        for project in projectsToLoad {
            projectInfos[project.id] = ProjectDetailInfo(id: project.id, project: project, isLoading: true)
        }

        Task {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                let maxConcurrency = 5
                var iterator = projectsToLoad.makeIterator()

                while running < maxConcurrency, let project = iterator.next() {
                    running += 1
                    group.addTask {
                        await loadProjectInfo(project)
                        running -= 1
                    }
                }
                // 等待每个完成后启动下一个
                for await _ in group {
                    if let project = iterator.next() {
                        running += 1
                        group.addTask {
                            await loadProjectInfo(project)
                            running -= 1
                        }
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
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }

        var githubRepo: GitHubRepo?
        var readme: String?

        if let parsed = GitHubService.parseRepoURL(project.remoteURL) {
            let gh = GitHubService()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    if case .success(let repo) = await gh.fetchRepo(owner: parsed.owner, name: parsed.name) {
                        githubRepo = repo
                    }
                }
                group.addTask { readme = await gh.fetchREADME(owner: parsed.owner, name: parsed.name) }
                group.addTask { try? await Task.sleep(nanoseconds: 8_000_000_000) }
                await group.next()
                group.cancelAll()
            }
        }

        let info = ProjectDetailInfo(
            id: project.id, project: project,
            localInfo: localInfo, githubRepo: githubRepo, readme: readme,
            isLoading: false
        )

        await MainActor.run {
            projectInfos[project.id] = info
        }
    }
}
