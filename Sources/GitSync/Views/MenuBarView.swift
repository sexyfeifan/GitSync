// MenuBarView.swift
// 菜单栏主视图，显示项目列表和底部操作栏
// v0.2.2 优化：performSyncAll 添加取消机制

import SwiftUI

// MARK: - 删除确认模式

/// 删除项目的确认选项
enum DeleteMode {
    case recordOnly       // 仅删除记录
    case recordAndFiles   // 删除记录和本地文件
}

struct MenuBarView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var notificationService: NotificationService
    @State private var searchText = ""

    /// 应用设置（统一管理 @AppStorage）
    @ObservedObject private var settings = AppSettings.shared

    // MARK: - 删除确认弹窗状态
    /// 是否显示删除确认弹窗
    @State private var showDeleteAlert = false
    /// 待删除的项目
    @State private var projectToDelete: SyncProject?

    // MARK: - 撤销删除状态
    /// 最近被删除的项目（用于撤销操作）
    @State private var lastDeletedProject: SyncProject?
    /// 撤销计时器
    @State private var undoTimer: Timer?

    // MARK: - 批量同步进度
    /// 当前正在同步的项目名（用于批量同步时显示进度）
    @State private var currentSyncingProject: String?
    /// 是否正在批量同步
    @State private var isSyncingAll = false
    /// 批量同步的 Task 引用（支持取消）
    @State private var syncAllTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(String(localized: "搜索项目..."), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "搜索项目"))
            .accessibilityHint(String(localized: "输入关键词过滤项目列表"))

            Divider()

            // 批量同步进度指示
            if isSyncingAll, let current = currentSyncingProject {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "正在同步：\(current)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                Divider()
            }

            // 项目列表
            if filteredProjects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(String(localized: "暂无项目"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(String(localized: "在设置中添加 Git 仓库"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: AppConstants.emptyListMinHeight)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredProjects) { project in
                            ProjectRowView(
                                project: project,
                                onDeleteRequested: { proj in
                                    projectToDelete = proj
                                    showDeleteAlert = true
                                }
                            )
                            .environmentObject(projectStore)
                        }
                    }
                }
                .frame(maxHeight: AppConstants.projectListMaxHeight)
            }

            Divider()

            // 底部操作栏
            HStack {
                // 网络状态指示
                if !networkMonitor.isConnected {
                    Image(systemName: networkMonitor.iconName)
                        .foregroundColor(.red)
                        .help(networkMonitor.statusDescription)
                        .accessibilityLabel(networkMonitor.statusDescription)
                }

                // 同步/取消按钮（根据状态切换）
                if isSyncingAll {
                    Button(String(localized: "取消同步")) {
                        syncAllTask?.cancel()
                        syncAllTask = nil
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityLabel(String(localized: "取消同步"))
                } else {
                    Button(String(localized: "全部同步")) {
                        syncAllTask = Task {
                            await performSyncAll()
                        }
                    }
                    .disabled(projectStore.projects.isEmpty || !networkMonitor.isConnected)
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityLabel(String(localized: "同步全部项目"))
                    .accessibilityHint(String(localized: "开始同步所有已添加的 Git 仓库"))
                }

                Spacer()

                Button(String(localized: "设置")) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel(String(localized: "打开设置"))

                Button(String(localized: "退出")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel(String(localized: "退出 GitSync"))
            }
            .padding(8)
        }
        .frame(width: AppConstants.menuBarWidth)
        // MARK: - 删除确认弹窗
        .alert(String(localized: "删除项目"), isPresented: $showDeleteAlert) {
            Button(String(localized: "取消"), role: .cancel) {
                projectToDelete = nil
            }
            Button(String(localized: "仅删除记录")) {
                if let project = projectToDelete {
                    // 保存被删除的项目，以便撤销
                    lastDeletedProject = project
                    projectStore.deleteProject(project)
                    // 启动撤销计时器（5秒后清除撤销状态）
                    startUndoTimer()
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
        // 撤销删除提示条
        .overlay(alignment: .bottom) {
            if let deleted = lastDeletedProject {
                HStack {
                    Text(String(localized: "已删除「\(deleted.name)」"))
                        .font(.caption)
                    Spacer()
                    Button(String(localized: "撤销")) {
                        // 恢复项目
                        projectStore.addProject(deleted)
                        lastDeletedProject = nil
                        undoTimer?.invalidate()
                        undoTimer = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
            }
        }
    }

    /// 按搜索关键词过滤项目
    private var filteredProjects: [SyncProject] {
        projectStore.filterProjects(searchText: searchText)
    }

    /// 同步所有项目（带进度指示和取消支持，通过 SyncResultHandler 统一处理）
    private func performSyncAll() async {
        isSyncingAll = true
        currentSyncingProject = nil

        // 使用共享 SyncEngine 实例，避免每次批量同步都创建新实例
        let syncEngine = SyncEngineFactory.shared(historyStore: historyStore)
        let handler = SyncResultHandler(
            syncEngine: syncEngine,
            projectStore: projectStore
        )
        for project in projectStore.projects {
            // 检查取消：如果 Task 被取消，立即退出
            if Task.isCancelled { break }
            currentSyncingProject = project.name
            _ = await handler.syncSingleProject(project)
        }

        currentSyncingProject = nil
        isSyncingAll = false
        syncAllTask = nil
    }

    /// 启动撤销计时器（5秒后自动清除撤销状态）
    private func startUndoTimer() {
        undoTimer?.invalidate()
        // 统一 Timer/Task 桥接模式：使用 Task { @MainActor [weak self] in }
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.lastDeletedProject = nil
                self.undoTimer = nil
            }
        }
    }
}
