// SyncProject.swift
// Git 同步项目数据模型

import Foundation

/// Git 同步项目，表示一个本地 Git 仓库及其远程关联
struct SyncProject: Codable, Identifiable, Equatable {
    /// 唯一标识符
    let id: UUID
    /// 仓库名称（通常为目录名）
    var name: String
    /// 远程仓库 URL（GitHub 地址）
    var remoteURL: String
    /// 本地仓库路径
    var localPath: String
    /// GitHub 用户名（仓库所有者）
    var owner: String
    /// 是否为自己的仓库（非 Fork）
    var isOwnRepo: Bool
    /// Fork 源仓库（格式: owner/repo），nil 表示非 Fork
    var forkedFrom: String?
    /// 当前同步状态
    var syncStatus: SyncStatus
    /// 最后同步时间
    var lastSyncAt: Date?
    /// 最后同步结果消息
    var lastSyncMessage: String
    /// 当前分支名称
    var branch: String

    /// 创建新项目
    init(
        id: UUID = UUID(),
        name: String,
        remoteURL: String,
        localPath: String,
        owner: String,
        isOwnRepo: Bool = true,
        forkedFrom: String? = nil,
        syncStatus: SyncStatus = .notSynced,
        lastSyncAt: Date? = nil,
        lastSyncMessage: String = "",
        branch: String = "main"
    ) {
        self.id = id
        self.name = name
        self.remoteURL = remoteURL
        self.localPath = localPath
        self.owner = owner
        self.isOwnRepo = isOwnRepo
        self.forkedFrom = forkedFrom
        self.syncStatus = syncStatus
        self.lastSyncAt = lastSyncAt
        self.lastSyncMessage = lastSyncMessage
        self.branch = branch
    }

    // MARK: - 便捷属性

    /// 仓库全名（owner/name）
    var fullName: String {
        "\(owner)/\(name)"
    }

    /// 是否为 Fork 仓库
    var isFork: Bool {
        forkedFrom != nil
    }

    /// 最后同步时间的格式化显示
    var lastSyncAtFormatted: String {
        guard let date = lastSyncAt else {
            return "从未同步"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// 本地路径的 URL 表示
    var localURL: URL {
        URL(fileURLWithPath: localPath)
    }
}
