// GitSyncApp.swift
// GitSync macOS 菜单栏应用入口

import SwiftUI
import ServiceManagement

@main
struct GitSyncApp: App {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var historyStore = SyncHistoryStore()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var notificationService = NotificationService()
    @ObservedObject private var settings = AppSettings.shared

    @State private var autoSyncService: AutoSyncService?
    @Environment(\.scenePhase) private var scenePhase

    /// 应用启动时初始化 Dock 图标状态
    init() {
        let showDock = UserDefaults.standard.bool(forKey: AppConstants.showDockIconKey)
        if !showDock {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    var body: some Scene {
        // 菜单栏常驻图标
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

        // 主窗口（Dock 点击打开此窗口，默认显示设置/项目页）
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
                .onAppear {
                    setupAutoSyncService()
                }
        }
        .defaultSize(width: 620, height: 520)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .inactive || newPhase == .background {
                projectStore.flush()
                historyStore.flush()
            }
        }
        .onChange(of: settings.showDockIcon) { show in
            NSApp.setActivationPolicy(show ? .regular : .accessory)
        }
        .onChange(of: settings.launchAtLogin) { enabled in
            toggleLaunchAtLogin(enabled)
        }
    }

    // MARK: - 自动同步

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

    // MARK: - 开机自启

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.general.error("开机自启设置失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 状态栏图标

    private var statusBarIconName: String {
        if let service = autoSyncService {
            switch service.appStatus {
            case .syncing: return "arrow.triangle.2.circlepath"
            case .conflict: return "exclamationmark.circle.fill"
            case .noNetwork: return "wifi.slash"
            case .hasUpdate: return "arrow.down.circle.fill"
            case .idle: break
            }
        }
        let statuses = projectStore.projects.map { $0.syncStatus }
        if statuses.contains(.syncing) { return "arrow.triangle.2.circlepath" }
        if statuses.contains(.error) || statuses.contains(.conflict) { return "exclamationmark.circle.fill" }
        return "arrow.triangle.2.circlepath"
    }

    private var statusBarAccessibilityValue: String {
        if let service = autoSyncService {
            switch service.appStatus {
            case .syncing: return String(localized: "正在同步")
            case .conflict: return String(localized: "存在冲突")
            case .noNetwork: return String(localized: "无网络连接")
            case .hasUpdate: return String(localized: "有更新")
            case .idle: return String(localized: "空闲")
            }
        }
        return String(localized: "空闲")
    }
}
