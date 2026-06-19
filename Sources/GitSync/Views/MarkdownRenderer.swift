// MarkdownRenderer.swift
// 轻量 Markdown → AttributedString 渲染器

import SwiftUI

enum MarkdownRenderer {

    /// 将 Markdown 文本转为带格式的 AttributedString
    static func render(_ markdown: String) -> AttributedString {
        var result = AttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 围栏代码块开关 ```
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // 结束代码块
                    result.append(makeCodeBlock(codeLines.joined(separator: "\n")))
                    result.append(AttributedString("\n"))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            result.append(parseLine(trimmed))
            result.append(AttributedString("\n"))
        }

        // 未闭合代码块
        if !codeLines.isEmpty {
            result.append(makeCodeBlock(codeLines.joined(separator: "\n")))
        }

        return result
    }

    // MARK: - 代码块

    private static func makeCodeBlock(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = .system(.caption, design: .monospaced)
        attr.foregroundColor = .secondary
        attr.backgroundColor = Color(nsColor: .textBackgroundColor).opacity(0.5)
        return attr
    }

    // MARK: - 行级解析

    private static func parseLine(_ line: String) -> AttributedString {
        if line.isEmpty { return AttributedString("") }

        // 分隔线
        if line.range(of: #"^[-*_]{3,}$"#, options: .regularExpression) != nil {
            var sep = AttributedString("────────────────────────────────")
            sep.foregroundColor = .secondary.opacity(0.3)
            sep.font = .caption
            return sep
        }

        // 标题
        if line.hasPrefix("# ") {
            return makeHeading(String(line.dropFirst(2)), level: 1)
        }
        if line.hasPrefix("## ") {
            return makeHeading(String(line.dropFirst(3)), level: 2)
        }
        if line.hasPrefix("### ") {
            return makeHeading(String(line.dropFirst(4)), level: 3)
        }
        if line.hasPrefix("#### ") {
            return makeHeading(String(line.dropFirst(5)), level: 4)
        }

        // 无序列表
        if (line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")) && line.count > 2 {
            var bullet = AttributedString("  •  ")
            bullet.foregroundColor = .secondary
            bullet.append(parseInline(String(line.dropFirst(2))))
            return bullet
        }

        // 有序列表
        if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            let prefix = String(line[line.startIndex..<match.upperBound])
            let text = String(line[match.upperBound...])
            var numbered = AttributedString("  " + prefix)
            numbered.foregroundColor = .secondary
            numbered.append(parseInline(text))
            return numbered
        }

        // 引用
        if line.hasPrefix("> ") {
            var quote = AttributedString("  │  ")
            quote.foregroundColor = .accentColor
            var text = parseInline(String(line.dropFirst(2)))
            text.font = .body.italic()
            text.foregroundColor = .secondary
            quote.append(text)
            return quote
        }

        // 普通文本
        return parseInline(line)
    }

    private static func makeHeading(_ text: String, level: Int) -> AttributedString {
        var attr = parseInline(text)
        switch level {
        case 1: attr.font = .title2.bold()
        case 2: attr.font = .title3.bold()
        case 3: attr.font = .headline
        default: attr.font = .subheadline.bold()
        }
        return attr
    }

    // MARK: - 行内格式

    private static func parseInline(_ text: String) -> AttributedString {
        var result = AttributedString()
        var i = text.startIndex

        while i < text.endIndex {
            // 行内代码 `...`
            if text[i] == "`" {
                if let end = text[text.index(after: i)...].firstIndex(of: "`") {
                    let code = String(text[text.index(after: i)..<end])
                    var codeAttr = AttributedString(code)
                    codeAttr.font = .system(.caption, design: .monospaced)
                    codeAttr.foregroundColor = .orange
                    codeAttr.backgroundColor = Color.orange.opacity(0.08)
                    result.append(codeAttr)
                    i = text.index(after: end)
                    continue
                }
            }

            // 粗体 **...**
            if text[i...].hasPrefix("**") {
                if let end = text[text.index(i, offsetBy: 2)...].range(of: "**")?.lowerBound {
                    let bold = String(text[text.index(i, offsetBy: 2)..<end])
                    var boldAttr = AttributedString(bold)
                    boldAttr.font = .body.bold()
                    result.append(boldAttr)
                    i = text.index(end, offsetBy: 2)
                    continue
                }
            }

            // 链接 [text](url)
            if text[i] == "[" {
                if let closeBracket = text[text.index(after: i)...].firstIndex(of: "]"),
                  closeBracket < text.index(before: text.endIndex),
                  text[text.index(after: closeBracket)] == "(",
                  let closeParen = text[text.index(closeBracket, offsetBy: 2)...].firstIndex(of: ")") {
                    let linkText = String(text[text.index(after: i)..<closeBracket])
                    let linkURL = String(text[text.index(closeBracket, offsetBy: 2)..<closeParen])
                    var linkAttr = AttributedString(linkText)
                    linkAttr.foregroundColor = .accentColor
                    linkAttr.underlineStyle = .single
                    if let url = URL(string: linkURL) { linkAttr.link = url }
                    result.append(linkAttr)
                    i = text.index(after: closeParen)
                    continue
                }
            }

            // 图片 ![alt](url) → [图片]
            if text[i...].hasPrefix("![") {
                if let closeParen = text[text.index(i, offsetBy: 2)...].firstIndex(of: ")") {
                    var img = AttributedString("[图片]")
                    img.foregroundColor = .secondary
                    result.append(img)
                    i = text.index(after: closeParen)
                    continue
                }
            }

            // 普通字符 — 收集到下一个特殊字符
            var end = text.index(after: i)
            while end < text.endIndex && text[end] != "`" && text[end] != "[" && text[end] != "*" {
                end = text.index(after: end)
            }
            var plain = AttributedString(decodeEntities(String(text[i..<end])))
            plain.font = .body
            result.append(plain)
            i = end
        }

        return result
    }

    // MARK: - HTML 实体解码

    private static func decodeEntities(_ text: String) -> String {
        var s = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&mdash;", "—"),
            ("&ndash;", "–"), ("&hellip;", "…"), ("&copy;", "©"), ("&reg;", "®"),
            ("&trade;", "™"), ("&rarr;", "→"), ("&larr;", "←"),
        ]
        for (entity, replacement) in entities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }
        // 移除残留 HTML 标签
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return s
    }
}
