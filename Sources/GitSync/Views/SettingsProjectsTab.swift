// SettingsProjectsTab.swift
// 项目管理标签页：项目列表、添加项目、删除项目

import SwiftUI

struct SettingsProjectsTab: View {
    @EnvironmentObject var projectStore: ProjectStore
    @Binding var showDeleteAlert: Bool
    @Binding var projectToDelete: SyncProject?
    @State private var showingAddProject = false
    @State private var newProjectURL = ""
    @State private var addProjectError: String?
    @State private var addProjectTechnicalError: String?
    @State private var isProcessing = false

    var body: some View {
        VStack {
            if projectStore.projects.isEmpty {
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
                List {
                    ForEach(projectStore.projects) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: project.syncStatus.iconName)
                                    .foregroundColor(project.syncStatus.color)
                                    .frame(width: 16, height: 16)
                                Text(project.name).font(.headline)
                                Spacer()
                                Button(String(localized: "删除"), role: .destructive) {
                                    projectToDelete = project
                                    showDeleteAlert = true
                                }
                                .buttonStyle(.borderless)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(project.remoteURL)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(sshURL(from: project.remoteURL))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(project.localPath)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                HStack {
                    Button(String(localized: "添加项目")) {
                        showingAddProject = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Spacer()
                    Text(String(localized: "共 \(projectStore.projects.count) 个项目"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .tabItem { Label(String(localized: "项目"), systemImage: "folder") }
        .sheet(isPresented: $showingAddProject) {
            addProjectSheet
        }
    }

    // MARK: - 添加项目弹窗

    private var addProjectSheet: some View {
        VStack(spacing: 16) {
            Text(String(localized: "添加 Git 项目"))
                .font(.headline)
            TextField(String(localized: "GitHub 仓库 URL"), text: $newProjectURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isProcessing)
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
            if isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "正在处理..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Button(String(localized: "取消")) {
                    if !isProcessing {
                        resetSheet()
                        showingAddProject = false
                    }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isProcessing)
                Button(String(localized: "添加")) {
                    Task {
                        await addProjectFromURL()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProjectURL.isEmpty || isProcessing)
            }
        }
        .padding()
        .frame(width: 450)
    }

    // MARK: - URL 规范化

    /// HTTPS URL → SSH URL
    private func sshURL(from httpsURL: String) -> String {
        var url = httpsURL
        if url.hasSuffix(".git") { url = String(url.dropLast(4)) }
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        url = url.replacingOccurrences(of: "https://github.com/", with: "git@github.com:")
        return url + ".git"
    }

    /// 格式统一：SSH 转 HTTPS、去尾部空格和斜杠，保留 .git 后缀
    private func normalizeGitHubURL(_ input: String) -> String {
        var url = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // SSH → HTTPS
        if url.hasPrefix("git@github.com:") {
            url = "https://github.com/" + url.replacingOccurrences(of: "git@github.com:", with: "")
        }
        // 去掉末尾 /（但保留 .git）
        while url.hasSuffix("/") {
            url = String(url.dropLast())
        }
        return url
    }

    // MARK: - 添加项目逻辑

    private func resetSheet() {
        newProjectURL = ""
        addProjectError = nil
        addProjectTechnicalError = nil
        isProcessing = false
    }

    private func addProjectFromURL() async {
        addProjectError = nil
        addProjectTechnicalError = nil

        // 规范化 URL（支持 .git 后缀和 SSH 格式）
        let normalizedURL = normalizeGitHubURL(newProjectURL)
        guard let parsed = GitHubService.parseRepoURL(normalizedURL) else {
            addProjectError = String(localized: "无法解析 URL，请输入有效的 GitHub 仓库地址")
            addProjectTechnicalError = String(localized: "支持的格式：\n- https://github.com/owner/repo\n- https://github.com/owner/repo.git\n- git@github.com:owner/repo.git")
            return
        }

        let settings = AppSettings.shared
        let localPath = settings.defaultSyncPath + "/" + parsed.name
        let localURL = URL(fileURLWithPath: localPath)
        let gitService = GitService.shared

        // 检查是否已添加过此项目
        if projectStore.projects.contains(where: { $0.localPath == localPath }) {
            addProjectError = String(localized: "该项目已添加：\(parsed.name)")
            return
        }

        isProcessing = true

        if FileManager.default.fileExists(atPath: localPath) {
            if gitService.isGitRepository(at: localURL) {
                // 本地已有 Git 仓库 → 备份后导入
                let backupResult = await BackupService.shared.createBackup(
                    sourceURL: localURL,
                    projectName: parsed.name
                )
                let needsBackupFlag: Bool
                switch backupResult {
                case .success:
                    needsBackupFlag = false
                case .failure:
                    needsBackupFlag = true
                }

                let existingRemote = await gitService.remoteURL(at: localURL)
                let remoteURL = existingRemote ?? normalizedURL

                let project = SyncProject(
                    name: parsed.name,
                    remoteURL: remoteURL,
                    localPath: localPath,
                    owner: parsed.owner,
                    needsInitialBackup: needsBackupFlag
                )
                projectStore.addProject(project)
                isProcessing = false
                resetSheet()
                showingAddProject = false
            } else {
                isProcessing = false
                addProjectError = String(localized: "本地目录已存在但不是 Git 仓库：\(localPath)")
                addProjectTechnicalError = String(localized: "请删除该目录或选择其他同步目录后重试")
            }
            return
        }

        // 本地目录不存在 → 克隆
        let cloneResult = await gitService.clone(url: normalizedURL, to: localURL)
        isProcessing = false

        switch cloneResult {
        case .success:
            let project = SyncProject(
                name: parsed.name,
                remoteURL: normalizedURL,
                localPath: localPath,
                owner: parsed.owner
            )
            projectStore.addProject(project)
            resetSheet()
            showingAddProject = false
        case .failure(let error):
            addProjectError = String(localized: "克隆失败")
            addProjectTechnicalError = error.localizedDescription
        }
    }
}
