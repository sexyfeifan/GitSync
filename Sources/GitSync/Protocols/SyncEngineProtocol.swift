// SyncEngineProtocol.swift
// 同步引擎协议抽象，便于测试和替换实现

import Foundation

/// 同步引擎协议
/// 定义同步操作的接口
protocol SyncEngineProtocol {
    /// 同步指定项目
    func syncProject(_ project: SyncProject) async -> AppSyncResult

    /// 获取指定路径的 commit hash
    func getCommitHash(at path: URL) -> String?
}

/// 让 SyncEngine 遵循协议
extension SyncEngine: SyncEngineProtocol {}
