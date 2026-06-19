import Foundation

// MARK: - Git 错误类型

/// Git 操作可能产生的错误
enum GitError: LocalizedError {
    /// 命令执行失败（包含退出码和输出信息）
    case commandFailed(command: String, code: Int32, output: String)
    /// 目录不存在
    case pathNotFound(path: String)
    /// 不是一个 Git 仓库
    case notGitRepository(path: String)
    /// 克隆失败
    case cloneFailed(url: String, reason: String)
    /// 合并冲突
    case conflict(details: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, code, output):
            return String(localized: "Git 命令失败（退出码 \(code)）: \(command)\n\(output)")
        case let .pathNotFound(path):
            return String(localized: "路径不存在: \(path)")
        case let .notGitRepository(path):
            return String(localized: "不是 Git 仓库: \(path)")
        case let .cloneFailed(url, reason):
            return String(localized: "克隆仓库失败 \(url): \(reason)")
        case let .conflict(details):
            return String(localized: "合并冲突: \(details)")
        }
    }
}

// MARK: - Git 状态

/// 工作区状态，包含各类型变更文件列表
struct GitStatus {
    /// 已修改的文件
    let modified: [String]
    /// 新增的文件（已暂存）
    let added: [String]
    /// 已删除的文件
    let deleted: [String]
    /// 未跟踪的文件
    let untracked: [String]
    /// 是否有冲突文件
    let hasConflicts: Bool
    /// 冲突文件列表
    let conflictFiles: [String]

    /// 工作区是否干净（无任何变更）
    var isClean: Bool {
        modified.isEmpty && added.isEmpty && deleted.isEmpty && untracked.isEmpty && !hasConflicts
    }
}

// MARK: - Git 服务

/// Git CLI 封装，通过 Process 执行 git 命令
/// 已标记 Sendable，所有可变状态在 init 后不再变化
final class GitService: Sendable {
    /// 共享实例，避免每次调用都创建新对象
    static let shared = GitService()

    /// 额外的 PATH 组件，会在执行命令前添加到环境变量
    /// 改为 let 确保线程安全（初始化后不可变）
    let extraPATHComponents: [String]

    init(extraPATHComponents: [String]? = nil) {
        #if os(macOS)
        let defaultComponents = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        #else
        let defaultComponents: [String] = []
        #endif
        self.extraPATHComponents = extraPATHComponents ?? defaultComponents
    }

    // MARK: - 仓库操作

    /// 克隆远程仓库到本地目录
    /// - Parameters:
    ///   - url: 远程仓库 URL（HTTPS 或 SSH）
    ///   - to: 本地目标路径
    /// - Returns: 操作结果
    func clone(url: String, to: URL) -> Result<Void, GitError> {
        // 克隆前检查目标路径是否已存在，避免覆盖已有仓库
        if FileManager.default.fileExists(atPath: to.path) {
            return .failure(.cloneFailed(url: url, reason: "目标路径已存在: \(to.path)"))
        }

        // 确保父目录存在
        let parentDir = to.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            do {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                return .failure(.pathNotFound(path: parentDir.path))
            }
        }

        do {
            _ = try runGit(args: ["clone", url, to.path], in: parentDir)
            return .success(())
        } catch let error as GitError {
            if case .commandFailed = error {
                return .failure(.cloneFailed(url: url, reason: error.localizedDescription))
            }
            return .failure(error)
        } catch {
            return .failure(.cloneFailed(url: url, reason: error.localizedDescription))
        }
    }

    /// 拉取远程更新（使用 rebase 策略）
    /// - Parameters:
    ///   - at: 本地仓库路径
    ///   - branch: 要拉取的分支名（默认当前分支）
    /// - Returns: 命令输出或错误
    func pull(at path: URL, branch: String? = nil) -> Result<String, GitError> {
        var args = ["pull", "--rebase"]
        if let branch = branch {
            args.append(contentsOf: ["origin", branch])
        }
        return executeGit(args: args, in: path)
    }

    /// 推送本地提交到远程
    /// - Parameters:
    ///   - at: 本地仓库路径
    ///   - branch: 要推送的分支名（默认当前分支）
    /// - Returns: 命令输出或错误
    func push(at path: URL, branch: String? = nil) -> Result<String, GitError> {
        var args = ["push"]
        if let branch = branch {
            args.append(contentsOf: ["origin", branch])
        }
        return executeGit(args: args, in: path)
    }

    /// 从远程获取最新引用（不合并）
    /// - Parameter at: 本地仓库路径
    /// - Returns: 操作结果
    func fetch(at path: URL) -> Result<Void, GitError> {
        switch executeGit(args: ["fetch", "origin"], in: path) {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - 状态查询

    /// 获取工作区状态，失败时返回错误而非静默返回空状态
    func status(at path: URL) -> Result<GitStatus, GitError> {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return .failure(.pathNotFound(path: path.path))
        }

        let result = executeGit(args: ["status", "--porcelain=v1"], in: path)

        switch result {
        case .success(let output):
            return .success(parseStatusOutput(output))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// 获取当前分支名
    /// - Parameter at: 本地仓库路径
    /// - Returns: 分支名，失败时返回 nil
    func currentBranch(at path: URL) -> String? {
        let result = executeGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        switch result {
        case .success(let output):
            let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.isEmpty ? nil : branch
        case .failure:
            return nil
        }
    }

    // MARK: - 变更检测

    /// 检测是否有远端变更（比较本地 HEAD 和远端 HEAD）
    /// - Parameter localPath: 本地仓库路径
    /// - Returns: true 表示远端有新提交
    func hasRemoteChanges(localPath: URL) -> Bool {
        // 先 fetch 最新引用
        guard case .success = fetch(at: localPath) else {
            return false
        }

        // 获取本地 HEAD 的 commit hash
        guard let localHead = commitHash(at: localPath, ref: "HEAD") else {
            return false
        }

        // 获取远端跟踪分支的 commit hash
        guard let branch = currentBranch(at: localPath) else {
            return false
        }
        guard let remoteHead = commitHash(at: localPath, ref: "origin/\(branch)") else {
            return false
        }

        // 比较两个 hash 是否相同
        return localHead != remoteHead
    }

    /// 检测是否有本地未提交或未推送的变更
    /// - Parameter localPath: 本地仓库路径
    /// - Returns: true 表示有本地变更
    func hasLocalChanges(localPath: URL) -> Bool {
        // 检查工作区是否有未提交的变更
        let currentStatus: GitStatus
        switch status(at: localPath) {
        case .success(let s):
            currentStatus = s
        case .failure:
            return false
        }
        if !currentStatus.isClean {
            return true
        }

        // 检查是否有未推送的提交
        guard let branch = currentBranch(at: localPath) else {
            return false
        }

        let result = executeGit(
            args: ["log", "origin/\(branch)..HEAD", "--oneline"],
            in: localPath
        )

        switch result {
        case .success(let output):
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .failure:
            return false
        }
    }

    // MARK: - 提交与变基

    /// 提交所有变更（add -A + commit）
    /// - Parameters:
    ///   - at: 本地仓库路径
    ///   - message: 提交信息
    /// - Returns: 提交信息或错误
    func commitAll(at path: URL, message: String) -> Result<String, GitError> {
        // 确保存在 .gitignore 并排除常见无关文件
        ensureGitignore(at: path)

        // 先暂存所有变更
        switch executeGit(args: ["add", "-A"], in: path) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        // 执行提交
        return executeGit(args: ["commit", "-m", message], in: path)
    }

    /// 执行 rebase 操作
    /// - Parameters:
    ///   - at: 本地仓库路径
    ///   - onto: 目标分支或 commit
    /// - Returns: 命令输出或错误
    func rebase(at path: URL, onto: String) -> Result<String, GitError> {
        let result = executeGit(args: ["rebase", onto], in: path)
        switch result {
        case .failure:
            // 只有确认存在冲突标记时才 abort，避免误中止其他失败原因
            let conflictMarkers = ["CONFLICT", "conflict", "could not apply", "Failed to merge"]
            // 检查 git status 输出中是否有冲突指示
            let statusResult = executeGit(args: ["status"], in: path)
            let hasConflict: Bool
            switch statusResult {
            case .success(let output):
                hasConflict = conflictMarkers.contains { output.localizedCaseInsensitiveContains($0) }
            case .failure:
                hasConflict = false
            }
            if hasConflict {
                _ = executeGit(args: ["rebase", "--abort"], in: path)
            }
            return result
        case .success:
            return result
        }
    }

    /// 检测仓库是否存在合并冲突
    /// - Parameter at: 本地仓库路径
    /// - Returns: true 表示有冲突
    func detectConflict(at path: URL) -> Bool {
        switch status(at: path) {
        case .success(let currentStatus):
            return currentStatus.hasConflicts
        case .failure:
            return false
        }
    }

    // MARK: - 私有辅助方法

    /// 获取指定引用的 commit hash
    /// - Parameters:
    ///   - at: 本地仓库路径
    ///   - ref: Git 引用（如 HEAD、origin/main 等）
    /// - Returns: commit hash 字符串，失败返回 nil
    func commitHash(at path: URL, ref: String = "HEAD") -> String? {
        let result = executeGit(args: ["rev-parse", ref], in: path)
        switch result {
        case .success(let output):
            let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return hash.isEmpty ? nil : hash
        case .failure:
            return nil
        }
    }

    /// 解析 git status --porcelain 输出
    /// 格式说明：每行以 XY 开头，X 为暂存区状态，Y 为工作区状态
    /// 例如：M  file.txt（已修改已暂存）、 M file.txt（已修改未暂存）、?? file.txt（未跟踪）
    private func parseStatusOutput(_ output: String) -> GitStatus {
        var modified: [String] = []
        var added: [String] = []
        var deleted: [String] = []
        var untracked: [String] = []
        var conflicts: [String] = []

        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            // git status --porcelain 格式: XY filename（至少 3 个字符）
            guard line.count >= 3 else { continue }

            let indexStatus = line[line.index(line.startIndex, offsetBy: 0)]
            let workTreeStatus = line[line.index(line.startIndex, offsetBy: 1)]
            let filePath = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)

            // 冲突标记：UU（双方修改）、AA（双方添加）、DD（双方删除）
            // UD（我们修改，他们删除）、DU（我们删除，他们修改）
            if indexStatus == "U" || workTreeStatus == "U" ||
                (indexStatus == "A" && workTreeStatus == "A") ||
                (indexStatus == "D" && workTreeStatus == "D") {
                conflicts.append(filePath)
                continue
            }

            switch (indexStatus, workTreeStatus) {
            case ("?", "?"):
                untracked.append(filePath)
            case (" ", "M"), ("M", " "):
                modified.append(filePath)
            case ("A", " "):
                added.append(filePath)
            case ("D", " "), (" ", "D"):
                deleted.append(filePath)
            case ("M", "M"):
                modified.append(filePath)
            case ("R", _):
                // 重命名操作：格式为 "old_path -> new_path"，提取新路径
                if let arrowIndex = filePath.range(of: " -> ") {
                    let newPath = String(filePath[arrowIndex.upperBound...])
                    modified.append(newPath)
                } else {
                    modified.append(filePath)
                }
            default:
                modified.append(filePath)
            }
        }

        return GitStatus(
            modified: modified,
            added: added,
            deleted: deleted,
            untracked: untracked,
            hasConflicts: !conflicts.isEmpty,
            conflictFiles: conflicts
        )
    }

    /// 构建包含额外 PATH 的环境变量
    private func enrichedEnvironment(for cwd: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let systemPaths = "/usr/bin:/bin:/usr/sbin:/sbin"
        if !extraPATHComponents.isEmpty {
            let combined = extraPATHComponents.joined(separator: ":") + ":" + systemPaths
            if let existing = env["PATH"] {
                env["PATH"] = "\(combined):\(existing)"
            } else {
                env["PATH"] = combined
            }
        }
        return env
    }

    /// 执行 git 命令并返回输出（同步版本，用于兼容现有调用链）
    /// 使用临时文件捕获 stdout/stderr，避免内存管道缓冲问题
    private func runGit(args: [String], in cwd: URL) throws -> (stdout: String, stderr: String) {
        try runGitBlocking(args: args, in: cwd)
    }

    /// 异步执行 git 命令，带超时保护（普通命令 30 秒，clone 120 秒）
    private func runGitAsync(args: [String], in cwd: URL, timeoutSeconds: TimeInterval = 30) async throws -> (stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let fm = FileManager.default
                process.currentDirectoryURL = cwd
                process.environment = self.enrichedEnvironment(for: cwd)
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git"] + args

                let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let stdoutURL = tempRoot.appendingPathComponent("gitsync-\(UUID().uuidString)-stdout.log")
                let stderrURL = tempRoot.appendingPathComponent("gitsync-\(UUID().uuidString)-stderr.log")

                fm.createFile(atPath: stdoutURL.path, contents: Data())
                fm.createFile(atPath: stderrURL.path, contents: Data())
                guard let stdoutHandle = try? FileHandle(forWritingTo: stdoutURL),
                      let stderrHandle = try? FileHandle(forWritingTo: stderrURL) else {
                    continuation.resume(throwing: GitError.commandFailed(command: "git", code: -1, output: "无法创建临时文件"))
                    return
                }

                process.standardOutput = stdoutHandle
                process.standardError = stderrHandle

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: GitError.commandFailed(command: "git", code: -1, output: error.localizedDescription))
                    return
                }

                // 超时保护：超时后 kill 进程
                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
                timer.schedule(deadline: .now() + timeoutSeconds)
                timer.setEventHandler {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                timer.resume()

                process.waitUntilExit()
                timer.cancel()

                try? stdoutHandle.synchronizeFile()
                try? stderrHandle.synchronizeFile()
                try? stdoutHandle.close()
                try? stderrHandle.close()

                let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
                let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
                try? fm.removeItem(at: stdoutURL)
                try? fm.removeItem(at: stderrURL)

                let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus != 0 {
                    let commandLine = (["git"] + args).joined(separator: " ")
                    let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
                    // 判断是否为超时导致的 kill
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: GitError.commandFailed(command: commandLine, code: -1, output: "命令超时（\(Int(timeoutSeconds))秒）: \(output)"))
                    } else {
                        continuation.resume(throwing: GitError.commandFailed(command: commandLine, code: process.terminationStatus, output: output))
                    }
                } else {
                    continuation.resume(returning: (stdout, stderr))
                }
            }
        }
    }

    /// 确保仓库根目录有 .gitignore，排除常见无关文件
    private func ensureGitignore(at path: URL) {
        let gitignoreURL = path.appendingPathComponent(".gitignore")
        let defaultEntries = [".DS_Store", "Thumbs.db", "*.swp", "*~", ".AppleDouble", ".LSOverride"]

        if FileManager.default.fileExists(atPath: gitignoreURL.path) {
            // 已有 .gitignore，检查是否需要追加 .DS_Store 等
            guard let existing = try? String(contentsOf: gitignoreURL, encoding: .utf8) else { return }
            var missing: [String] = []
            for entry in defaultEntries {
                if !existing.contains(entry) {
                    missing.append(entry)
                }
            }
            if !missing.isEmpty {
                let append = "\n# GitSync 自动添加\n" + missing.joined(separator: "\n") + "\n"
                if let handle = try? FileHandle(forWritingTo: gitignoreURL) {
                    handle.seekToEndOfFile()
                    if let data = append.data(using: .utf8) {
                        handle.write(data)
                    }
                    handle.closeFile()
                }
            }
        } else {
            // 不存在，创建默认 .gitignore
            let content = "# GitSync 自动创建\n" + defaultEntries.joined(separator: "\n") + "\n"
            try? content.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        }
    }

    /// 实际执行 git 命令的阻塞实现（供同步和异步版本共用）
    private func runGitBlocking(args: [String], in cwd: URL) throws -> (stdout: String, stderr: String) {
        let process = Process()
        let fm = FileManager.default
        process.currentDirectoryURL = cwd
        process.environment = enrichedEnvironment(for: cwd)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args

        // 使用临时文件捕获输出（参考 NookDesk ProcessRunner 模式）
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let stdoutURL = tempRoot.appendingPathComponent("gitsync-\(UUID().uuidString)-stdout.log")
        let stderrURL = tempRoot.appendingPathComponent("gitsync-\(UUID().uuidString)-stderr.log")

        fm.createFile(atPath: stdoutURL.path, contents: Data())
        fm.createFile(atPath: stderrURL.path, contents: Data())
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fm.removeItem(at: stdoutURL)
            try? fm.removeItem(at: stderrURL)
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()

        let stdoutData = try Data(contentsOf: stdoutURL)
        let stderrData = try Data(contentsOf: stderrURL)
        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let commandLine = (["git"] + args).joined(separator: " ")
            throw GitError.commandFailed(
                command: commandLine,
                code: process.terminationStatus,
                output: [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            )
        }

        return (stdout, stderr)
    }

    /// 统一执行 git 命令并返回 Result
    private func executeGit(args: [String], in path: URL) -> Result<String, GitError> {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return .failure(.pathNotFound(path: path.path))
        }

        do {
            let result = try runGit(args: args, in: path)
            return .success(result.stdout)
        } catch let error as GitError {
            return .failure(error)
        } catch {
            return .failure(.commandFailed(
                command: "git " + args.joined(separator: " "),
                code: -1,
                output: error.localizedDescription
            ))
        }
    }
}
