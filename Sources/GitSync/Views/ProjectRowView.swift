// ProjectRowView.swift
// 项目行视图，显示单个项目的同步状态和操作按钮
// v0.2.2 优化：同步按钮添加 isSyncing loading 状态

import SwiftUI

struct ProjectRowView: View {
    let project: SyncProject
    /// 删除请求回调（由父视图处理确认弹窗）
    let onDeleteRequested: (SyncProject) -> Void
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore

    /// 是否正在同步（loading 状态）
    @State private var isSyncing = false

    var body: some View {
        HStack(spacing: 8) {
            // 同步状态图标
            Image(systemName: project.syncStatus.iconName)
                .foregroundColor(project.syncStatus.color)
                .font(.body)
                .frame(width: 16)
                .accessibilityLabel(project.syncStatus.accessibilityDescription)

            // 项目信息
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(project.name)
                        .font(.system(.callout, weight: .medium))
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
                HStack(spacing: 4) {
                    Text(project.owner)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if !project.lastSyncMessage.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(project.lastSyncMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 操作按钮
            if isSyncing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Button {
                    Task {
                        await syncSingleProject(project)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "同步此项目"))
                .accessibilityLabel(String(localized: "同步项目 \(project.name)"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // 双击打开本地目录
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.localPath)
        }
        .contextMenu {
            Button(String(localized: "在 Finder 中打开")) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.localPath)
            }
            Button(String(localized: "在终端中打开")) {
                NSWorkspace.shared.open(URL(fileURLWithPath: project.localPath))
            }
            Divider()
            Button(String(localized: "复制 GitHub URL")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(project.remoteURL, forType: .string)
            }
            Divider()
            Button(String(localized: "删除项目"), role: .destructive) {
                onDeleteRequested(project)
            }
        }
    }

    /// 同步单个项目（通过 SyncResultHandler 统一处理，使用共享 SyncEngine）
    private func syncSingleProject(_ project: SyncProject) async {
        guard !isSyncing else { return } // 防止重复点击
        isSyncing = true
        let syncEngine = SyncEngineFactory.shared(historyStore: historyStore, projectStore: projectStore)
        let handler = SyncResultHandler(
            syncEngine: syncEngine,
            projectStore: projectStore
        )
        _ = await handler.syncSingleProject(project)
        isSyncing = false
    }
}
