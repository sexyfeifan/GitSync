// SettingsView.swift
// 设置面板：协调三个标签页（通用、GitHub、项目管理）

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore

    /// 应用设置（统一管理 @AppStorage）
    @ObservedObject private var settings = AppSettings.shared

    // MARK: - 测试连接状态（传递给 GitHubTab）
    @State private var isTestingConnection = false
    @State private var testConnectionMessage: String?
    @State private var testConnectionSuccess = false
    @State private var testConnectionUsername: String?
    @State private var testConnectionAvatarURL: String?
    @State private var testConnectionTechnicalError: String?

    // MARK: - 项目管理状态（传递给 ProjectsTab）
    @State private var showingAddProject = false
    @State private var showDeleteAlert = false
    @State private var projectToDelete: SyncProject?

    // MARK: - 通用设置状态（传递给 GeneralTab）
    @AppStorage("maxHistoryEntries") private var maxHistoryEntries = AppConstants.maxHistoryEntries
    @AppStorage("notificationPreference") private var notificationPreference: NotificationPreference = .all

    var body: some View {
        TabView {
            // 通用设置标签页
            SettingsGeneralTab(
                settings: settings,
                maxHistoryEntries: $maxHistoryEntries,
                notificationPreference: $notificationPreference
            )

            // GitHub 设置标签页
            SettingsGitHubTab(
                settings: settings,
                isTestingConnection: $isTestingConnection,
                testConnectionMessage: $testConnectionMessage,
                testConnectionSuccess: $testConnectionSuccess,
                testConnectionUsername: $testConnectionUsername,
                testConnectionAvatarURL: $testConnectionAvatarURL,
                testConnectionTechnicalError: $testConnectionTechnicalError
            )

            // 项目管理标签页
            SettingsProjectsTab(
                showingAddProject: $showingAddProject,
                showDeleteAlert: $showDeleteAlert,
                projectToDelete: $projectToDelete
            )
        }
        .frame(width: AppConstants.settingsWidth, height: 450)
        // 删除确认弹窗
        .alert(String(localized: "删除项目"), isPresented: $showDeleteAlert) {
            Button(String(localized: "取消"), role: .cancel) {
                projectToDelete = nil
            }
            Button(String(localized: "仅删除记录")) {
                if let project = projectToDelete {
                    projectStore.deleteProject(project)
                }
                projectToDelete = nil
            }
            Button(String(localized: "删除记录和本地文件"), role: .destructive) {
                if let project = projectToDelete {
                    projectStore.deleteProject(project, deleteLocalFiles: true)
                }
                projectToDelete = nil
            }
        } message: {
            if let project = projectToDelete {
                Text(String(localized: "确定要删除项目「\(project.name)」吗？\n\n⚠️ 本地文件路径：\(project.localPath)\n\n选择「删除记录和本地文件」将永久删除本地仓库文件，此操作不可恢复。"))
            }
        }
    }
}
