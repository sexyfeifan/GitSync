// AddProjectSheet.swift
// 添加项目弹窗

import SwiftUI

struct AddProjectSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var localBasePath = ""
    @State private var isChecking = false
    @State private var checkResult: String?
    @State private var repoInfo: GitHubRepo?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("添加项目")
                .font(.title2)
                .fontWeight(.bold)

            Text("输入 GitHub 仓库 URL，自动克隆并同步到本地。如果不是你自己的仓库，会自动 Fork。")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // URL 输入
            VStack(alignment: .leading, spacing: 6) {
                Text("GitHub 仓库 URL")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("https://github.com/user/repo", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                    Button("检查") {
                        Task { await checkRepo() }
                    }
                    .disabled(urlString.isEmpty || isChecking)
                }

                if isChecking {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在检查仓库...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let info = repoInfo {
                    HStack(spacing: 12) {
                        Label(info.fullName, systemImage: "person.fill")
                            .font(.caption)
                        Label(info.isFork ? "Fork 仓库" : "原始仓库", systemImage: info.isFork ? "tuningfork" : "folder.fill")
                            .font(.caption)
                        Label(info.defaultBranch, systemImage: "arrow.branch")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }

                if let error = checkResult {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // 本地路径
            VStack(alignment: .leading, spacing: 6) {
                Text("本地保存目录")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("~/GitHub", text: $localBasePath)
                        .textFieldStyle(.roundedBorder)

                    Button("选择") {
                        if let path = pickDirectory() {
                            localBasePath = path
                        }
                    }
                }

                Text("仓库将克隆到：\(localBasePath)/仓库名")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Fork 提示
            if let info = repoInfo, !isOwnRepo(info) {
                HStack(spacing: 8) {
                    Image(systemName: "tuningfork")
                        .foregroundColor(.orange)
                    Text("这不是你自己的仓库，将自动 Fork 到你的 GitHub 账号下。")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            Spacer()

            // 按钮
            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("添加并同步") {
                    Task {
                        await viewModel.addProject(urlString: urlString, localBasePath: localBasePath)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.isEmpty || localBasePath.isEmpty || isChecking)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            // 默认路径
            if localBasePath.isEmpty {
                localBasePath = NSHomeDirectory() + "/GitHub"
            }
        }
    }

    private func checkRepo() async {
        isChecking = true
        checkResult = nil
        repoInfo = nil

        guard let (owner, name) = GitHubService.parseRepoURL(urlString) else {
            checkResult = "无法解析 URL"
            isChecking = false
            return
        }

        let service = GitHubService()
        if let repo = await service.fetchRepo(owner: owner, name: name) {
            repoInfo = repo
        } else {
            checkResult = "仓库不存在或无法访问"
        }

        isChecking = false
    }

    private func isOwnRepo(_ repo: GitHubRepo) -> Bool {
        // 简单判断：检查 owner 是否与当前用户匹配
        // 实际应从 GitHub API 获取当前用户名
        return !repo.isFork && repo.parent == nil
    }

    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择保存目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
