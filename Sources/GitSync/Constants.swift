// Constants.swift
// 项目全局常量集中管理，消除 magic number

import Foundation

/// 应用级常量
enum AppConstants {
    // MARK: - UI 尺寸

    /// 菜单栏弹出窗口宽度
    static let menuBarWidth: CGFloat = 320
    /// 项目列表最大高度
    static let projectListMaxHeight: CGFloat = 400
    /// 空项目列表最小高度
    static let emptyListMinHeight: CGFloat = 120
    /// 设置窗口宽度
    static let settingsWidth: CGFloat = 500
    /// 设置窗口高度
    static let settingsHeight: CGFloat = 400
    /// 通用设置标签页宽度
    static let generalTabWidth: CGFloat = 400
    /// 通用设置标签页高度
    static let generalTabHeight: CGFloat = 250
    /// GitHub 设置标签页高度
    static let githubTabHeight: CGFloat = 200
    /// 项目管理标签页高度
    static let projectTabHeight: CGFloat = 300

    // MARK: - 存储键名

    /// @AppStorage 键：自动同步间隔（分钟）
    static let autoSyncIntervalKey = "autoSyncInterval"
    /// @AppStorage 键：是否启用自动同步
    static let autoSyncEnabledKey = "autoSyncEnabled"
    /// @AppStorage 键：默认同步目录
    static let defaultSyncPathKey = "defaultSyncPath"
    /// @AppStorage 键：GitHub Token
    static let githubTokenKey = "githubToken"
    /// UserDefaults 键：自动同步是否暂停
    static let autoSyncPausedKey = "autoSyncPaused"
    /// UserDefaults 键：GitHub Token（Keychain 回退）
    static let gitHubTokenUserDefaultsKey = "GitSync.GitHubToken"

    // MARK: - 同步参数

    /// 默认自动同步间隔（分钟）
    static let defaultAutoSyncInterval: Double = 5.0
    /// 最小自动同步间隔（秒）
    static let minAutoSyncIntervalSeconds: TimeInterval = 60
    /// 最大自动同步间隔（秒）
    static let maxAutoSyncIntervalSeconds: TimeInterval = 3600
    /// 默认自动同步间隔（秒）
    static let defaultAutoSyncIntervalSeconds: TimeInterval = 300
    /// 防抖延迟（秒）
    static let debounceDelay: TimeInterval = 0.5

    // MARK: - 历史记录

    /// 历史记录最大保留条数
    static let maxHistoryEntries = 1000
    /// 默认显示最近 N 条记录
    static let recentHistoryCount = 20

    // MARK: - GitHub API

    /// GitHub API 基础 URL
    static let gitHubAPIBaseURL = "https://api.github.com"
    /// GitHub Token 页面
    static let gitHubTokenURL = "https://github.com/settings/tokens"
    /// Keychain 服务名
    static let keychainServiceName = "com.gitsync.github.token"
    /// Keychain 账户名
    static let keychainAccountName = "default"
    /// HTTP User-Agent（从 Bundle.main 获取版本号）
    static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "GitSync/\(version) (\(build))"
    }()

    // MARK: - 文件路径

    /// Application Support 子目录名
    static let appSupportDirectoryName = "GitSync"
    /// 项目存储文件名
    static let projectsFileName = "projects.json"
    /// 同步历史文件名
    static let syncHistoryFileName = "sync_history.json"

    // MARK: - 通知分类

    /// 通知分类：同步完成
    static let notificationCategorySyncCompleted = "SYNC_COMPLETED"
    /// 通知分类：批量同步
    static let notificationCategoryBatchSync = "BATCH_SYNC"
    /// 通知分类：有更新
    static let notificationCategoryHasUpdate = "HAS_UPDATE"
    /// 通知分类：冲突
    static let notificationCategoryConflict = "CONFLICT"
    /// 通知分类：错误
    static let notificationCategoryError = "ERROR"
    /// 通知分类：网络
    static let notificationCategoryNetwork = "NETWORK"
}
