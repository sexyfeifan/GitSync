import Foundation

// MARK: - Git 同步结果

/// Git 同步引擎的返回结果
/// 注意：与 SyncHistory.swift 中的 SyncResult 不同，此枚举用于同步引擎的返回值
enum GitSyncResult {
    /// 同步成功（有新的提交同步）
    case success(message: String)
    /// 已是最新，无需同步
    case upToDate
    /// 发生冲突（包含冲突描述）
    case conflict(details: String)
    /// 同步失败（包含错误信息）
    case error(message: String)
}

// MARK: - 同步引擎

/// Git 同步引擎，协调本地和远程仓库的同步流程
/// 流程：fetch → 检测远端变更 → 检测本地变更 → pull/push/rebase
/// 每次同步记录到 SyncHistoryStore
final class SyncEngine {
    /// Git 服务实例
    private let gitService: GitService
    /// 同步历史存储
    private let historyStore: SyncHistoryStore

    /// 初始化同步引擎
    /// - Parameters:
    ///   - gitService: Git 服务实例，默认使用共享实例
    ///   - historyStore: 历史存储实例
    init(gitService: GitService = .shared, historyStore: SyncHistoryStore = SyncHistoryStore()) {
        self.gitService = gitService
        self.historyStore = historyStore
    }

    /// 同步指定项目
    /// 完整流程：fetch → 检测远端变更 → 检测本地变更 → 决策同步策略 → 执行同步
    /// 边界情况处理：目录不存在、不是 git 仓库、网络不可达等
    /// - Parameter project: 要同步的项目（使用 Models/SyncProject.swift 中定义的类型）
    /// - Returns: 同步结果
    func syncProject(_ project: SyncProject) async -> GitSyncResult {
        let localPath = project.localURL
        let startTime = Date()

        // 边界情况：目录不存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            let msg = String(localized: "本地目录不存在: \(localPath.path)")
            await recordSync(project: project, action: .sync, result: .failure,
                      message: msg, startTime: startTime,
                      fromCommit: nil)
            return .error(message: msg)
        }

        // 边界情况：不是 git 仓库（检查 .git 目录）
        let gitDir = localPath.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            let msg = String(localized: "不是 Git 仓库: \(localPath.path)")
            await recordSync(project: project, action: .sync, result: .failure,
                      message: msg, startTime: startTime,
                      fromCommit: nil)
            return .error(message: msg)
        }

        // 记录当前 commit hash（用于历史记录）
        let fromCommit = gitService.commitHash(at: localPath)

        // 步骤 1：获取远程最新引用
        switch gitService.fetch(at: localPath) {
        case .failure(let error):
            let msg = String(localized: "Fetch 失败: \(error.localizedDescription)")
            await recordSync(project: project, action: .sync, result: .failure,
                      message: msg, startTime: startTime,
                      fromCommit: fromCommit)
            return .error(message: msg)
        case .success:
            break
        }

        // 步骤 2：检测远端是否有变更
        let hasRemote = gitService.hasRemoteChanges(localPath: localPath)

        // 步骤 3：检测本地是否有变更
        let hasLocal = gitService.hasLocalChanges(localPath: localPath)

        // 步骤 4：根据远端和本地变更情况选择同步策略
        if !hasRemote && !hasLocal {
            // 双方都无变更，已是最新
            await recordSync(project: project, action: .sync, result: .noChange,
                      message: String(localized: "已是最新，无需同步"), startTime: startTime,
                      fromCommit: fromCommit)
            return .upToDate
        }

        if hasRemote && !hasLocal {
            // 只有远端有变更，直接 pull
            return await pullOnly(project: project, localPath: localPath, startTime: startTime, fromCommit: fromCommit)
        }

        if !hasRemote && hasLocal {
            // 只有本地有变更，直接 push
            return await pushOnly(project: project, localPath: localPath, startTime: startTime, fromCommit: fromCommit)
        }

        // 双方都有变更，先 commit 本地修改，再 rebase
        return await syncWithRebase(project: project, localPath: localPath, startTime: startTime, fromCommit: fromCommit)
    }

    // MARK: - 同步策略

    /// 仅拉取远端更新
    private func pullOnly(project: SyncProject, localPath: URL, startTime: Date, fromCommit: String?) async -> GitSyncResult {
        switch gitService.pull(at: localPath, branch: project.branch) {
        case .success(let output):
            let toCommit = gitService.commitHash(at: localPath)
            await recordSync(project: project, action: .pull, result: .success,
                      message: String(localized: "拉取成功"), startTime: startTime,
                      fromCommit: fromCommit, toCommit: toCommit)
            return .success(message: output)
        case .failure(let error):
            let msg = String(localized: "拉取失败: \(error.localizedDescription)")
            await recordSync(project: project, action: .pull, result: .failure,
                      message: msg, startTime: startTime,
                      fromCommit: fromCommit)
            return .error(message: msg)
        }
    }

    /// 仅推送本地更新
    private func pushOnly(project: SyncProject, localPath: URL, startTime: Date, fromCommit: String?) async -> GitSyncResult {
        // 先提交本地未保存的变更
        let status = gitService.status(at: localPath)
        if !status.isClean {
            let commitMessage = String(localized: "自动同步提交 - \(Self.dateFormatter.string(from: Date()))")
            let commitResult = gitService.commitAll(at: localPath, message: commitMessage)
            if case .failure(let error) = commitResult {
                let msg = String(localized: "提交本地变更失败: \(error.localizedDescription)")
                await recordSync(project: project, action: .push, result: .failure,
                          message: msg, startTime: startTime,
                          fromCommit: fromCommit)
                return .error(message: msg)
            }
        }

        switch gitService.push(at: localPath, branch: project.branch) {
        case .success(let output):
            let toCommit = gitService.commitHash(at: localPath)
            await recordSync(project: project, action: .push, result: .success,
                      message: String(localized: "推送成功"), startTime: startTime,
                      fromCommit: fromCommit, toCommit: toCommit)
            return .success(message: output)
        case .failure(let error):
            let msg = String(localized: "推送失败: \(error.localizedDescription)")
            await recordSync(project: project, action: .push, result: .failure,
                      message: msg, startTime: startTime,
                      fromCommit: fromCommit)
            return .error(message: msg)
        }
    }

    /// 双方都有变更时的同步策略：先 commit 本地，再 rebase 到远端，最后 push
    private func syncWithRebase(project: SyncProject, localPath: URL, startTime: Date, fromCommit: String?) async -> GitSyncResult {
        // 1. 先提交本地所有变更
        let status = gitService.status(at: localPath)
        if !status.isClean {
            let commitMessage = String(localized: "自动同步提交 - \(Self.dateFormatter.string(from: Date()))")
            let commitResult = gitService.commitAll(at: localPath, message: commitMessage)
            if case .failure(let error) = commitResult {
                let msg = String(localized: "提交本地变更失败: \(error.localizedDescription)")
                await recordSync(project: project, action: .sync, result: .failure,
                          message: msg, startTime: startTime,
                          fromCommit: fromCommit)
                return .error(message: msg)
            }
        }

        // 2. 尝试 rebase 到远端分支
        let remoteRef = "origin/\(project.branch)"
        switch gitService.rebase(at: localPath, onto: remoteRef) {
        case .success:
            // rebase 成功，现在推送
            switch gitService.push(at: localPath, branch: project.branch) {
            case .success(let output):
                let toCommit = gitService.commitHash(at: localPath)
                await recordSync(project: project, action: .sync, result: .success,
                          message: String(localized: "Rebase 并推送成功"), startTime: startTime,
                          fromCommit: fromCommit, toCommit: toCommit)
                return .success(message: String(localized: "Rebase 成功并已推送: \(output)"))
            case .failure(let error):
                let msg = String(localized: "推送失败（rebase 后）: \(error.localizedDescription)")
                await recordSync(project: project, action: .sync, result: .failure,
                          message: msg, startTime: startTime,
                          fromCommit: fromCommit)
                return .error(message: msg)
            }

        case .failure:
            // rebase 失败，说明有冲突
            let conflictFiles = status.conflictFiles
            let details = conflictFiles.joined(separator: ", ")
            let msg = String(localized: "冲突文件: \(details)")
            await recordSync(project: project, action: .sync, result: .conflict,
                      message: msg, startTime: startTime,
                      fromCommit: fromCommit)
            return .conflict(details: msg)
        }
    }

    // MARK: - 辅助方法

    /// 获取指定路径的 commit hash（公开给外部使用）
    func getCommitHash(at path: URL) -> String? {
        gitService.commitHash(at: path)
    }

    /// 记录同步历史到 SyncHistoryStore（异步，确保在 MainActor 上执行）
    private func recordSync(
        project: SyncProject,
        action: SyncAction,
        result: SyncResult,
        message: String,
        startTime: Date,
        fromCommit: String?,
        toCommit: String? = nil
    ) async {
        let duration = Date().timeIntervalSince(startTime)
        let store = historyStore
        let pid = project.id
        let pname = project.name
        await MainActor.run {
            store.recordSync(
                projectID: pid,
                projectName: pname,
                action: action,
                result: result,
                message: message,
                duration: duration,
                fromCommit: fromCommit,
                toCommit: toCommit
            )
        }
    }

    /// 日期格式化器（用于提交信息）
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
