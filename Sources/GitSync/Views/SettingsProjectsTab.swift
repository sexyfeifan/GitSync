// SettingsProjectsTab.swift
// 项目管理标签页：项目列表、添加项目、删除项目

import SwiftUI

/// 项目管理标签页内容
struct SettingsProjectsTab: View {
    /// 项目存储
    @EnvironmentObject var projectStore: ProjectStore

    /// 是否显示添加项目面板
    @Binding var showingAddProject: Bool
    /// 删除确认弹窗状态
    @Binding var showDeleteAlert: Bool
    /// 待删除的项目
    @Binding var projectToDelete: SyncProject?

    /// 新项目的远程 URL
    @State private var newProjectURL = ""
    /// 添加项目错误信息
    @State private var addProjectError: String?
    /// 添加项目技术错误详情
    @State private var addProjectTechnicalError: String?

    var body: some View {
        VStack {
            if projectStore.projects.isEmpty {
                // 空状态提示
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(String(localized: "暂无项目"))
                        .foregroundColor(.secondary)
                    Button(String(localized: "添加项目")) {
                        showingAddProject = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 项目列表
                List {
                    ForEach(projectStore.projects) { project in
                        HStack {
                            // 状态指示（形状+颜色，对色盲友好）
                            Image(systemName: project.syncStatus.iconName)
                                .foregroundColor(project.syncStatus.color)
                                .frame(width: 16, height: 16)
                                .accessibilityLabel(project.syncStatus.accessibilityDescription)
                            VStack(alignment: .leading) {
                                Text(project.name).font(.headline)
                                Text(project.remoteURL).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(String(localized: "删除"), role: .destructive) {
                                projectToDelete = project
                                showDeleteAlert = true
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(String(localized: "删除项目 \(project.name)"))
                            .accessibilityHint(String(localized: "弹出确认对话框"))
                        }
                    }
                }
                // 底部添加按钮
                HStack {
                    Button(String(localized: "添加项目")) {
                        showingAddProject = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel(String(localized: "添加新项目"))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .tabItem { Label(String(localized: "项目"), systemImage: "folder") }
        .frame(width: AppConstants.generalTabWidth, height: AppConstants.projectTabHeight)
        .sheet(isPresented: $showingAddProject) {
            addProjectSheet
        }
    }

    // MARK: - 添加项目弹窗

    private var addProjectSheet: some View {
        VStack(spacing: 16) {
            Text(String(localized: "添加 Git 项目"))
                .font(.headline)
            TextField(String(localized: "GitHub 仓库 URL（HTTPS 或 SSH）"), text: $newProjectURL)
                .textFieldStyle(.roundedBorder)
            if let error = addProjectError {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    if let techDetail = addProjectTechnicalError {
                        DisclosureGroup(String(localized: "技术详情")) {
                            Text(techDetail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            HStack {
                Button(String(localized: "取消")) {
                    newProjectURL = ""
                    addProjectError = nil
                    addProjectTechnicalError = nil
                    showingAddProject = false
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "添加")) {
                    Task {
                        await addProjectFromURL()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProjectURL.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }

    // MARK: - 添加项目逻辑

    /// 从 URL 添加新项目
    private func addProjectFromURL() async {
        addProjectError = nil
        addProjectTechnicalError = nil

        guard let parsed = GitHubService.parseRepoURL(newProjectURL) else {
            addProjectError = String(localized: "无法解析 URL，请输入有效的 GitHub 仓库地址")
            addProjectTechnicalError = String(localized: "支持的格式：\n- https://github.com/owner/repo\n- git@github.com:owner/repo.git")
            return
        }

        let settings = AppSettings.shared
        let localPath = settings.defaultSyncPath + "/" + parsed.name

        // 检查本地路径是否已存在
        if FileManager.default.fileExists(atPath: localPath) {
            addProjectError = String(localized: "本地目录已存在：\(localPath)")
            return
        }

        // 克隆仓库
        let gitService = GitService.shared
        // [BUGFIX-1] clone 是 async 方法，必须加 await，否则编译失败
        let cloneResult = await gitService.clone(url: newProjectURL, to: URL(fileURLWithPath: localPath))

        switch cloneResult {
        case .success:
            let project = SyncProject(
                name: parsed.name,
                remoteURL: newProjectURL,
                localPath: localPath,
                owner: parsed.owner
            )
            projectStore.addProject(project)
            newProjectURL = ""
            showingAddProject = false
        case .failure(let error):
            addProjectError = String(localized: "克隆失败")
            addProjectTechnicalError = error.localizedDescription
        }
    }
}
