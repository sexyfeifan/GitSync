// AppSettings.swift
// 集中管理所有 @AppStorage 设置，避免分散在各视图中

import Foundation
import SwiftUI

/// 应用全局设置管理器
/// 将散落在各视图中的 @AppStorage 集中到此 ObservableObject
final class AppSettings: ObservableObject {
    /// 共享实例
    static let shared = AppSettings()

    // MARK: - 同步设置

    /// 自动同步间隔（分钟）
    @AppStorage(AppConstants.autoSyncIntervalKey)
    var autoSyncInterval: Double = AppConstants.defaultAutoSyncInterval

    /// 是否启用自动同步
    @AppStorage(AppConstants.autoSyncEnabledKey)
    var autoSyncEnabled: Bool = true

    /// 默认同步目录
    @AppStorage(AppConstants.defaultSyncPathKey)
    var defaultSyncPath: String = NSHomeDirectory() + "/GitHub"

    /// GitHub Personal Access Token
    @AppStorage(AppConstants.githubTokenKey)
    var githubToken: String = ""

    // MARK: - 便捷属性

    /// 自动同步间隔（秒），带边界保护
    var autoSyncIntervalSeconds: TimeInterval {
        let seconds = autoSyncInterval * 60.0
        guard seconds >= AppConstants.minAutoSyncIntervalSeconds,
              seconds <= AppConstants.maxAutoSyncIntervalSeconds else {
            return AppConstants.defaultAutoSyncIntervalSeconds
        }
        return seconds
    }

    private init() {}
}
