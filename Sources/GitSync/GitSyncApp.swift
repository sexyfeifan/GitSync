// GitSyncApp.swift
// GitSync macOS 菜单栏应用入口
// 视图已拆分至 Views/ 目录，此处仅保留 App 声明和生命周期管理

import SwiftUI

@main
struct GitSyncApp: App {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var historyStore = SyncHistoryStore()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var notificationService = NotificationService()

    /// 自动同步服务（延迟初始化，依赖其他 StateObject）
    @State private var autoSyncService: AutoSyncService?

    /// 场景生命周期阶段，用于监听应用退出
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        // 菜单栏常驻图标，macOS 13+ MenuBarExtra
        MenuBarExtra {
            MenuBarView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
                .environmentObject(networkMonitor)
                .environmentObject(notificationService)
        } label: {
            Image(systemName: statusBarIconName)
                .accessibilityLabel(String(localized: "GitSync 同步状态"))
                .accessibilityValue(statusBarAccessibilityValue)
        }
        .menuBarExtraStyle(.window)

        // 设置窗口（使用 WindowGroup 替代 Settings，确保 macOS 26 兼容）
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
                .onAppear {
                    setupAutoSyncService()
                }
        }
        .defaultSize(width: 600, height: 500)
        .onChange(of: scenePhase) { newPhase in
            // 应用进入非活跃状态时，强制刷写所有待保存数据到磁盘
            if newPhase == .inactive || newPhase == .background {
                projectStore.flush()
                historyStore.flush()
            }
        }
    }

    /// 初始化并启动自动同步服务
    private func setupAutoSyncService() {
        guard autoSyncService == nil else { return }
        let service = AutoSyncService(
            projectStore: projectStore,
            historyStore: historyStore,
            notificationService: notificationService,
            networkMonitor: networkMonitor
        )
        autoSyncService = service
    }

    /// 根据项目同步状态动态计算状态栏图标
    private var statusBarIconName: String {
        if let service = autoSyncService {
            switch service.appStatus {
            case .syncing:
                return "arrow.triangle.2.circlepath"
            case .conflict:
                return "exclamationmark.circle.fill"
            case .noNetwork:
                return "wifi.slash"
            case .hasUpdate:
                return "arrow.down.circle.fill"
            case .idle:
                break
            }
        }

        let statuses = projectStore.projects.map { $0.syncStatus }
        if statuses.contains(.syncing) {
            return "arrow.triangle.2.circlepath"
        }
        if statuses.contains(.error) || statuses.contains(.conflict) {
            return "exclamationmark.circle.fill"
        }
        return "arrow.triangle.2.circlepath"
    }

    /// 状态栏图标的无障碍描述
    private var statusBarAccessibilityValue: String {
        if let service = autoSyncService {
            switch service.appStatus {
            case .syncing:
                return String(localized: "正在同步")
            case .conflict:
                return String(localized: "存在冲突")
            case .noNetwork:
                return String(localized: "无网络连接")
            case .hasUpdate:
                return String(localized: "有更新")
            case .idle:
                return String(localized: "空闲")
            }
        }
        return String(localized: "空闲")
    }
}
