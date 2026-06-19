// SettingsGeneralTab.swift
// 通用设置标签页：同步目录、自动同步、历史记录、通知
// v0.2.2 优化：直接使用 @AppStorage，移除 @Binding 依赖

import SwiftUI

/// 通用设置标签页内容
struct SettingsGeneralTab: View {
    /// 应用设置（统一管理 @AppStorage）
    @ObservedObject private var settings = AppSettings.shared

    /// 历史记录最大条数（直接 @AppStorage，无需从父视图传递）
    @AppStorage("maxHistoryEntries") private var maxHistoryEntries = AppConstants.maxHistoryEntries
    /// 通知偏好（直接 @AppStorage，无需从父视图传递）
    @AppStorage("notificationPreference") private var notificationPreference: NotificationPreference = .all

    var body: some View {
        Form {
            // 同步目录
            Section(String(localized: "同步目录")) {
                HStack {
                    TextField(String(localized: "默认路径"), text: $settings.defaultSyncPath)
                        .textFieldStyle(.roundedBorder)
                    Button(String(localized: "选择")) {
                        Task {
                            if let path = await pickDirectoryAsync() {
                                settings.defaultSyncPath = path
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "选择同步目录"))
                    .accessibilityHint(String(localized: "打开文件夹选择器"))
                }
                Text(String(localized: "新项目将默认保存到此目录"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 备份目录
            Section(String(localized: "备份目录")) {
                HStack {
                    TextField(String(localized: "备份路径"), text: $settings.backupPath)
                        .textFieldStyle(.roundedBorder)
                    Button(String(localized: "选择")) {
                        Task {
                            if let path = await pickDirectoryAsync() {
                                settings.backupPath = path
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "选择备份目录"))
                    .accessibilityHint(String(localized: "打开文件夹选择器"))
                }
                Text(String(localized: "导入已有本地仓库时自动备份原始状态到此目录"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 自动同步
            Section(String(localized: "自动同步")) {
                Toggle(String(localized: "启用自动同步"), isOn: $settings.autoSyncEnabled)
                    .accessibilityHint(String(localized: "开启或关闭定时自动同步"))
                if settings.autoSyncEnabled {
                    Picker(String(localized: "同步间隔"), selection: $settings.autoSyncInterval) {
                        Text(String(localized: "每 1 分钟")).tag(1.0)
                        Text(String(localized: "每 5 分钟")).tag(5.0)
                        Text(String(localized: "每 15 分钟")).tag(15.0)
                        Text(String(localized: "每 1 小时")).tag(60.0)
                    }
                }
            }

            // 历史记录
            Section(String(localized: "历史记录")) {
                Stepper(
                    String(localized: "最大记录数：\(maxHistoryEntries)"),
                    value: $maxHistoryEntries,
                    in: 100...10000,
                    step: 100
                )
                .accessibilityLabel(String(localized: "历史记录最大数量"))
                .accessibilityHint(String(localized: "设置同步历史记录保留的最大条数"))
                Text(String(localized: "超出限制时自动删除最旧的记录"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 通知
            Section(String(localized: "通知")) {
                Picker(String(localized: "通知偏好"), selection: $notificationPreference) {
                    ForEach(NotificationPreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .accessibilityHint(String(localized: "选择接收通知的类型"))
                Text(String(localized: "控制同步完成后是否发送系统通知"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 应用行为
            Section(String(localized: "应用行为")) {
                Toggle(String(localized: "在 Dock 栏显示图标"), isOn: $settings.showDockIcon)
                    .accessibilityHint(String(localized: "关闭后仅保留菜单栏图标，应用在后台运行"))
                Toggle(String(localized: "开机自启动"), isOn: $settings.launchAtLogin)
                    .accessibilityHint(String(localized: "登录时自动启动 GitSync"))
            }
        }
        .tabItem { Label(String(localized: "通用"), systemImage: "gear") }
        .frame(width: AppConstants.generalTabWidth, height: AppConstants.generalTabHeight + 50)
    }

    // MARK: - 辅助方法

    /// 异步版本的目录选择器（使用 continuation，不阻塞主线程）
    private func pickDirectoryAsync() async -> String? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            DispatchQueue.main.async {
                let result = panel.runModal()
                continuation.resume(returning: result == .OK ? panel.url?.path : nil)
            }
        }
    }
}
