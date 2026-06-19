// AppResult.swift
// 统一的结果类型，替代 GitSyncResult 及其他自定义 Result 变体

import Foundation

/// 统一的应用级错误类型
/// 汇总 Git、GitHub、网络等各层错误
enum AppError: LocalizedError {
    /// Git 操作错误
    case git(GitError)
    /// GitHub API 错误
    case github(GitHubServiceError)
    /// 通用错误（携带消息）
    case generic(String)
    /// 本地目录不存在
    case pathNotFound(path: String)
    /// 不是 Git 仓库
    case notGitRepository(path: String)

    var errorDescription: String? {
        switch self {
        case .git(let error):
            return error.localizedDescription
        case .github(let error):
            return error.localizedDescription
        case .generic(let message):
            return message
        case .pathNotFound(let path):
            return String(localized: "路径不存在: \(path)")
        case .notGitRepository(let path):
            return String(localized: "不是 Git 仓库: \(path)")
        }
    }
}

/// 统一的同步结果类型
/// 替代原来的 GitSyncResult，在所有同步操作中统一使用
enum AppSyncResult {
    /// 同步成功（有新提交同步）
    case success(message: String)
    /// 已是最新，无需同步
    case upToDate
    /// 发生冲突（包含冲突描述）
    case conflict(details: String)
    /// 同步失败（包含错误信息）
    case error(message: String)

    /// 是否为成功或无需操作
    var isSuccess: Bool {
        switch self {
        case .success, .upToDate:
            return true
        case .conflict, .error:
            return false
        }
    }

    /// 提取消息文本（用于日志或显示）
    var messageText: String {
        switch self {
        case .success(let message):
            return message
        case .upToDate:
            return String(localized: "已是最新")
        case .conflict(let details):
            return String(localized: "冲突：\(details)")
        case .error(let message):
            return message
        }
    }

    /// 对应的同步状态
    var syncStatus: SyncStatus {
        switch self {
        case .success:
            return .synced
        case .upToDate:
            return .synced
        case .conflict:
            return .conflict
        case .error:
            return .error
        }
    }
}
