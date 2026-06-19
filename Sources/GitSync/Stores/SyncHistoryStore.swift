// SyncHistoryStore.swift
// 同步历史记录持久化存储
// v0.2.2 优化：loadEntries 解码失败时尝试从 .bak.1 恢复（与 ProjectStore 一致）

import Foundation
import SwiftUI
import Combine
import os

/// 同步历史记录存储管理器
@MainActor
class SyncHistoryStore: ObservableObject {
    /// 所有同步历史记录
    @Published var entries: [SyncHistoryEntry] = []

    /// 存储文件路径
    private let storageURL: URL

    /// 使用 OSAllocatedUnfairLock 保护 lastKnownEntries 的读写，避免 data race
    private let lockedEntries = OSAllocatedUnfairLock<[SyncHistoryEntry]>(initialState: [])

    /// 历史记录保留的最大数量（从 UserDefaults 读取，默认 1000）
    private var maxEntries: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxHistoryEntries")
        // 如果未设置或为 0，使用默认值 1000；限制范围 100...10000
        guard stored > 0 else { return 1000 }
        return min(max(stored, 100), 10000)
    }

    /// debounce 写入的 Timer，避免频繁磁盘写入
    private var debounceTimer: Timer?

    /// debounce 延迟（秒），批量操作时合并写入
    private let debounceInterval: TimeInterval = 0.5

    /// 最大备份数量（用于备份轮转）
    private let maxBackupCount = 3

    /// 初始化存储管理器
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(AppConstants.appSupportDirectoryName, isDirectory: true)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.storageURL = appDir.appendingPathComponent(AppConstants.syncHistoryFileName)

        // 加载已有数据
        loadEntries()
    }

    deinit {
        // 退出时确保数据写入磁盘
        debounceTimer?.invalidate()
        debounceTimer = nil
        // deinit 中不能访问 @MainActor 隔离的 entries 属性
        // 调用非隔离的 flushSync 来安全写入
        flushSync()
    }

    /// 非隔离的同步写入方法（仅在 deinit 中使用）
    /// 使用 lastKnownEntries 快照避免访问 @MainActor 隔离的 entries
    nonisolated private func flushSync() {
        // 使用快照数据直接序列化写入，无需访问 @MainActor 隔离属性
        let snapshot = lockedEntries.withLock { $0 }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.storage.error("flushSync 写入失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 持久化操作

    /// 从磁盘加载历史记录（解码失败时尝试从 .bak.1 备份恢复）
    func loadEntries() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            entries = []
            lockedEntries.withLock { $0 = [] }
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([SyncHistoryEntry].self, from: data)
            let snapshot = entries
            lockedEntries.withLock { $0 = snapshot }
        } catch {
            Log.storage.error("加载同步历史失败: \(error.localizedDescription)")
            // [优化] 解码失败时尝试从 .bak.1 备份恢复，与 ProjectStore 保持一致
            let backupURL = storageURL.deletingPathExtension().appendingPathExtension("bak.1")
            if FileManager.default.fileExists(atPath: backupURL.path),
               let backupData = try? Data(contentsOf: backupURL) {
                let backupDecoder = JSONDecoder()
                backupDecoder.dateDecodingStrategy = .iso8601
                if let backupEntries = try? backupDecoder.decode([SyncHistoryEntry].self, from: backupData) {
                    Log.storage.info("从备份 .bak.1 成功恢复 \(backupEntries.count) 条历史记录")
                    entries = backupEntries
                    let snapshot = entries
                    lockedEntries.withLock { $0 = snapshot }
                    return
                }
            }
            Log.storage.error("备份恢复也失败，历史数据可能已丢失")
            entries = []
            lockedEntries.withLock { $0 = [] }
        }
    }

    /// 请求保存（debounce：延迟 0.5 秒后写入，合并多次快速调用）
    private func requestSave() {
        debounceTimer?.invalidate()
        // 统一 Timer/Task 桥接模式：使用 Task { @MainActor [weak self] in }
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

    /// 保存历史记录到磁盘（内部方法，带备份轮转）
    private func saveEntries() {
        // 更新快照，供 deinit 中的 flushSync() 使用
        let snapshot = entries
        lockedEntries.withLock { $0 = snapshot }

        // 写入前创建备份
        createBackupIfNeeded()

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.storage.error("保存同步历史失败: \(error.localizedDescription)")
        }

        // 清理超出上限的旧备份
        cleanOldBackups()
    }

    // MARK: - 备份管理

    /// 创建备份文件：将当前文件复制为 .bak.1
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

    /// 清理超出 maxBackupCount 的旧备份文件（最多检查到 maxBackupCount + 10）
    private func cleanOldBackups() {
        let fm = FileManager.default
        let dir = storageURL.deletingLastPathComponent()
        let baseName = storageURL.lastPathComponent

        // 添加合理上限：最多检查到 maxBackupCount + 10，避免无限循环
        let upperBound = maxBackupCount + 10
        for i in (maxBackupCount + 1)...upperBound {
            let bakFile = dir.appendingPathComponent("\(baseName).bak.\(i)")
            if fm.fileExists(atPath: bakFile.path) {
                try? fm.removeItem(at: bakFile)
            }
        }
    }

    // MARK: - 记录管理

    /// 添加新的历史记录
    func addEntry(_ entry: SyncHistoryEntry) {
        entries.insert(entry, at: 0)

        // 超过上限时删除最旧的记录（maxEntries 从 UserDefaults 动态读取）
        let limit = maxEntries
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
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
    func recentEntries(count: Int = AppConstants.recentHistoryCount) -> [SyncHistoryEntry] {
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
