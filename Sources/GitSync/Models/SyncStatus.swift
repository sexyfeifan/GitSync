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
    /// 每种状态使用不同形状（对色盲友好）：
    /// - synced: 勾选圆形 ✓
    /// - syncing: 旋转箭头 ↻
    /// - hasUpdate: 下载圆形 ↓
    /// - localAhead: 上传圆形 ↑
    /// - conflict: 警告三角形 △
    /// - error: 叉号圆形 ✕
    /// - notSynced: 虚线圆形 ○
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
    /// 注意：conflict 使用三角形形状，error 使用圆形+叉号，颜色虽同为红色但形状不同
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
            return .orange
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

    /// 无障碍辅助文本，提供纯文字描述（配合 VoiceOver 使用）
    var accessibilityDescription: String {
        switch self {
        case .synced:
            return String(localized: "已同步，勾选标记")
        case .syncing:
            return String(localized: "同步中，旋转箭头")
        case .hasUpdate:
            return String(localized: "有更新，下载箭头")
        case .localAhead:
            return String(localized: "本地领先，上传箭头")
        case .conflict:
            return String(localized: "冲突，警告三角形")
        case .error:
            return String(localized: "错误，叉号标记")
        case .notSynced:
            return String(localized: "未同步，虚线圆圈")
        }
    }
}
