// ProjectStore.swift
// 项目持久化存储，使用 JSON 文件

import Foundation
import SwiftUI
import os

/// 项目数据存储管理器
@MainActor
class ProjectStore: ObservableObject {
    /// debounce 写入的 Timer，避免频繁磁盘写入
    /// 使用 Timer 而非 Task.sleep，与 SyncHistoryStore 保持一致，更可靠
    private var debounceTimer: Timer?

    /// 项目列表
    @Published var projects: [SyncProject] = []

    /// 存储文件路径
    private let storageURL: URL

    /// 最大备份数量
    private let maxBackupCount = 3

    /// 初始化存储管理器
    init() {
        // 在 Application Support 目录下创建存储文件
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("GitSync", isDirectory: true)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.storageURL = appDir.appendingPathComponent("projects.json")

        // 加载已有数据
        loadProjects()
    }

    /// 立即保存项目到磁盘（跳过 debounce），用于应用退出时调用
    func flush() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        writeProjectsToDisk()
    }

    // MARK: - 持久化操作

    /// 从磁盘加载项目列表
    func loadProjects() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            projects = []
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            projects = try decoder.decode([SyncProject].self, from: data)
        } catch {
            Log.storage.error("加载项目数据失败: \(error.localizedDescription)")
            // [BUGFIX-4] 解码失败时尝试从 .bak.1 备份恢复，避免丢失所有数据
            let backupURL = storageURL.deletingPathExtension().appendingPathExtension("bak.1")
            if FileManager.default.fileExists(atPath: backupURL.path),
               let backupData = try? Data(contentsOf: backupURL) {
                let backupDecoder = JSONDecoder()
                backupDecoder.dateDecodingStrategy = .iso8601
                if let backupProjects = try? backupDecoder.decode([SyncProject].self, from: backupData) {
                    Log.storage.info("从备份 .bak.1 成功恢复 \(backupProjects.count) 个项目")
                    projects = backupProjects
                    return
                }
            }
            Log.storage.error("备份恢复也失败，数据可能已丢失")
            projects = []
        }
    }

    /// 保存项目列表到磁盘（防抖：延迟 0.5 秒，合并多次快速调用）
    private func saveProjects() {
        // 取消之前的防抖 Timer
        debounceTimer?.invalidate()
        // 使用 Timer 防抖，与 SyncHistoryStore 保持一致的实现
        debounceTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.debounceDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.writeProjectsToDisk()
            }
        }
    }

    /// 实际执行磁盘写入（在 MainActor 上执行）
    /// 写入前先备份旧文件，最多保留 maxBackupCount 个备份
    private func writeProjectsToDisk() {
        // 步骤 1：创建备份（仅在旧文件存在时）
        createBackupIfNeeded()

        // 步骤 2：写入新数据
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(projects)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.storage.error("保存项目数据失败: \(error.localizedDescription)")
        }

        // 步骤 3：清理超出上限的旧备份
        cleanOldBackups()
    }

    /// 创建备份文件：将当前 projects.json 复制为 projects.json.bak.1
    /// 备份轮转：.bak.3 → 删除，.bak.2 → .bak.3，.bak.1 → .bak.2，当前 → .bak.1
    private func createBackupIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storageURL.path) else { return }

        let dir = storageURL.deletingLastPathComponent()
        let baseName = storageURL.lastPathComponent

        // 轮转：先移编号大的，避免覆盖
        for i in stride(from: maxBackupCount, through: 2, by: -1) {
            let older = dir.appendingPathComponent("\(baseName).bak.\(i - 1)")
            let newer = dir.appendingPathComponent("\(baseName).bak.\(i)")
            if fm.fileExists(atPath: older.path) {
                try? fm.removeItem(at: newer)
                try? fm.moveItem(at: older, to: newer)
            }
        }

        // 将当前文件复制为 .bak.1
        let bak1 = dir.appendingPathComponent("\(baseName).bak.1")
        try? fm.removeItem(at: bak1)
        try? fm.copyItem(at: storageURL, to: bak1)
    }

    /// 清理超出 maxBackupCount 的旧备份文件
    private func cleanOldBackups() {
        let fm = FileManager.default
        let dir = storageURL.deletingLastPathComponent()
        let baseName = storageURL.lastPathComponent

        // 删除编号大于 maxBackupCount 的备份
        for i in (maxBackupCount + 1)... {
            let bakFile = dir.appendingPathComponent("\(baseName).bak.\(i)")
            if fm.fileExists(atPath: bakFile.path) {
                try? fm.removeItem(at: bakFile)
            } else {
                break // 不存在则无需继续
            }
        }
    }

    // MARK: - CRUD 操作

    /// 添加新项目
    func addProject(_ project: SyncProject) {
        // 避免重复添加同一路径的项目
        guard !projects.contains(where: { $0.localPath == project.localPath }) else {
            return
        }
        projects.append(project)
        saveProjects()
    }

    /// 删除项目（仅删除记录，不删除本地文件）
    func deleteProject(_ project: SyncProject) {
        projects.removeAll { $0.id == project.id }
        saveProjects()
    }

    /// 删除项目并可选删除本地文件
    /// - Parameters:
    ///   - project: 要删除的项目
    ///   - deleteLocalFiles: 是否同时删除本地文件
    func deleteProject(_ project: SyncProject, deleteLocalFiles: Bool) {
        projects.removeAll { $0.id == project.id }
        saveProjects()
        if deleteLocalFiles {
            let url = URL(fileURLWithPath: project.localPath)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 按 ID 删除项目
    func deleteProject(byID id: UUID) {
        projects.removeAll { $0.id == id }
        saveProjects()
    }

    /// 更新项目信息
    func updateProject(_ project: SyncProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            return
        }
        projects[index] = project
        saveProjects()
    }

    /// 更新项目的同步状态
    func updateSyncStatus(for projectID: UUID, status: SyncStatus, message: String = "") {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            return
        }
        projects[index].syncStatus = status
        projects[index].lastSyncMessage = message
        if status == .synced {
            projects[index].lastSyncAt = Date()
        }
        saveProjects()
    }

    /// 按 ID 查找项目
    func project(byID id: UUID) -> SyncProject? {
        projects.first { $0.id == id }
    }

    // MARK: - 搜索与排序

    /// 按关键词过滤项目（搜索名称、owner、URL）
    func filterProjects(searchText: String) -> [SyncProject] {
        let sorted = projectsSortedByLastSync
        guard !searchText.isEmpty else {
            return sorted
        }
        let query = searchText.lowercased()
        return sorted.filter { project in
            project.name.lowercased().contains(query) ||
            project.owner.lowercased().contains(query) ||
            project.remoteURL.lowercased().contains(query) ||
            project.branch.lowercased().contains(query)
        }
    }

    /// 按最后同步时间排序（最近同步的在前，从未同步的在最后）
    var projectsSortedByLastSync: [SyncProject] {
        projects.sorted { a, b in
            switch (a.lastSyncAt, b.lastSyncAt) {
            case let (dateA?, dateB?):
                return dateA > dateB
            case (_, .some):
                return false
            case (.some, _):
                return true
            case (nil, nil):
                return a.name < b.name
            }
        }
    }

    /// 按同步状态分组
    var projectsByStatus: [SyncStatus: [SyncProject]] {
        Dictionary(grouping: projects, by: \.syncStatus)
    }

    /// 获取需要关注的项目数量（有更新、冲突或错误的项目）
    var attentionNeededCount: Int {
        projects.filter { project in
            [.hasUpdate, .conflict, .error].contains(project.syncStatus)
        }.count
    }

    // MARK: - 同步操作

    // 注意：同步逻辑统一由 AutoSyncService 管理
    // ProjectStore 仅负责数据持久化和状态更新
}
