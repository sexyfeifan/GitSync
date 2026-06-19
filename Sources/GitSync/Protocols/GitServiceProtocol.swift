// GitServiceProtocol.swift
// Git 服务协议抽象，便于测试和替换实现

import Foundation

/// Git 服务协议
/// 定义所有 Git CLI 操作的接口
protocol GitServiceProtocol {
    /// 克隆远程仓库到本地目录
    func clone(url: String, to: URL) -> Result<Void, GitError>

    /// 拉取远程更新（使用 rebase 策略）
    func pull(at path: URL, branch: String?) -> Result<String, GitError>

    /// 推送本地提交到远程
    func push(at path: URL, branch: String?) -> Result<String, GitError>

    /// 从远程获取最新引用（不合并）
    func fetch(at path: URL) -> Result<Void, GitError>

    /// 获取工作区状态
    func status(at path: URL) -> GitStatus

    /// 获取当前分支名
    func currentBranch(at path: URL) -> String?

    /// 检测是否有远端变更
    func hasRemoteChanges(localPath: URL) -> Bool

    /// 检测是否有本地未提交或未推送的变更
    func hasLocalChanges(localPath: URL) -> Bool

    /// 提交所有变更（add -A + commit）
    func commitAll(at path: URL, message: String) -> Result<String, GitError>

    /// 执行 rebase 操作
    func rebase(at path: URL, onto: String) -> Result<String, GitError>

    /// 检测仓库是否存在合并冲突
    func detectConflict(at path: URL) -> Bool

    /// 获取指定引用的 commit hash
    func commitHash(at path: URL, ref: String) -> String?
}

/// 提供默认参数值的扩展
extension GitServiceProtocol {
    func pull(at path: URL, branch: String? = nil) -> Result<String, GitError> {
        pull(at: path, branch: branch)
    }

    func push(at path: URL, branch: String? = nil) -> Result<String, GitError> {
        push(at: path, branch: branch)
    }

    func commitHash(at path: URL) -> String? {
        commitHash(at: path, ref: "HEAD")
    }
}

/// 让 GitService 遵循协议
extension GitService: GitServiceProtocol {}
