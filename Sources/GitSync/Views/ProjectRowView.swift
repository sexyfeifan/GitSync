// ProjectRowView.swift
// 项目行视图，显示单个项目的同步状态和操作按钮

import SwiftUI

struct ProjectRowView: View {
    let project: SyncProject
    /// 删除请求回调（由父视图处理确认弹窗）
    let onDeleteRequested: (SyncProject) -> Void
    @EnvironmentObject var projectStore: ProjectStore

    var body: some View {
        HStack(spacing: 10) {
            // 同步状态图标（形状+颜色区分，对色盲友好）
            Image(systemName: project.syncStatus.iconName)
                .foregroundColor(project.syncStatus.color)
                .frame(width: 20)
                .accessibilityLabel(project.syncStatus.accessibilityDescription)

            // 项目信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(project.name)
                        .font(.system(.body, weight: .medium))
                    if project.isOwnRepo {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .accessibilityLabel(String(localized: "自己的仓库"))
                    }
                    if project.forkedFrom != nil {
                        Image(systemName: "tuningfork")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .accessibilityLabel(String(localized: "Fork 仓库"))
                    }
                }
                Text(project.owner)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !project.lastSyncMessage.isEmpty {
                    Text(project.lastSyncMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 操作按钮
            VStack(spacing: 4) {
                Button {
                    Task {
                        await syncSingleProject(project)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "同步此项目"))
                .accessibilityLabel(String(localized: "同步项目 \(project.name)"))
                .accessibilityHint(String(localized: "立即同步此 Git 仓库"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    /// 同步单个项目（通过 SyncResultHandler 统一处理）
    private func syncSingleProject(_ project: SyncProject) async {
        let syncEngine = SyncEngine(gitService: .shared)
        let handler = SyncResultHandler(
            syncEngine: syncEngine,
            projectStore: projectStore
        )
        _ = await handler.syncSingleProject(project)
    }
}
