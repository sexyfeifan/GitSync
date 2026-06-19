// NotificationService.swift
// 系统通知服务，使用 UNUserNotificationCenter 发送 macOS 通知

import Foundation
import UserNotifications

/// 系统通知服务
/// 封装 UNUserNotificationCenter，提供同步相关通知功能
@MainActor
class NotificationService: ObservableObject {
    /// 通知中心实例
    private let center = UNUserNotificationCenter.current()

    /// 用户是否已授权发送通知
    @Published private(set) var isAuthorized: Bool = false

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
    /// - Parameters:
    ///   - projectName: 项目名称
    ///   - message: 同步结果消息
    func postSyncCompleted(projectName: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "同步完成"
        content.subtitle = projectName
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "SYNC_COMPLETED"

        sendNotification(content: content, identifier: "sync-completed-\(projectName)-\(UUID().uuidString)")
    }

    /// 发送批量同步完成通知
    /// - Parameters:
    ///   - totalCount: 总同步项目数
    ///   - successCount: 成功数量
    ///   - failureCount: 失败数量
    func postBatchSyncCompleted(totalCount: Int, successCount: Int, failureCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "批量同步完成"
        content.body = "共 \(totalCount) 个项目，成功 \(successCount) 个，失败 \(failureCount) 个"
        content.sound = .default
        content.categoryIdentifier = "BATCH_SYNC"

        if failureCount > 0 {
            content.title = "批量同步完成（有失败）"
            content.sound = .defaultCritical
        }

        sendNotification(content: content, identifier: "batch-sync-\(UUID().uuidString)")
    }

    /// 发送有更新通知
    /// - Parameters:
    ///   - projectName: 项目名称
    ///   - updateCount: 更新数量
    func postHasUpdate(projectName: String, updateCount: Int = 1) {
        let content = UNMutableNotificationContent()
        content.title = "有新更新"
        content.subtitle = projectName
        content.body = "远程仓库有 \(updateCount) 个新提交，可拉取更新"
        content.sound = .default
        content.categoryIdentifier = "HAS_UPDATE"

        sendNotification(content: content, identifier: "has-update-\(projectName)")
    }

    /// 发送冲突通知
    /// - Parameters:
    ///   - projectName: 项目名称
    ///   - conflictFiles: 冲突文件列表
    func postConflict(projectName: String, conflictFiles: [String]) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ 同步冲突"
        content.subtitle = projectName
        content.body = "检测到 \(conflictFiles.count) 个冲突文件：\(conflictFiles.prefix(3).joined(separator: "、"))"
        content.sound = .defaultCritical
        content.categoryIdentifier = "CONFLICT"

        sendNotification(content: content, identifier: "conflict-\(projectName)")
    }

    /// 发送错误通知
    /// - Parameters:
    ///   - projectName: 项目名称（可选）
    ///   - errorMessage: 错误消息
    func postError(projectName: String? = nil, errorMessage: String) {
        let content = UNMutableNotificationContent()
        content.title = "同步错误"
        if let projectName = projectName {
            content.subtitle = projectName
        }
        content.body = errorMessage
        content.sound = .defaultCritical
        content.categoryIdentifier = "ERROR"

        sendNotification(content: content, identifier: "error-\(projectName ?? "global")-\(UUID().uuidString)")
    }

    /// 发送网络断开通知
    func postNetworkDisconnected() {
        let content = UNMutableNotificationContent()
        content.title = "网络已断开"
        content.body = "自动同步已暂停，网络恢复后将自动继续"
        content.sound = .default
        content.categoryIdentifier = "NETWORK"

        sendNotification(content: content, identifier: "network-disconnected")
    }

    /// 发送网络恢复通知
    func postNetworkRestored() {
        let content = UNMutableNotificationContent()
        content.title = "网络已恢复"
        content.body = "自动同步已恢复"
        content.sound = .default
        content.categoryIdentifier = "NETWORK"

        sendNotification(content: content, identifier: "network-restored")
    }

    // MARK: - 通知管理

    /// 清除所有已发送的通知
    func clearAllNotifications() {
        center.removeAllDeliveredNotifications()
    }

    /// 清除指定标识符的通知
    /// - Parameter identifier: 通知标识符
    func clearNotification(identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // MARK: - 私有方法

    /// 发送通知请求
    /// - Parameters:
    ///   - content: 通知内容
    ///   - identifier: 通知标识符（用于去重和管理）
    private func sendNotification(content: UNMutableNotificationContent, identifier: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("发送通知失败: \(error.localizedDescription)")
            }
        }
    }
}
