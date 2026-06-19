// ProjectStore.swift
// 项目持久化存储，使用 JSON 文件

import Foundation
import SwiftUI

/// 项目数据存储管理器
@MainActor
class ProjectStore: ObservableObject {
    /// 项目列表
    @Published var projects: [SyncProject] = []

    /// 存储文件路径
    private let storageURL: URL

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
            print("加载项目数据失败: \(error.localizedDescription)")
            projects = []
        }
    }

    /// 保存项目列表到磁盘
    private func saveProjects() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(projects)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("保存项目数据失败: \(error.localizedDescription)")
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

    /// 删除项目
    func deleteProject(_ project: SyncProject) {
        projects.removeAll { $0.id == project.id }
        saveProjects()
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

    /// 同步单个项目（占位实现，实际同步逻辑由 GitSyncEngine 提供）
    func syncProject(_ project: SyncProject) {
        // 标记为同步中（这里简化处理）
        updateSyncStatus(for: project.id, status: .notSynced, message: "正在同步...")
    }

    /// 同步所有项目
    func syncAll() {
        for project in projects {
            syncProject(project)
        }
    }
}
