// GitSyncApp.swift
// GitSync macOS 菜单栏应用入口

import SwiftUI

@main
struct GitSyncApp: App {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var historyStore = SyncHistoryStore()

    var body: some Scene {
        // 菜单栏常驻图标，macOS 13+ MenuBarExtra
        MenuBarExtra("GitSync", systemImage: "arrow.triangle.2.circlepath") {
            MenuBarView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
        }
        .menuBarExtraStyle(.window)

        // 设置窗口
        Settings {
            SettingsView()
                .environmentObject(projectStore)
                .environmentObject(historyStore)
        }
    }
}

// MARK: - 菜单栏主视图

struct MenuBarView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索项目...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 项目列表
            if filteredProjects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无项目")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("在设置中添加 Git 仓库")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredProjects) { project in
                            ProjectRowView(project: project)
                                .environmentObject(projectStore)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            Divider()

            // 底部操作栏
            HStack {
                Button("全部同步") {
                    projectStore.syncAll()
                }
                .disabled(projectStore.projects.isEmpty)

                Spacer()

                Button("设置") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
        }
        .frame(width: 320)
    }

    /// 按搜索关键词过滤项目
    private var filteredProjects: [SyncProject] {
        projectStore.filterProjects(searchText: searchText)
    }
}

// MARK: - 项目行视图

struct ProjectRowView: View {
    let project: SyncProject
    @EnvironmentObject var projectStore: ProjectStore

    var body: some View {
        HStack(spacing: 10) {
            // 同步状态图标
            Image(systemName: project.syncStatus.iconName)
                .foregroundColor(project.syncStatus.color)
                .frame(width: 20)

            // 项目信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(project.name)
                        .font(.system(.body, weight: .medium))
                    if project.isOwnRepo {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if project.forkedFrom != nil {
                        Image(systemName: "tuningfork")
                            .font(.caption2)
                            .foregroundColor(.orange)
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
                    projectStore.syncProject(project)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("同步此项目")
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
            Button("在 Finder 中打开") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.localPath)
            }
            Button("在终端中打开") {
                NSWorkspace.shared.open(URL(fileURLWithPath: project.localPath))
            }
            Divider()
            Button("复制 GitHub URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(project.remoteURL, forType: .string)
            }
            Divider()
            Button("删除项目", role: .destructive) {
                projectStore.deleteProject(project)
            }
        }
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var historyStore: SyncHistoryStore
    @AppStorage("defaultSyncPath") private var defaultSyncPath = NSHomeDirectory() + "/GitHub"
    @AppStorage("autoSyncInterval") private var autoSyncInterval = 5.0
    @AppStorage("autoSyncEnabled") private var autoSyncEnabled = true
    @AppStorage("githubToken") private var githubToken = ""
    @State private var showingTokenAlert = false

    var body: some View {
        TabView {
            // 通用设置
            Form {
                Section("同步目录") {
                    HStack {
                        TextField("默认路径", text: $defaultSyncPath)
                            .textFieldStyle(.roundedBorder)
                        Button("选择") {
                            if let path = pickDirectory() {
                                defaultSyncPath = path
                            }
                        }
                    }
                    Text("新项目将默认保存到此目录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("自动同步") {
                    Toggle("启用自动同步", isOn: $autoSyncEnabled)
                    if autoSyncEnabled {
                        Picker("同步间隔", selection: $autoSyncInterval) {
                            Text("每 1 分钟").tag(1.0)
                            Text("每 5 分钟").tag(5.0)
                            Text("每 15 分钟").tag(15.0)
                            Text("每 1 小时").tag(60.0)
                        }
                    }
                }
            }
            .tabItem { Label("通用", systemImage: "gear") }
            .frame(width: 400, height: 250)

            // GitHub 设置
            Form {
                Section("GitHub Token") {
                    SecureField("Personal Access Token", text: $githubToken)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("获取 Token") {
                            NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens")!)
                        }
                        Button("测试连接") {
                            showingTokenAlert = true
                        }
                        .disabled(githubToken.isEmpty)
                    }

                    Text("需要 repo 权限（Fine-grained Token 推荐）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tabItem { Label("GitHub", systemImage: "person.circle") }
            .frame(width: 400, height: 200)

            // 项目管理
            VStack {
                if projectStore.projects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("暂无项目")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(projectStore.projects) { project in
                            HStack {
                                Circle()
                                    .fill(project.syncStatus.color)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading) {
                                    Text(project.name).font(.headline)
                                    Text(project.remoteURL).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("删除", role: .destructive) {
                                    projectStore.deleteProject(project)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .tabItem { Label("项目", systemImage: "folder") }
            .frame(width: 400, height: 300)
        }
        .frame(width: 500, height: 400)
        .alert("测试连接", isPresented: $showingTokenAlert) {
            Button("确定") {}
        } message: {
            Text("Token 验证功能将在下次同步时自动测试")
        }
    }

    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
