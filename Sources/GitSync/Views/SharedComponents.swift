// SharedComponents.swift
// 公共 UI 组件和工具函数，消除跨文件重复

import SwiftUI

// MARK: - 语言颜色映射

/// 根据编程语言名返回对应的标识颜色
func languageColor(_ lang: String) -> Color {
    switch lang.lowercased() {
    case "swift": return .orange
    case "python": return .blue
    case "javascript", "typescript": return .yellow
    case "rust": return .red
    case "go": return .cyan
    case "java", "kotlin": return .purple
    case "c", "c++", "c#": return .green
    case "ruby": return .red
    case "html", "css": return .pink
    case "shell", "bash": return .gray
    case "astro": return .orange
    case "dart": return .cyan
    case "php": return .indigo
    case "scala": return .red
    case "lua": return .blue
    default: return .secondary
    }
}

// MARK: - 语言颜色标签

/// 编程语言的彩色标签组件
struct LanguageBadge: View {
    let language: String
    var body: some View {
        Text(language)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(languageColor(language).opacity(0.15))
            .foregroundColor(languageColor(language))
            .cornerRadius(4)
    }
}

// MARK: - ISO 日期格式化器（缓存）

/// 缓存的 ISO8601 日期格式化器，避免每次调用都创建新实例
enum CachedDateFormatters {
    /// 带毫秒的 ISO8601 格式化器
    static let iso8601Full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 不带毫秒的 ISO8601 格式化器
    static let iso8601Short: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 相对时间格式化器
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.unitsStyle = .short
        return f
    }()

    /// 将 ISO8601 字符串转为相对时间描述（如"3 分钟前"）
    static func relativeString(from isoString: String) -> String {
        if let date = iso8601Full.date(from: isoString) {
            return relative.localizedString(for: date, relativeTo: Date())
        }
        if let date = iso8601Short.date(from: isoString) {
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return isoString
    }
}

// MARK: - 信息行组件

/// 键值对信息行（标签 + 值）
struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(value)
                .font(mono ? .system(.caption, design: .monospaced) : .caption)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

// MARK: - 信息卡片容器

/// 带标题和颜色标识的信息卡片
struct InfoCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .cornerRadius(10)
    }
}
