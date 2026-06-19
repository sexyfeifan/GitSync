// SyncResultHandler.swift
// 统一的同步结果处理逻辑，消除三处重复的 syncSingleProject

import Foundation

/// 同步结果处理器
/// 统一处理单个项目的同步流程，包括状态更新和可选的通知
@MainActor
struct SyncResultHandler {
    private let syncEngine: SyncEngineProtocol
    private let projectStore: ProjectStore
    private let notificationService: NotificationService?

    /// 初始化结果处理器
    /// - Parameters:
    ///   - syncEngine: 同步引擎实例
    ///   - projectStore: 项目存储
    ///   - notificationService: 通知服务（可选，自动同步时传入以发送通知）
    init(
        syncEngine: SyncEngineProtocol,
        projectStore: ProjectStore,
        notificationService: NotificationService? = nil
    ) {
        self.syncEngine = syncEngine
        self.projectStore = projectStore
        self.notificationService = notificationService
    }

    /// 同步单个项目并统一处理结果
    /// - Parameters:
    ///   - project: 要同步的项目
    ///   - syncingMessage: 同步中的提示文字
    /// - Returns: 同步结果
    func syncSingleProject(
        _ project: SyncProject,
        syncingMessage: String = String(localized: "同步中...")
    ) async -> AppSyncResult {
        projectStore.updateSyncStatus(
            for: project.id,
            status: .syncing,
            message: syncingMessage
        )

        let result = await syncEngine.syncProject(project)

        switch result {
        case .success(let message):
            projectStore.updateSyncStatus(
                for: project.id,
                status: .synced,
                message: message
            )
            notificationService?.postSyncCompleted(
                projectName: project.name,
                message: message
            )
        case .upToDate:
            projectStore.updateSyncStatus(
                for: project.id,
                status: .synced,
                message: String(localized: "已是最新")
            )
        case .conflict(let details):
            projectStore.updateSyncStatus(
                for: project.id,
                status: .conflict,
                message: String(localized: "冲突：\(details)")
            )
        case .error(let message):
            projectStore.updateSyncStatus(
                for: project.id,
                status: .error,
                message: message
            )
        }

        return result
    }
}
