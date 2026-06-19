// NotificationService.swift
// 系统通知服务，使用 UNUserNotificationCenter 发送 macOS 通知

import Foundation
import UserNotifications
import SwiftUI
import os

/// 通知偏好设置
/// 控制应用发送通知的行为
enum NotificationPreference: String, CaseIterable {
    /// 全部通知（同步完成、错误、网络变化等）
    case all
    /// 仅失败时通知（仅错误和冲突）
    case failuresOnly
    /// 关闭所有通知
    case off

    /// 显示名称
    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部通知")
        case .failuresOnly:
            return String(localized: "仅失败时通知")
        case .off:
            return String(localized: "关闭通知")
        }
    }
}

/// 系统通知服务
/// 封装 UNUserNotificationCenter，提供同步相关通知功能
@MainActor
class NotificationService: ObservableObject {
    /// 通知中心实例
    private let center = UNUserNotificationCenter.current()

    /// 用户是否已授权发送通知
    @Published private(set) var isAuthorized: Bool = false

    /// 通知偏好设置（从 UserDefaults 读写）
    @AppStorage("notificationPreference")
    var preference: NotificationPreference = .all

    init() {
        requestAuthorization()
    }

    // MARK: - 权限管理

    /// 请求通知权限
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
            }
        }
    }

    // MARK: - 通知发送

    /// 发送同步完成通知
    func postSyncCompleted(projectName: String, message: String) {
        // 仅在全部通知模式下发送成功通知
        guard preference == .all else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "同步完成")
        content.subtitle = projectName
        content.body = message
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategorySyncCompleted

        sendNotification(content: content, identifier: "sync-completed-\(projectName)")
    }

    /// 发送批量同步完成通知
    func postBatchSyncCompleted(totalCount: Int, successCount: Int, failureCount: Int) {
        // 仅失败时通知模式：只在有失败时发送
        if preference == .failuresOnly && failureCount == 0 { return }
        // 关闭通知模式：不发送任何通知
        if preference == .off { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "批量同步完成")
        content.body = String(localized: "共 \(totalCount) 个项目，成功 \(successCount) 个，失败 \(failureCount) 个")
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryBatchSync

        if failureCount > 0 {
            content.title = String(localized: "批量同步完成（有失败）")
            content.sound = .default
        }

        sendNotification(content: content, identifier: "batch-sync-completed")
    }

    /// 发送有更新通知
    func postHasUpdate(projectName: String, updateCount: Int = 1) {
        // 仅在全部通知模式下发送更新通知
        guard preference == .all else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "有新更新")
        content.subtitle = projectName
        content.body = String(localized: "远程仓库有 \(updateCount) 个新提交，可拉取更新")
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryHasUpdate

        sendNotification(content: content, identifier: "has-update-\(projectName)")
    }

    /// 发送冲突通知
    func postConflict(projectName: String, conflictFiles: [String]) {
        // 关闭通知模式：不发送任何通知
        guard preference != .off else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "⚠️ 同步冲突")
        content.subtitle = projectName
        content.body = String(localized: "检测到 \(conflictFiles.count) 个冲突文件：\(conflictFiles.prefix(3).joined(separator: "、"))")
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryConflict

        sendNotification(content: content, identifier: "conflict-\(projectName)")
    }

    /// 发送错误通知
    func postError(projectName: String? = nil, errorMessage: String) {
        // 关闭通知模式：不发送任何通知
        guard preference != .off else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "同步错误")
        if let projectName = projectName {
            content.subtitle = projectName
        }
        content.body = errorMessage
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryError

        sendNotification(content: content, identifier: "error-\(projectName ?? "global")")
    }

    /// 发送网络断开通知
    func postNetworkDisconnected() {
        // 关闭通知模式：不发送任何通知
        guard preference != .off else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "网络已断开")
        content.body = String(localized: "自动同步已暂停，网络恢复后将自动继续")
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryNetwork

        sendNotification(content: content, identifier: "network-disconnected")
    }

    /// 发送网络恢复通知
    func postNetworkRestored() {
        // 关闭通知模式：不发送任何通知
        guard preference != .off else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "网络已恢复")
        content.body = String(localized: "自动同步已恢复")
        content.sound = .default
        content.categoryIdentifier = AppConstants.notificationCategoryNetwork

        sendNotification(content: content, identifier: "network-restored")
    }

    // MARK: - 通知管理

    /// 清除所有已发送的通知
    func clearAllNotifications() {
        center.removeAllDeliveredNotifications()
    }

    /// 清除指定标识符的通知
    func clearNotification(identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // MARK: - 私有方法

    /// 发送通知请求
    private func sendNotification(content: UNMutableNotificationContent, identifier: String) {
        // 先移除已发送的同标识符通知，确保新通知替换旧通知
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                Log.notification.error("发送通知失败: \(error.localizedDescription)")
            }
        }
    }
}
