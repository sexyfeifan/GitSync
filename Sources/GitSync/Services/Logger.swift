// Logger.swift
// 统一日志服务，使用 os.Logger 支持 Console.app 过滤

import Foundation
import os

/// 应用日志工具，封装 os.Logger
/// 在 Console.app 中可通过 subsystem "com.gitsync" 过滤
enum Log {
    /// 通用日志（默认分类）
    static let general = Logger(subsystem: "com.gitsync", category: "general")
    /// 网络相关日志
    static let network = Logger(subsystem: "com.gitsync", category: "network")
    /// 同步操作日志
    static let sync = Logger(subsystem: "com.gitsync", category: "sync")
    /// 存储操作日志
    static let storage = Logger(subsystem: "com.gitsync", category: "storage")
    /// 通知服务日志
    static let notification = Logger(subsystem: "com.gitsync", category: "notification")
}
