// AppViewModel.swift
// GitSync 主 ViewModel — 连接 UI 和 Services

import SwiftUI
import Combine

@MainActor
class AppViewModel: ObservableObject {
    @Published var projectStore: ProjectStore
    @Published var historyStore: SyncHistoryStore
    @Published var selectedProjectID: UUID?
    @Published var isSyncing = false
    @Published var statusText = ""
    @Published var showingAddSheet = false

    private let gitService = GitService()
    private let gitHubService: GitHubService
    private let syncEngine: SyncEngine

    init(projectStore: ProjectStore = ProjectStore(), historyStore: SyncHistoryStore = SyncHistoryStore()) {
        self.projectStore = projectStore
        self.historyStore = historyStore
        self.gitHubService = GitHubService()
        self.syncEngine = SyncEngine(gitService: GitService(), historyStore: historyStore)
    }

    var selectedProject: SyncProject? {
        guard let id = selectedProjectID else { return nil }
        return projectStore.project(byID: id)
    }

    // MARK: - 添加项目

    func addProject(urlString: String, localBasePath: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "请输入 GitHub 仓库 URL"
            return
        }

        guard let (owner, name) = GitHubService.parseRepoURL(trimmed) else {
            statusText = "无法解析 URL：\(trimmed)"
            return
        }

        statusText = "正在检查仓库..."
        let localPath = (localBasePath as NSString).appendingPathComponent(name)

        // 检查是否自己的仓库
        let isOwn = await gitHubService.checkIsOwnRepo(owner: owner)
        var forkedFrom: String? = nil
        var finalOwner = owner

        if !isOwn {
            statusText = "不是自己的仓库，正在 Fork..."
            if let fork = await gitHubService.forkRepo(owner: owner, name: name) {
                finalOwner = fork.owner
                forkedFrom = "\(owner)/\(name)"
                statusText = "Fork 成功：\(fork.fullName)"
            } else {
                statusText = "Fork 失败，将直接使用原仓库"
            }
        }

        let remoteURL = "https://github.com/\(finalOwner)/\(name).git"
        let project = SyncProject(
            name: name,
            remoteURL: remoteURL,
            localPath: localPath,
            owner: finalOwner,
            isOwnRepo: isOwn || forkedFrom != nil,
            forkedFrom: forkedFrom,
            syncStatus: .notSynced,
            lastSyncAt: nil,
            lastSyncMessage: "等待首次同步",
            branch: "main"
        )

        projectStore.addProject(project)
        statusText = "项目已添加：\(name)"
        selectedProjectID = project.id

        // 自动首次同步
        await syncProject(project)
    }

    // MARK: - 同步

    func syncProject(_ project: SyncProject) async {
        isSyncing = true
        statusText = "正在同步 \(project.name)..."

        projectStore.updateSyncStatus(for: project.id, status: .syncing, message: "同步中...")

        let result = await syncEngine.syncProject(project)

        switch result {
        case .success(let message):
            projectStore.updateSyncStatus(for: project.id, status: .synced, message: message)
            statusText = "\(project.name) 同步完成"
        case .upToDate:
            projectStore.updateSyncStatus(for: project.id, status: .synced, message: "已是最新")
            statusText = "\(project.name) 已是最新"
        case .conflict(let details):
            projectStore.updateSyncStatus(for: project.id, status: .conflict, message: "冲突：\(details)")
            statusText = "\(project.name) 有冲突"
        case .error(let message):
            projectStore.updateSyncStatus(for: project.id, status: .error, message: message)
            statusText = "\(project.name) 同步失败：\(message)"
        }

        isSyncing = false
    }

    func syncAll() async {
        isSyncing = true
        statusText = "正在同步全部项目..."

        for project in projectStore.projects {
            await syncProject(project)
        }

        statusText = "全部同步完成"
        isSyncing = false
    }

    // MARK: - Git 操作

    func pullProject(_ project: SyncProject) async {
        isSyncing = true
        statusText = "正在拉取 \(project.name)..."
        let result = gitService.pull(at: URL(fileURLWithPath: project.localPath), branch: project.branch)
        switch result {
        case .success(let msg):
            projectStore.updateSyncStatus(for: project.id, status: .synced, message: msg)
            statusText = "拉取完成：\(msg)"
        case .failure(let err):
            statusText = "拉取失败：\(err.localizedDescription)"
        }
        isSyncing = false
    }

    func pushProject(_ project: SyncProject) async {
        isSyncing = true
        statusText = "正在推送 \(project.name)..."
        let result = gitService.push(at: URL(fileURLWithPath: project.localPath), branch: project.branch)
        switch result {
        case .success(let msg):
            projectStore.updateSyncStatus(for: project.id, status: .synced, message: msg)
            statusText = "推送完成：\(msg)"
        case .failure(let err):
            statusText = "推送失败：\(err.localizedDescription)"
        }
        isSyncing = false
    }

    func commitAndPush(_ project: SyncProject, message: String) async {
        isSyncing = true
        statusText = "正在提交 \(project.name)..."

        let commitResult = gitService.commitAll(at: URL(fileURLWithPath: project.localPath), message: message)
        switch commitResult {
        case .success:
            let pushResult = gitService.push(at: URL(fileURLWithPath: project.localPath), branch: project.branch)
            switch pushResult {
            case .success(let msg):
                projectStore.updateSyncStatus(for: project.id, status: .synced, message: msg)
                statusText = "提交并推送完成"
            case .failure(let err):
                statusText = "推送失败：\(err.localizedDescription)"
            }
        case .failure(let err):
            statusText = "提交失败：\(err.localizedDescription)"
        }

        isSyncing = false
    }

    // MARK: - 检测状态

    func detectStatus(for project: SyncProject) {
        let hasRemote = gitService.hasRemoteChanges(localPath: project.localPath)
        let hasLocal = gitService.hasLocalChanges(localPath: project.localPath)
        let hasConflict = gitService.detectConflict(at: URL(fileURLWithPath: project.localPath))

        let newStatus: SyncStatus
        if hasConflict {
            newStatus = .conflict
        } else if hasRemote && hasLocal {
            newStatus = .hasUpdate
        } else if hasRemote {
            newStatus = .hasUpdate
        } else if hasLocal {
            newStatus = .localAhead
        } else {
            newStatus = .synced
        }

        projectStore.updateSyncStatus(for: project.id, status: newStatus)
    }

    func detectAllStatuses() {
        for project in projectStore.projects {
            detectStatus(for: project)
        }
    }

    // MARK: - 文件操作

    func openInFinder(_ project: SyncProject) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.localPath)
    }

    func openInTerminal(_ project: SyncProject) {
        NSWorkspace.shared.open(URL(fileURLWithPath: project.localPath))
    }

    func copyURL(_ project: SyncProject) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.remoteURL, forType: .string)
    }

    func deleteProject(_ project: SyncProject) {
        projectStore.deleteProject(project)
        if selectedProjectID == project.id {
            selectedProjectID = nil
        }
    }
}
