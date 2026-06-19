// BackupRotator.swift
// 备份轮转工具：ProjectStore 和 SyncHistoryStore 共用

import Foundation

/// 备份轮转管理器：自动创建备份文件，清理旧备份
enum BackupRotator {
    /// 最大备份数量
    static let maxBackupCount = 3

    /// 创建备份（将当前文件复制为 .bak.1，旧备份依次轮转）
    static func rotate(url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }

        let dir = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent

        // 轮转：先移编号大的
        for i in stride(from: maxBackupCount, through: 2, by: -1) {
            let older = dir.appendingPathComponent("\(baseName).bak.\(i - 1)")
            let newer = dir.appendingPathComponent("\(baseName).bak.\(i)")
            if fm.fileExists(atPath: older.path) {
                try? fm.removeItem(at: newer)
                try? fm.moveItem(at: older, to: newer)
            }
        }

        let bak1 = dir.appendingPathComponent("\(baseName).bak.1")
        try? fm.removeItem(at: bak1)
        try? fm.copyItem(at: url, to: bak1)
    }

    /// 清理超出上限的旧备份
    static func cleanOld(url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent
        for i in (maxBackupCount + 1)...(maxBackupCount + 10) {
            let bakFile = dir.appendingPathComponent("\(baseName).bak.\(i)")
            if fm.fileExists(atPath: bakFile.path) {
                try? fm.removeItem(at: bakFile)
            }
        }
    }

    /// 从备份恢复（尝试 .bak.1）
    static func recover<T: Decodable>(url: URL, type: T.Type, decoder: JSONDecoder? = nil) -> T? {
        let bakURL = url.deletingPathExtension().appendingPathExtension("bak.1")
        guard FileManager.default.fileExists(atPath: bakURL.path),
              let data = try? Data(contentsOf: bakURL) else { return nil }
        let dec = decoder ?? JSONDecoder()
        return try? dec.decode(T.self, from: data)
    }
}
