// ProjectDetailView.swift
// 项目详情视图

import SwiftUI

struct ProjectDetailView: View {
    let project: SyncProject
    @ObservedObject var viewModel: AppViewModel
    @State private var commitMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 项目头部
                projectHeader

                Divider()

                // 同步状态
                syncStatusSection

                Divider()

                // 操作按钮
                actionButtons

                Divider()

                // 本地变更（如果有）
                localChangesSection

                Divider()

                // 同步历史
                syncHistorySection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 项目头部

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: project.syncStatus.iconName)
                    .font(.title2)
                    .foregroundColor(project.syncStatus.color)

                Text(project.name)
                    .font(.title2)
                    .fontWeight(.bold)

                if project.isOwnRepo {
                    Label("自己的", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }

                if let forkFrom = project.forkedFrom {
                    Label("Fork 自 \(forkFrom)", systemImage: "tuningfork")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            HStack(spacing: 16) {
                Label(project.remoteURL, systemImage: "link")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Label(project.localPath, systemImage: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Label("分支: \(project.branch)", systemImage: "arrow.branch")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 同步状态

    private var syncStatusSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("同步状态")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(project.syncStatus.color)
                        .frame(width: 10, height: 10)
                    Text(project.syncStatus.displayName)
                        .font(.system(.body, weight: .medium))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("最后同步")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(project.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "从未")
                    .font(.system(.body, weight: .medium))
            }

            if !project.lastSyncMessage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("同步信息")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(project.lastSyncMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("操作")
                .font(.caption)
                .foregroundColor(.secondary)

            // 提交并推送
            HStack(spacing: 8) {
                TextField("提交信息...", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)

                Button("提交并推送") {
                    Task {
                        let msg = commitMessage.isEmpty ? "通过 GitSync 更新" : commitMessage
                        await viewModel.commitAndPush(project, message: msg)
                        commitMessage = ""
                    }
                }
                .disabled(viewModel.isSyncing || project.syncStatus == .synced)
            }

            // 其他操作
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.pullProject(project) }
                } label: {
                    Label("拉取", systemImage: "arrow.down")
                }
                .disabled(viewModel.isSyncing)

                Button {
                    Task { await viewModel.pushProject(project) }
                } label: {
                    Label("推送", systemImage: "arrow.up")
                }
                .disabled(viewModel.isSyncing)

                Button {
                    Task { await viewModel.syncProject(project) }
                } label: {
                    Label("同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(viewModel.isSyncing)

                Divider()

                Button {
                    viewModel.openInFinder(project)
                } label: {
                    Label("Finder", systemImage: "folder")
                }

                Button {
                    viewModel.openInTerminal(project)
                } label: {
                    Label("终端", systemImage: "terminal")
                }

                Button {
                    viewModel.copyURL(project)
                } label: {
                    Label("复制 URL", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - 本地变更

    private var localChangesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本地变更")
                .font(.caption)
                .foregroundColor(.secondary)

            let gitService = GitService()
            let status = gitService.status(at: URL(fileURLWithPath: project.localPath))

            if status.isClean {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("工作区干净，无未提交变更")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(status.modified, id: \.self) { file in
                        Label(file, systemImage: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    ForEach(status.added, id: \.self) { file in
                        Label(file, systemImage: "plus.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    ForEach(status.deleted, id: \.self) { file in
                        Label(file, systemImage: "minus.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    ForEach(status.untracked, id: \.self) { file in
                        Label(file, systemImage: "questionmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach(status.conflictFiles, id: \.self) { file in
                        Label(file, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }

    // MARK: - 同步历史

    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("同步历史")
                .font(.caption)
                .foregroundColor(.secondary)

            let history = historyStore.history(forProject: project.id)

            if history.isEmpty {
                Text("暂无同步记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(history.prefix(10)) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.action.iconName)
                                .font(.caption)
                                .foregroundColor(entry.result.color)
                                .frame(width: 16)

                            Text(entry.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Text(entry.timestamp.formatted(.relative(presentation: .named)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var historyStore: SyncHistoryStore {
        viewModel.historyStore
    }
}
