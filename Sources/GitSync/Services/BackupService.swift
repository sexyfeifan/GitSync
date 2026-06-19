// BackupService.swift
// 备份服务：将本地仓库目录压缩为 zip 存档，防止同步覆盖导致数据丢失

import Foundation

/// 备份操作错误类型
enum BackupError: LocalizedError {
    case sourceNotFound(path: String)
    case sourceNotDirectory(path: String)
    case createDirectoryFailed(path: String, reason: String)
    case zipFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path):
            return String(localized: "备份源路径不存在: \(path)")
        case .sourceNotDirectory(let path):
            return String(localized: "备份源路径不是目录: \(path)")
        case .createDirectoryFailed(let path, let reason):
            return String(localized: "创建备份目录失败 \(path): \(reason)")
        case .zipFailed(let reason):
            return String(localized: "压缩备份失败: \(reason)")
        }
    }
}

/// 备份服务：将本地 Git 仓库目录压缩为 zip 存档
/// 备份文件命名：{项目名}_{时间戳}.zip
/// 备份目录默认：~/GitSync-Backups/
/// 所有压缩操作在后台线程执行，不阻塞 UI
final class BackupService: Sendable {
    /// 共享实例
    static let shared = BackupService()

    /// 后台串行队列（备份操作排队执行，避免并发写入冲突）
    private let queue = DispatchQueue(label: "com.gitsync.backup", qos: .utility)

    /// 日期格式化器（用于文件名时间戳）
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    private init() {}

    /// 创建本地目录的 zip 备份（异步，后台执行，不阻塞 UI）
    /// - Parameters:
    ///   - sourceURL: 要备份的本地仓库目录
    ///   - projectName: 项目名（用于备份文件命名）
    ///   - backupDir: 备份目标目录（默认从 AppSettings 读取）
    /// - Returns: 备份文件路径或错误
    func createBackup(
        sourceURL: URL,
        projectName: String,
        backupDir: URL? = nil
    ) async -> Result<URL, BackupError> {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.performBackup(sourceURL: sourceURL, projectName: projectName, backupDir: backupDir)
                continuation.resume(returning: result)
            }
        }
    }

    /// 实际执行备份（在后台队列上调用）
    private func performBackup(
        sourceURL: URL,
        projectName: String,
        backupDir: URL?
    ) -> Result<URL, BackupError> {
        let fm = FileManager.default
        let sourcePath = sourceURL.path

        guard fm.fileExists(atPath: sourcePath) else {
            return .failure(.sourceNotFound(path: sourcePath))
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourcePath, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.sourceNotDirectory(path: sourcePath))
        }

        let targetDir = backupDir ?? URL(fileURLWithPath: AppSettings.shared.backupPath)

        if !fm.fileExists(atPath: targetDir.path) {
            do {
                try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            } catch {
                return .failure(.createDirectoryFailed(path: targetDir.path, reason: error.localizedDescription))
            }
        }

        let timestamp = Self.timestampFormatter.string(from: Date())
        let backupFileName = "\(projectName)_\(timestamp).zip"
        let backupURL = targetDir.appendingPathComponent(backupFileName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourcePath, backupURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.zipFailed(reason: error.localizedDescription))
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "未知错误"
            return .failure(.zipFailed(reason: errorMsg))
        }

        return .success(backupURL)
    }

    /// 获取备份目录下指定项目的所有备份文件（按时间降序）
    func listBackups(projectName: String, backupDir: URL? = nil) -> [URL] {
        let fm = FileManager.default
        let targetDir = backupDir ?? URL(fileURLWithPath: AppSettings.shared.backupPath)
        guard let files = try? fm.contentsOfDirectory(
            at: targetDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix(projectName + "_") && $0.pathExtension == "zip" }
            .sorted { ($0.lastPathComponent) > ($1.lastPathComponent) }
    }
}
