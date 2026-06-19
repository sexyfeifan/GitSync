// SyncStatus.swift
// 同步状态枚举，包含颜色和图标映射

import SwiftUI

/// Git 仓库同步状态
enum SyncStatus: String, Codable, CaseIterable {
    /// 已同步，本地与远程一致
    case synced
    /// 同步进行中
    case syncing
    /// 远程有新提交，需要拉取
    case hasUpdate
    /// 本地有新提交，需要推送
    case localAhead
    /// 存在合并冲突
    case conflict
    /// 同步出错
    case error
    /// 尚未同步过
    case notSynced

    /// SF Symbols 图标名称
    var iconName: String {
        switch self {
        case .synced:
            return "checkmark.circle.fill"
        case .syncing:
            return "arrow.clockwise"
        case .hasUpdate:
            return "arrow.down.circle.fill"
        case .localAhead:
            return "arrow.up.circle.fill"
        case .conflict:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        case .notSynced:
            return "circle.dashed"
        }
    }

    /// 状态对应的颜色
    var color: Color {
        switch self {
        case .synced:
            return .green
        case .syncing:
            return .blue
        case .hasUpdate:
            return .blue
        case .localAhead:
            return .orange
        case .conflict:
            return .red
        case .error:
            return .red
        case .notSynced:
            return .gray
        }
    }

    /// 状态的中文显示名称
    var displayName: String {
        switch self {
        case .synced:
            return String(localized: "已同步")
        case .syncing:
            return String(localized: "同步中")
        case .hasUpdate:
            return String(localized: "有更新")
        case .localAhead:
            return String(localized: "本地领先")
        case .conflict:
            return String(localized: "冲突")
        case .error:
            return String(localized: "错误")
        case .notSynced:
            return String(localized: "未同步")
        }
    }
}
