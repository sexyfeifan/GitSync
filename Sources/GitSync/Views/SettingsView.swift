// SettingsView.swift
// 设置面板：协调三个标签页（通用、GitHub、项目管理）

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore
    @Environment(\.dismiss) var dismiss

    @ObservedObject private var settings = AppSettings.shared

    @State private var showDeleteAlert = false
    @State private var projectToDelete: SyncProject?

    var body: some View {
        TabView {
            SettingsGeneralTab()
            SettingsGitHubTab()
            SettingsProjectsTab(
                showDeleteAlert: $showDeleteAlert,
                projectToDelete: $projectToDelete
            )
        }
        .frame(width: 540, height: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "关闭")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
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
