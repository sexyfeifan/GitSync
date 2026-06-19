// ProjectDetailView.swift
// 项目详情视图

import SwiftUI

struct ProjectDetailView: View {
    let info: ProjectDetailInfo
    var onSync: ((SyncProject) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    localInfoCard
                    remoteInfoCard
                    syncStatusCard
                    metaInfoCard
                }
                Divider()
                readmeSection
            }
            .padding(20)
        }
    }

    // MARK: - 头部

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: info.project.syncStatus.iconName)
                    .foregroundColor(info.project.syncStatus.color)
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.project.name).font(.title.bold())
                    if let desc = info.githubRepo?.description, !desc.isEmpty {
                        Text(desc).font(.callout).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    onSync?(info.project)
                } label: {
                    Label(String(localized: "同步"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            HStack(spacing: 12) {
                if let lang = info.githubRepo?.language { LanguageBadge(language: lang) }
                if let license = info.githubRepo?.license {
                    Label(license.name, systemImage: "doc.plaintext")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let stars = info.githubRepo?.stargazersCount {
                    Label("\(stars)", systemImage: "star.fill").font(.caption).foregroundColor(.yellow)
                }
                if let forks = info.githubRepo?.forksCount {
                    Label("\(forks)", systemImage: "tuningfork").font(.caption).foregroundColor(.secondary)
                }
                Label(info.project.owner, systemImage: "person").font(.caption).foregroundColor(.secondary)
                Link(destination: URL(string: info.project.remoteURL.replacingOccurrences(of: ".git", with: "").replacingOccurrences(of: "git@github.com:", with: "https://github.com/")) ?? URL(string: "https://github.com")!) {
                    Label(String(localized: "GitHub"), systemImage: "safari").font(.caption)
                }
            }
        }
    }

    // MARK: - 本地信息卡片

    private var localInfoCard: some View {
        InfoCard(title: String(localized: "本地"), icon: "desktopcomputer", color: .blue) {
            if let local = info.localInfo {
                InfoRow(label: String(localized: "分支"), value: local.branch)
                InfoRow(label: String(localized: "提交"), value: local.commitHash, mono: true)
                InfoRow(label: String(localized: "消息"), value: local.commitMessage)
                InfoRow(label: String(localized: "作者"), value: local.author)
                InfoRow(label: String(localized: "日期"), value: CachedDateFormatters.relativeString(from: local.commitDate))
                if !local.tags.isEmpty {
                    InfoRow(label: String(localized: "标签"), value: local.tags.joined(separator: ", "))
                }
                HStack(spacing: 4) {
                    Circle().fill(local.isClean ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(local.isClean ? String(localized: "工作区干净") : String(localized: "有未提交变更"))
                        .font(.caption2).foregroundColor(.secondary)
                }
            } else {
                Text(String(localized: "无法读取本地信息")).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - GitHub 信息卡片

    private var remoteInfoCard: some View {
        InfoCard(title: String(localized: "GitHub"), icon: "cloud", color: .purple) {
            if let repo = info.githubRepo {
                InfoRow(label: String(localized: "仓库"), value: repo.fullName)
                InfoRow(label: String(localized: "默认分支"), value: repo.defaultBranch)
                if let lang = repo.language { InfoRow(label: String(localized: "语言"), value: lang) }
                if let pushed = repo.pushedAt {
                    InfoRow(label: String(localized: "最后推送"), value: CachedDateFormatters.relativeString(from: pushed))
                }
                if repo.isFork, let parent = repo.parent {
                    InfoRow(label: String(localized: "Fork 自"), value: parent.fullName)
                }
                if let stars = repo.stargazersCount {
                    InfoRow(label: String(localized: "Stars"), value: "\(stars)")
                }
                if let forks = repo.forksCount {
                    InfoRow(label: String(localized: "Forks"), value: "\(forks)")
                }
                if let license = repo.license {
                    InfoRow(label: String(localized: "许可证"), value: license.name)
                }
            } else {
                Text(String(localized: "无法获取远程信息")).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 同步状态卡片

    private var syncStatusCard: some View {
        InfoCard(title: String(localized: "同步状态"), icon: "arrow.triangle.2.circlepath", color: .green) {
            HStack(spacing: 6) {
                Image(systemName: info.project.syncStatus.iconName)
                    .foregroundColor(info.project.syncStatus.color)
                Text(info.project.syncStatus.displayName)
                    .font(.callout.weight(.medium))
            }
            if !info.project.lastSyncMessage.isEmpty {
                InfoRow(label: String(localized: "消息"), value: info.project.lastSyncMessage)
            }
            InfoRow(label: String(localized: "上次同步"), value: info.project.lastSyncAtFormatted)
            InfoRow(label: String(localized: "远程地址"), value: info.project.remoteURL)
        }
    }

    // MARK: - 项目信息卡片

    private var metaInfoCard: some View {
        InfoCard(title: String(localized: "项目信息"), icon: "info.circle", color: .orange) {
            InfoRow(label: String(localized: "本地路径"), value: info.project.localPath)
            InfoRow(label: String(localized: "Owner"), value: info.project.owner)
            if info.project.isFork {
                Label(String(localized: "Fork 仓库"), systemImage: "tuningfork")
                    .font(.caption).foregroundColor(.orange)
            }
            if info.project.needsInitialBackup && !info.project.initialBackupDone {
                Label(String(localized: "首次同步前将自动备份"), systemImage: "shield.checkered")
                    .font(.caption).foregroundColor(.orange)
            }
            if let pushed = info.githubRepo?.pushedAt {
                InfoRow(label: String(localized: "最后活动"), value: CachedDateFormatters.relativeString(from: pushed))
            }
        }
    }

    // MARK: - README

    @ViewBuilder
    private var readmeSection: some View {
        if let readme = info.readme, !readme.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "README"), systemImage: "doc.text")
                    .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(MarkdownRenderer.render(readme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
            }
        }
    }
}
