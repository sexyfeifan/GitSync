// AppSettings.swift
// 集中管理所有 @AppStorage 设置，避免分散在各视图中

import Foundation
import SwiftUI

/// 应用全局设置管理器
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - @AppStorage 设置

    @AppStorage(AppConstants.autoSyncIntervalKey)
    var autoSyncInterval: Double = AppConstants.defaultAutoSyncInterval

    @AppStorage(AppConstants.autoSyncEnabledKey)
    var autoSyncEnabled: Bool = true

    @AppStorage(AppConstants.defaultSyncPathKey)
    var defaultSyncPath: String = NSHomeDirectory() + "/GitHub"

    @AppStorage(AppConstants.backupPathKey)
    var backupPath: String = NSHomeDirectory() + "/GitSync-Backups"

    @AppStorage(AppConstants.showDockIconKey)
    var showDockIcon: Bool = true

    @AppStorage(AppConstants.launchAtLoginKey)
    var launchAtLogin: Bool = false

    // MARK: - GitHub Token（仅 Keychain，不存 UserDefaults）

    /// Token 仅存储在 Keychain，@Published 驱动 UI 更新
    @Published var githubToken: String = ""

    /// 自动同步间隔（秒），带边界保护
    var autoSyncIntervalSeconds: TimeInterval {
        let seconds = autoSyncInterval * 60.0
        guard seconds >= AppConstants.minAutoSyncIntervalSeconds,
              seconds <= AppConstants.maxAutoSyncIntervalSeconds else {
            return AppConstants.defaultAutoSyncIntervalSeconds
        }
        return seconds
    }

    private init() {
        // 启动时从 Keychain 加载 Token
        self.githubToken = GitHubService.loadTokenFromKeychain() ?? ""
    }

    /// 保存 Token 到 Keychain 并更新内存
    func saveToken(_ token: String) {
        githubToken = token
        GitHubService.saveTokenToKeychain(token)
    }

    /// 清除 Token
    func clearToken() {
        githubToken = ""
        GitHubService.deleteTokenFromKeychain()
    }
}
