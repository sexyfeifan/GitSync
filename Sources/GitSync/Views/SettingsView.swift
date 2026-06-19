// SettingsView.swift
// 设置面板：协调三个标签页（通用、GitHub、项目管理）
// v0.2.2 优化：移除 7+ 个 @Binding 传递，各 Tab 直接使用 @ObservedObject 访问共享状态

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore

    /// 应用设置（统一管理 @AppStorage）
    @ObservedObject private var settings = AppSettings.shared

    // MARK: - 项目管理状态（删除确认弹窗保留在父视图，因为需要 projectStore 引用）
    @State private var showDeleteAlert = false
    @State private var projectToDelete: SyncProject?

    var body: some View {
        TabView {
            // 通用设置标签页：直接使用 @AppStorage，无需 @Binding 传递
            SettingsGeneralTab()

            // GitHub 设置标签页：连接测试状态自管理，无需从父视图 @Binding 传递
            SettingsGitHubTab()

            // 项目管理标签页：删除弹窗状态保留在此，其余自管理
            SettingsProjectsTab(
                showDeleteAlert: $showDeleteAlert,
                projectToDelete: $projectToDelete
            )
        }
        .frame(width: AppConstants.settingsWidth, height: AppConstants.settingsHeight + 50)
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
