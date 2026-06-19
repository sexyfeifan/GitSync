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
    /// 同步结果处理器（统一处理逻辑，消除重复代码）
    private let resultHandler: SyncResultHandler
    /// 应用设置
    private let settings = AppSettings.shared

    // MARK: - 发布状态

    /// 当前应用状态（驱动菜单栏图标变化）
    @Published var appStatus: SyncAppStatus = .idle

    /// 是否已暂停同步
    @Published var isPaused: Bool = false {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: AppConstants.autoSyncPausedKey)
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

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    /// 创建自动同步服务
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

        let syncEngine = SyncEngine(gitService: .shared, historyStore: historyStore)
        self.resultHandler = SyncResultHandler(
            syncEngine: syncEngine,
            projectStore: projectStore,
            notificationService: notificationService
        )

        // 恢复暂停状态
        self.isPaused = UserDefaults.standard.bool(forKey: AppConstants.autoSyncPausedKey)

        setupBindings()
        updateStats()

        // 启动定时器（如果未暂停且已启用）
        if settings.autoSyncEnabled && !isPaused {
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
                    if self.settings.autoSyncEnabled && !self.isPaused {
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
        if settings.autoSyncEnabled && !isPaused {
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

        guard settings.autoSyncEnabled, !isPaused, networkMonitor.isConnected else {
            return
        }

        let interval = settings.autoSyncIntervalSeconds
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performAutoSync()
            }
        }

        print("自动同步定时器已启动，间隔：\(Int(interval)) 秒")
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

            let result = await resultHandler.syncSingleProject(
                project,
                syncingMessage: String(localized: "自动同步中...")
            )

            switch result {
            case .success:
                successCount += 1
            case .upToDate:
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
