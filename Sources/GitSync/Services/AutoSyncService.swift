// AutoSyncService.swift
// 自动同步服务，使用 Timer 定期同步所有项目

import Foundation
import Combine
import SwiftUI

/// 菜单栏应用状态，用于驱动状态栏图标变化
enum SyncAppStatus: Equatable {
    /// 正常空闲
    case idle
    /// 正在同步中
    case syncing
    /// 有项目存在更新
    case hasUpdate
    /// 有项目存在冲突
    case conflict
    /// 无网络连接
    case noNetwork
}

/// 自动同步服务
/// 定时扫描所有项目并执行同步，检查网络状态，同步完成后发送通知
@MainActor
class AutoSyncService: ObservableObject {
    // MARK: - 依赖

    /// 项目存储
    private let projectStore: ProjectStore
    /// 同步历史存储
    private let historyStore: SyncHistoryStore
    /// 通知服务
    private let notificationService: NotificationService
    /// 网络监控
    private let networkMonitor: NetworkMonitor
    /// Git 同步引擎
    private let syncEngine: SyncEngine

    // MARK: - 发布状态

    /// 当前应用状态（驱动菜单栏图标变化）
    @Published var appStatus: SyncAppStatus = .idle

    /// 是否已暂停同步
    @Published var isPaused: Bool = false {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: "autoSyncPaused")
            if isPaused {
                stopTimer()
            } else {
                startTimer()
            }
        }
    }

    /// 今日同步次数
    @Published var todaySyncCount: Int = 0

    /// 今日推送次数
    @Published var todayPushCount: Int = 0

    /// 今日冲突次数
    @Published var todayConflictCount: Int = 0

    // MARK: - 私有状态

    /// 自动同步定时器
    private var syncTimer: Timer?

    /// 自动同步间隔（秒）
    /// 注意：设置界面存储的是分钟值（1/5/15/60），需要乘以 60 转换为秒
    private var autoSyncInterval: TimeInterval {
        let minutes = UserDefaults.standard.double(forKey: "autoSyncInterval")
        // 默认 5 分钟 = 300 秒
        guard minutes > 0 else { return 300 }
        return (minutes * 60.0).clamped(to: 60...3600, defaultValue: 300)
    }

    /// 自动同步是否启用
    private var autoSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoSyncEnabled") as? Bool ?? true
    }

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    /// 创建自动同步服务
    /// - Parameters:
    ///   - projectStore: 项目存储
    ///   - historyStore: 历史存储
    ///   - notificationService: 通知服务
    ///   - networkMonitor: 网络监控
    init(
        projectStore: ProjectStore,
        historyStore: SyncHistoryStore,
        notificationService: NotificationService,
        networkMonitor: NetworkMonitor
    ) {
        self.projectStore = projectStore
        self.historyStore = historyStore
        self.notificationService = notificationService
        self.networkMonitor = networkMonitor
        self.syncEngine = SyncEngine(gitService: .shared, historyStore: historyStore)

        // 恢复暂停状态
        self.isPaused = UserDefaults.standard.bool(forKey: "autoSyncPaused")

        setupBindings()
        updateStats()

        // 启动定时器（如果未暂停且已启用）
        if autoSyncEnabled && !isPaused {
            startTimer()
        }
    }

    // MARK: - 绑定设置

    /// 设置响应式绑定
    private func setupBindings() {
        // 监听网络状态变化
        networkMonitor.onNetworkStatusChanged = { [weak self] isConnected in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !isConnected {
                    self.appStatus = .noNetwork
                    self.stopTimer()
                    self.notificationService.postNetworkDisconnected()
                } else {
                    // 网络恢复，如果未暂停则重启定时器
                    if self.autoSyncEnabled && !self.isPaused {
                        self.appStatus = .idle
                        self.startTimer()
                        self.notificationService.postNetworkRestored()
                    }
                }
            }
        }

        // 监听 UserDefaults 变化，确保在主线程处理
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                MainActor.assumeIsolated {
                    self.handleDefaultsChanged()
                }
            }
            .store(in: &cancellables)
    }

    /// 处理 UserDefaults 变化
    private func handleDefaultsChanged() {
        if autoSyncEnabled && !isPaused {
            // 重启定时器以应用新的间隔
            stopTimer()
            startTimer()
        } else {
            stopTimer()
        }
    }

    // MARK: - 定时器管理

    /// 启动自动同步定时器
    func startTimer() {
        stopTimer()

        guard autoSyncEnabled, !isPaused, networkMonitor.isConnected else {
            return
        }

        syncTimer = Timer.scheduledTimer(withTimeInterval: autoSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performAutoSync()
            }
        }

        print("自动同步定时器已启动，间隔：\(Int(autoSyncInterval)) 秒")
    }

    /// 停止自动同步定时器
    func stopTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - 同步执行

    /// 执行自动同步（扫描所有项目）
    func performAutoSync() async {
        // 前置检查
        guard !isPaused else { return }
        guard networkMonitor.isConnected else {
            appStatus = .noNetwork
            return
        }
        guard !projectStore.projects.isEmpty else { return }

        appStatus = .syncing

        var successCount = 0
        var failureCount = 0
        var conflictCount = 0
        var hasUpdates = false

        for project in projectStore.projects {
            // 同步过程中如果被暂停或断网，立即停止
            if isPaused || !networkMonitor.isConnected {
                break
            }

            let result = await syncSingleProject(project)

            switch result {
            case .success:
                successCount += 1
            case .upToDate:
                // 无需计入统计
                break
            case .conflict(let details):
                conflictCount += 1
                notificationService.postConflict(
                    projectName: project.name,
                    conflictFiles: [details]
                )
            case .error(let message):
                failureCount += 1
                notificationService.postError(
                    projectName: project.name,
                    errorMessage: message
                )
            }
        }

        // 检测是否有项目存在远程更新
        for project in projectStore.projects {
            if project.syncStatus == .hasUpdate {
                hasUpdates = true
                break
            }
        }

        // 更新统计
        todaySyncCount += successCount + failureCount + conflictCount
        todayPushCount += successCount
        todayConflictCount += conflictCount

        // 更新应用状态
        if !networkMonitor.isConnected {
            appStatus = .noNetwork
        } else if conflictCount > 0 {
            appStatus = .conflict
        } else if hasUpdates {
            appStatus = .hasUpdate
        } else {
            appStatus = .idle
        }

        // 发送批量同步通知
        let totalCount = successCount + failureCount + conflictCount
        if totalCount > 0 {
            notificationService.postBatchSyncCompleted(
                totalCount: totalCount,
                successCount: successCount,
                failureCount: failureCount
            )
        }
    }

    /// 同步单个项目
    /// - Parameter project: 要同步的项目
    /// - Returns: 同步结果
    private func syncSingleProject(_ project: SyncProject) async -> GitSyncResult {
        projectStore.updateSyncStatus(for: project.id, status: .syncing, message: String(localized: "自动同步中..."))

        let result = await syncEngine.syncProject(project)

        switch result {
        case .success(let message):
            projectStore.updateSyncStatus(for: project.id, status: .synced, message: message)
            notificationService.postSyncCompleted(projectName: project.name, message: message)
        case .upToDate:
            projectStore.updateSyncStatus(for: project.id, status: .synced, message: String(localized: "已是最新"))
        case .conflict(let details):
            projectStore.updateSyncStatus(for: project.id, status: .conflict, message: String(localized: "冲突：\(details)"))
        case .error(let message):
            projectStore.updateSyncStatus(for: project.id, status: .error, message: message)
        }

        return result
    }

    // MARK: - 统计更新

    /// 更新今日统计数据
    func updateStats() {
        let todayEntries = historyStore.todayEntries()
        todaySyncCount = todayEntries.count
        todayPushCount = todayEntries.filter { $0.action == .push && $0.isSuccess }.count
        todayConflictCount = todayEntries.filter { $0.result == .conflict }.count
    }

    /// 重置今日统计
    func resetTodayStats() {
        todaySyncCount = 0
        todayPushCount = 0
        todayConflictCount = 0
    }
}

// MARK: - TimeInterval 范围扩展

private extension TimeInterval {
    /// 将值限制在指定范围内，超出范围时使用默认值
    func clamped(to range: ClosedRange<TimeInterval>, defaultValue: TimeInterval) -> TimeInterval {
        if self >= range.lowerBound && self <= range.upperBound {
            return self
        }
        return defaultValue
    }
}
