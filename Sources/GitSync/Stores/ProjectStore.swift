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

    /// 初始化存储管理器
    init() {
        // 在 Application Support 目录下创建存储文件
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(AppConstants.appSupportDirectoryName, isDirectory: true)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.storageURL = appDir.appendingPathComponent(AppConstants.projectsFileName)

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
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let recovered: [SyncProject] = BackupRotator.recover(url: storageURL, type: [SyncProject].self, decoder: dec) {
                Log.storage.info("从备份恢复 \(recovered.count) 个项目")
                projects = recovered
            } else {
                Log.storage.error("备份恢复也失败，数据可能已丢失")
                projects = []
            }
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

    /// 实际执行磁盘写入
    private func writeProjectsToDisk() {
        BackupRotator.rotate(url: storageURL)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(projects)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.storage.error("保存项目数据失败: \(error.localizedDescription)")
        }
        BackupRotator.cleanOld(url: storageURL)
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

    /// 标记项目的首次备份已完成
    func markBackupDone(projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            return
        }
        projects[index].initialBackupDone = true
        projects[index].needsInitialBackup = false
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
