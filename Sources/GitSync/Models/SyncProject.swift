// SyncProject.swift
// Git 同步项目数据模型

import Foundation

/// Git 同步项目，表示一个本地 Git 仓库及其远程关联
struct SyncProject: Codable, Identifiable, Equatable {
    // MARK: - CodingKeys（支持向后兼容，新字段均为 optional）
    /// JSON 编解码键映射，确保新增字段不会破坏旧数据加载
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case remoteURL
        case localPath
        case owner
        case isOwnRepo
        case forkedFrom
        case syncStatus
        case lastSyncAt
        case lastSyncMessage
        case branch
        case needsInitialBackup
        case initialBackupDone
    }

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
    /// 是否需要首次同步前备份（导入已有本地仓库时设为 true）
    var needsInitialBackup: Bool
    /// 首次备份是否已完成
    var initialBackupDone: Bool

    // MARK: - 静态缓存的格式化器

    /// 相对时间格式化器（静态缓存，避免每次调用都创建新实例）
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter
    }()

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
        branch: String = "main",
        needsInitialBackup: Bool = false,
        initialBackupDone: Bool = false
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
        self.needsInitialBackup = needsInitialBackup
        self.initialBackupDone = initialBackupDone
    }

    /// 自定义解码，支持向后兼容（新字段缺失时使用默认值）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        remoteURL = try container.decode(String.self, forKey: .remoteURL)
        localPath = try container.decode(String.self, forKey: .localPath)
        owner = try container.decode(String.self, forKey: .owner)
        // 以下字段使用 decodeIfPresent + 默认值，支持旧版本数据
        isOwnRepo = try container.decodeIfPresent(Bool.self, forKey: .isOwnRepo) ?? true
        forkedFrom = try container.decodeIfPresent(String.self, forKey: .forkedFrom)
        syncStatus = try container.decodeIfPresent(SyncStatus.self, forKey: .syncStatus) ?? .notSynced
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastSyncMessage = try container.decodeIfPresent(String.self, forKey: .lastSyncMessage) ?? ""
        branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? "main"
        needsInitialBackup = try container.decodeIfPresent(Bool.self, forKey: .needsInitialBackup) ?? false
        initialBackupDone = try container.decodeIfPresent(Bool.self, forKey: .initialBackupDone) ?? false
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

    /// 最后同步时间的格式化显示（使用静态缓存的格式化器）
    var lastSyncAtFormatted: String {
        guard let date = lastSyncAt else {
            return String(localized: "从未同步")
        }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// 本地路径的 URL 表示
    var localURL: URL {
        URL(fileURLWithPath: localPath)
    }
}
