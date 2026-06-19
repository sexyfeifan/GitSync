// SyncHistory.swift
// 同步历史记录模型

import Foundation

/// 同步操作类型
enum SyncAction: String, Codable {
    /// 拉取远程更新
    case pull
    /// 推送本地提交
    case push
    /// 双向同步（先 pull 后 push）
    case sync
    /// 克隆仓库
    case clone
    /// 解决冲突
    case resolveConflict
}

/// 同步操作结果
enum SyncResult: String, Codable {
    /// 操作成功
    case success
    /// 操作失败
    case failure
    /// 无需操作（已是最新）
    case noChange
    /// 存在冲突
    case conflict
}

/// 同步历史记录条目
struct SyncHistoryEntry: Codable, Identifiable {
    /// 唯一标识符
    let id: UUID
    /// 关联的项目 ID
    let projectID: UUID
    /// 项目名称（冗余存储，便于显示）
    let projectName: String
    /// 同步操作类型
    let action: SyncAction
    /// 操作结果
    let result: SyncResult
    /// 操作时间
    let performedAt: Date
    /// 详细消息（错误信息或成功摘要）
    let message: String
    /// 操作耗时（秒）
    let duration: TimeInterval
    /// 操作前的 commit hash
    let fromCommit: String?
    /// 操作后的 commit hash
    let toCommit: String?

    /// 创建同步历史记录
    init(
        id: UUID = UUID(),
        projectID: UUID,
        projectName: String,
        action: SyncAction,
        result: SyncResult,
        performedAt: Date = Date(),
        message: String,
        duration: TimeInterval = 0,
        fromCommit: String? = nil,
        toCommit: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.action = action
        self.result = result
        self.performedAt = performedAt
        self.message = message
        self.duration = duration
        self.fromCommit = fromCommit
        self.toCommit = toCommit
    }

    // MARK: - 便捷属性

    /// 操作类型的中文显示名称
    var actionDisplayName: String {
        switch action {
        case .pull: return "拉取"
        case .push: return "推送"
        case .sync: return "同步"
        case .clone: return "克隆"
        case .resolveConflict: return "解决冲突"
        }
    }

    /// 操作结果的中文显示名称
    var resultDisplayName: String {
        switch result {
        case .success: return "成功"
        case .failure: return "失败"
        case .noChange: return "无变更"
        case .conflict: return "冲突"
        }
    }

    /// 操作耗时的格式化显示
    var durationFormatted: String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m\(seconds)s"
        }
    }

    /// 操作时间的格式化显示
    var performedAtFormatted: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: performedAt)
    }

    /// 是否为成功操作
    var isSuccess: Bool {
        result == .success || result == .noChange
    }
}
