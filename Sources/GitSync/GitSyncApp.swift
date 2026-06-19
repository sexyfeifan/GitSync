// GitSyncApp.swift
// GitSync macOS 菜单栏应用入口

import SwiftUI
import ServiceManagement

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.activate(ignoringOtherApps: true)
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }
}

// MARK: - App 入口

@main
struct GitSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var projectStore = ProjectStore()
    @StateObject private var historyStore = SyncHistoryStore()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var notificationService = NotificationService()
    @ObservedObject private var settings = AppSettings.shared

    @State private var autoSyncService: AutoSyncService?
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAppliedDockPolicy = false

    var body: some Scene {
        // 菜单栏常驻图标 — 自动同步在此初始化（确保即使不打开主窗口也能工作）
        MenuBarExtra {
            MenuBarView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
                .environmentObject(networkMonitor)
                .environmentObject(notificationService)
                .onAppear {
                    setupAutoSyncService()
                    applyDockPolicy()
                }
        } label: {
            Image(systemName: statusBarIconName)
                .accessibilityLabel(String(localized: "GitSync 同步状态"))
                .accessibilityValue(statusBarAccessibilityValue)
        }
        .menuBarExtraStyle(.window)

        // 主窗口（Dock 点击打开，展示项目仪表盘）
        WindowGroup(id: "main") {
            MainDashboardView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
                .environmentObject(networkMonitor)
                .environmentObject(notificationService)
        }
        .defaultSize(width: 960, height: 640)

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
        autoSyncService = AutoSyncService(
            projectStore: projectStore,
            historyStore: historyStore,
            notificationService: notificationService,
            networkMonitor: networkMonitor
        )
    }

    // MARK: - Dock 图标策略

    private func applyDockPolicy() {
        guard !hasAppliedDockPolicy else { return }
        hasAppliedDockPolicy = true
        if !settings.showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - 开机自启

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
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
        return "checkmark.circle"
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
