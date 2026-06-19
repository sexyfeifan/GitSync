// MainView.swift
// GitSync 主窗口 — 项目列表 + 详情

import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            // 左侧：项目列表
            VStack(spacing: 0) {
                // 搜索栏
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("搜索项目...", text: .constant(""))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // 项目列表
                if viewModel.projectStore.projects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("还没有项目")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("点击下方按钮添加")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.projectStore.projects, selection: $viewModel.selectedProjectID) { project in
                        ProjectListRow(project: project, viewModel: viewModel)
                            .tag(project.id)
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                // 底部操作栏
                HStack(spacing: 8) {
                    Button {
                        viewModel.showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("添加项目")

                    Button {
                        Task { await viewModel.syncAll() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isSyncing)
                    .help("同步全部")

                    Spacer()

                    Text("\(viewModel.projectStore.projects.count) 个项目")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            // 右侧：项目详情
            if let project = viewModel.selectedProject {
                ProjectDetailView(project: project, viewModel: viewModel)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("选择一个项目")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("或点击 + 添加新项目")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $viewModel.showingAddSheet) {
            AddProjectSheet(viewModel: viewModel)
        }
    }
}

// MARK: - 项目列表行

struct ProjectListRow: View {
    let project: SyncProject
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            // 状态指示灯
            Circle()
                .fill(project.syncStatus.color)
                .frame(width: 8, height: 8)

            // 项目信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(project.name)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    if project.isOwnRepo {
                        Image(systemName: "person.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.blue)
                    }
                    if project.forkedFrom != nil {
                        Image(systemName: "tuningfork")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 6) {
                    Text(project.owner)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let lastSync = project.lastSyncAt {
                        Text(lastSync.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // 同步按钮
            if viewModel.isSyncing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Button {
                    Task { await viewModel.syncProject(project) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("同步")
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("同步") {
                Task { await viewModel.syncProject(project) }
            }
            Divider()
            Button("在 Finder 中打开") {
                viewModel.openInFinder(project)
            }
            Button("在终端中打开") {
                viewModel.openInTerminal(project)
            }
            Button("复制 GitHub URL") {
                viewModel.copyURL(project)
            }
            Divider()
            Button("删除", role: .destructive) {
                viewModel.deleteProject(project)
            }
        }
    }
}
