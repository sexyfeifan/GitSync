// SettingsView.swift
// 设置面板，包含通用设置、GitHub 配置、项目管理和添加项目

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore

    /// 应用设置（统一管理 @AppStorage）
    @ObservedObject private var settings = AppSettings.shared

    // MARK: - 测试连接状态
    /// 是否正在测试连接
    @State private var isTestingConnection = false
    /// 测试连接结果消息
    @State private var testConnectionMessage: String?
    /// 测试连接是否成功
    @State private var testConnectionSuccess = false
    /// 测试连接返回的用户名
    @State private var testConnectionUsername: String?
    /// 测试连接返回的头像 URL
    @State private var testConnectionAvatarURL: String?
    /// 测试连接的技术错误详情
    @State private var testConnectionTechnicalError: String?

    // MARK: - 添加项目状态
    /// 是否显示添加项目面板
    @State private var showingAddProject = false
    /// 新项目的远程 URL
    @State private var newProjectURL = ""
    /// 添加项目错误信息
    @State private var addProjectError: String?
    /// 添加项目技术错误详情
    @State private var addProjectTechnicalError: String?

    // MARK: - 删除确认弹窗状态
    @State private var showDeleteAlert = false
    @State private var projectToDelete: SyncProject?

    // MARK: - maxEntries 配置
    @AppStorage("maxHistoryEntries") private var maxHistoryEntries = AppConstants.maxHistoryEntries

    // MARK: - 通知偏好配置
    @AppStorage("notificationPreference") private var notificationPreference: NotificationPreference = .all

    var body: some View {
        TabView {
            // 通用设置
            generalSettingsTab
            // GitHub 设置
            githubSettingsTab
            // 项目管理
            projectManagementTab
        }
        .frame(width: AppConstants.settingsWidth, height: 450)
        // 添加项目弹窗
        .sheet(isPresented: $showingAddProject) {
            addProjectSheet
        }
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

    // MARK: - 通用设置标签页

    private var generalSettingsTab: some View {
        Form {
            Section(String(localized: "同步目录")) {
                HStack {
                    TextField(String(localized: "默认路径"), text: $settings.defaultSyncPath)
                        .textFieldStyle(.roundedBorder)
                    Button(String(localized: "选择")) {
                        Task {
                            if let path = await pickDirectoryAsync() {
                                settings.defaultSyncPath = path
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "选择同步目录"))
                    .accessibilityHint(String(localized: "打开文件夹选择器"))
                }
                Text(String(localized: "新项目将默认保存到此目录"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(String(localized: "自动同步")) {
                Toggle(String(localized: "启用自动同步"), isOn: $settings.autoSyncEnabled)
                    .accessibilityHint(String(localized: "开启或关闭定时自动同步"))
                if settings.autoSyncEnabled {
                    Picker(String(localized: "同步间隔"), selection: $settings.autoSyncInterval) {
                        Text(String(localized: "每 1 分钟")).tag(1.0)
                        Text(String(localized: "每 5 分钟")).tag(5.0)
                        Text(String(localized: "每 15 分钟")).tag(15.0)
                        Text(String(localized: "每 1 小时")).tag(60.0)
                    }
                }
            }

            Section(String(localized: "历史记录")) {
                Stepper(
                    String(localized: "最大记录数：\(maxHistoryEntries)"),
                    value: $maxHistoryEntries,
                    in: 100...10000,
                    step: 100
                )
                .accessibilityLabel(String(localized: "历史记录最大数量"))
                .accessibilityHint(String(localized: "设置同步历史记录保留的最大条数"))
                Text(String(localized: "超出限制时自动删除最旧的记录"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(String(localized: "通知")) {
                Picker(String(localized: "通知偏好"), selection: $notificationPreference) {
                    ForEach(NotificationPreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .accessibilityHint(String(localized: "选择接收通知的类型"))
                Text(String(localized: "控制同步完成后是否发送系统通知"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .tabItem { Label(String(localized: "通用"), systemImage: "gear") }
        .frame(width: AppConstants.generalTabWidth, height: AppConstants.generalTabHeight + 50)
    }

    // MARK: - GitHub 设置标签页

    private var githubSettingsTab: some View {
        Form {
            Section(String(localized: "GitHub Token")) {
                SecureField("Personal Access Token", text: $settings.githubToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(String(localized: "获取 Token")) {
                        NSWorkspace.shared.open(URL(string: AppConstants.gitHubTokenURL)!)
                    }
                    .accessibilityHint(String(localized: "在浏览器中打开 GitHub Token 设置页"))

                    Button(String(localized: "测试连接")) {
                        Task {
                            await performTestConnection()
                        }
                    }
                    .disabled(settings.githubToken.isEmpty || isTestingConnection)
                    .accessibilityLabel(String(localized: "测试 GitHub 连接"))
                    .accessibilityHint(String(localized: "验证 Token 是否有效"))
                }

                // 测试连接结果
                if isTestingConnection {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "正在验证..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let message = testConnectionMessage {
                    HStack(spacing: 6) {
                        Image(systemName: testConnectionSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(testConnectionSuccess ? .green : .red)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(testConnectionSuccess ? .green : .red)
                    }

                    // 成功时显示用户信息
                    if testConnectionSuccess, let username = testConnectionUsername {
                        HStack(spacing: 8) {
                            if let avatarURL = testConnectionAvatarURL, let url = URL(string: avatarURL) {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    Circle().fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                            }
                            Text(String(localized: "已登录：\(username)"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 失败时显示可展开的技术详情
                    if !testConnectionSuccess, let techError = testConnectionTechnicalError {
                        DisclosureGroup(String(localized: "技术详情")) {
                            Text(techError)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Text(String(localized: "需要 repo 权限（Fine-grained Token 推荐）"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .tabItem { Label("GitHub", systemImage: "person.circle") }
        .frame(width: AppConstants.generalTabWidth, height: AppConstants.githubTabHeight + 150)
    }

    // MARK: - 项目管理标签页

    private var projectManagementTab: some View {
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

    // MARK: - 测试连接（真正的 GitHub API 调用）

    /// 调用 GitHub API /user 验证 Token 有效性
    private func performTestConnection() async {
        isTestingConnection = true
        testConnectionMessage = nil
        testConnectionSuccess = false
        testConnectionUsername = nil
        testConnectionAvatarURL = nil
        testConnectionTechnicalError = nil

        // 先保存 Token 到 Keychain
        do {
            try GitHubService.saveToken(settings.githubToken)
        } catch {
            testConnectionMessage = String(localized: "Token 保存失败")
            testConnectionTechnicalError = error.localizedDescription
            isTestingConnection = false
            return
        }

        // 调用 GitHub API /user
        let service = GitHubService(token: settings.githubToken)
        let result = await service.testConnection()

        switch result {
        case .success(let userInfo):
            testConnectionMessage = String(localized: "连接成功 ✓")
            testConnectionSuccess = true
            testConnectionUsername = userInfo.login
            testConnectionAvatarURL = userInfo.avatarURL
        case .failure(let error):
            testConnectionMessage = String(localized: "连接失败")
            testConnectionSuccess = false
            switch error {
            case .unauthorized:
                testConnectionTechnicalError = String(localized: "Token 无效或已过期，请重新生成。")
            case .rateLimited(let resetDate):
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                testConnectionTechnicalError = String(localized: "API 速率限制，请在 \(formatter.string(from: resetDate)) 后重试。")
            case .networkError:
                testConnectionTechnicalError = String(localized: "请检查网络连接。详细信息：\(error.localizedDescription)")
            default:
                testConnectionTechnicalError = error.localizedDescription
            }
        }

        isTestingConnection = false
    }

    // MARK: - 添加项目

    /// 从 URL 添加新项目
    private func addProjectFromURL() async {
        addProjectError = nil
        addProjectTechnicalError = nil

        guard let parsed = GitHubService.parseRepoURL(newProjectURL) else {
            addProjectError = String(localized: "无法解析 URL，请输入有效的 GitHub 仓库地址")
            addProjectTechnicalError = String(localized: "支持的格式：\n- https://github.com/owner/repo\n- git@github.com:owner/repo.git")
            return
        }

        let localPath = settings.defaultSyncPath + "/" + parsed.name

        // 检查本地路径是否已存在
        if FileManager.default.fileExists(atPath: localPath) {
            addProjectError = String(localized: "本地目录已存在：\(localPath)")
            return
        }

        // 克隆仓库
        let gitService = GitService.shared
        let cloneResult = gitService.clone(url: newProjectURL, to: URL(fileURLWithPath: localPath))

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

    // MARK: - 辅助方法

    /// 异步版本的目录选择器（使用 continuation，不阻塞主线程）
    private func pickDirectoryAsync() async -> String? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            DispatchQueue.main.async {
                let result = panel.runModal()
                continuation.resume(returning: result == .OK ? panel.url?.path : nil)
            }
        }
    }
}
