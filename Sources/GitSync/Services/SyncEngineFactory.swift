// SyncEngineFactory.swift
// 共享 SyncEngine 实例工厂
// 避免在 AutoSyncService、MenuBarView、ProjectRowView 中各创建独立实例

import Foundation

/// SyncEngine 工厂
/// 提供缓存的共享 SyncEngine 实例，确保整个应用使用同一个同步引擎
@MainActor
enum SyncEngineFactory {
    /// 缓存的共享实例
    private static var _shared: SyncEngine?

    /// 获取或创建共享的同步引擎实例
    /// 首次调用时创建实例，后续调用返回缓存的实例
    /// - Parameter historyStore: 同步历史存储（仅首次调用时使用）
    /// - Returns: 共享的 SyncEngine 实例
    static func shared(historyStore: SyncHistoryStore) -> SyncEngine {
        if let existing = _shared {
            return existing
        }
        let engine = SyncEngine(gitService: GitService.shared, historyStore: historyStore)
        _shared = engine
        return engine
    }

    /// 重置共享实例（仅用于测试）
    static func reset() {
        _shared = nil
    }
}
