// SyncHistoryStore.swift
// 同步历史记录持久化存储

import Foundation
import SwiftUI
import Combine

/// 同步历史记录存储管理器
@MainActor
class SyncHistoryStore: ObservableObject {
    /// 所有同步历史记录
    @Published var entries: [SyncHistoryEntry] = []

    /// 存储文件路径
    private let storageURL: URL

    /// 历史记录保留的最大数量
    private let maxEntries = 1000

    /// debounce 写入的 Timer，避免频繁磁盘写入
    private var debounceTimer: Timer?

    /// debounce 延迟（秒），批量操作时合并写入
    private let debounceInterval: TimeInterval = 0.5

    /// 初始化存储管理器
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("GitSync", isDirectory: true)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.storageURL = appDir.appendingPathComponent("sync_history.json")

        // 加载已有数据
        loadEntries()
    }

    deinit {
        // 退出时确保数据写入磁盘
        debounceTimer?.invalidate()
        debounceTimer = nil
        // deinit 中不能调用 @MainActor 隔离的方法，直接序列化写入
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[SyncHistoryStore] deinit 保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 持久化操作

    /// 从磁盘加载历史记录
    func loadEntries() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([SyncHistoryEntry].self, from: data)
        } catch {
            print("[SyncHistoryStore] 加载同步历史失败: \(error.localizedDescription)")
            entries = []
        }
    }

    /// 请求保存（debounce：延迟 0.5 秒后写入，合并多次快速调用）
    private func requestSave() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.saveEntries()
            }
        }
    }

    /// 立即保存历史记录到磁盘（跳过 debounce）
    func flush() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        saveEntries()
    }

    /// 保存历史记录到磁盘（内部方法）
    private func saveEntries() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[SyncHistoryStore] 保存同步历史失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 记录管理

    /// 添加新的历史记录
    func addEntry(_ entry: SyncHistoryEntry) {
        entries.insert(entry, at: 0)

        // 超过上限时删除最旧的记录
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        // 使用 debounce 写入，避免频繁磁盘 I/O
        requestSave()
    }

    /// 快捷方法：记录一次同步操作
    func recordSync(
        projectID: UUID,
        projectName: String,
        action: SyncAction,
        result: SyncResult,
        message: String,
        duration: TimeInterval = 0,
        fromCommit: String? = nil,
        toCommit: String? = nil
    ) {
        let entry = SyncHistoryEntry(
            projectID: projectID,
            projectName: projectName,
            action: action,
            result: result,
            message: message,
            duration: duration,
            fromCommit: fromCommit,
            toCommit: toCommit
        )
        addEntry(entry)
    }

    /// 删除指定的历史记录
    func deleteEntry(_ entry: SyncHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        requestSave()
    }

    /// 按 ID 删除历史记录
    func deleteEntry(byID id: UUID) {
        entries.removeAll { $0.id == id }
        requestSave()
    }

    /// 清空所有历史记录
    func clearAll() {
        entries.removeAll()
        requestSave()
    }

    /// 清空指定项目的历史记录
    func clearEntries(forProjectID projectID: UUID) {
        entries.removeAll { $0.projectID == projectID }
        requestSave()
    }

    // MARK: - 查询

    /// 获取指定项目的同步历史
    func entries(forProjectID projectID: UUID) -> [SyncHistoryEntry] {
        entries.filter { $0.projectID == projectID }
    }

    /// 获取最近 N 条记录
    func recentEntries(count: Int = 20) -> [SyncHistoryEntry] {
        Array(entries.prefix(count))
    }

    /// 获取今天的同步记录
    func todayEntries() -> [SyncHistoryEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return entries.filter { $0.performedAt >= startOfDay }
    }

    /// 获取失败的记录
    func failedEntries() -> [SyncHistoryEntry] {
        entries.filter { $0.result == .failure }
    }

    /// 今天的同步统计
    var todayStats: (total: Int, success: Int, failure: Int) {
        let today = todayEntries()
        let success = today.filter { $0.isSuccess }.count
        let failure = today.filter { !$0.isSuccess }.count
        return (today.count, success, failure)
    }
}
