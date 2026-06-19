// SettingsGitHubTab.swift
// GitHub 设置标签页：Token 配置、连接测试
// v0.2.2 优化：连接测试状态自管理，移除 6 个 @Binding 依赖

import SwiftUI

/// GitHub 设置标签页内容
struct SettingsGitHubTab: View {
    /// 应用设置（统一管理 @AppStorage）
    @ObservedObject private var settings = AppSettings.shared

    // MARK: - 测试连接状态（自管理，无需从父视图 @Binding 传递）
    @State private var isTestingConnection = false
    @State private var testConnectionMessage: String?
    @State private var testConnectionSuccess = false
    @State private var testConnectionUsername: String?
    @State private var testConnectionAvatarURL: String?
    @State private var testConnectionTechnicalError: String?

    var body: some View {
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

    // MARK: - 测试连接

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
}
