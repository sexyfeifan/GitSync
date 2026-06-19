// GitServiceProtocol.swift
// Git 服务协议抽象，便于测试和替换实现
// 所有方法均为 async，统一走带超时保护的异步路径

import Foundation

/// Git 服务协议
/// 定义所有 Git CLI 操作的接口
protocol GitServiceProtocol {
    /// 克隆远程仓库到本地目录
    func clone(url: String, to: URL) async -> Result<Void, GitError>

    /// 拉取远程更新（使用 rebase 策略）
    func pull(at path: URL, branch: String?) async -> Result<String, GitError>

    /// 推送本地提交到远程
    func push(at path: URL, branch: String?) async -> Result<String, GitError>

    /// 从远程获取最新引用（不合并）
    func fetch(at path: URL) async -> Result<Void, GitError>

    /// 获取工作区状态（返回 Result，与 GitService 实现一致）
    func status(at path: URL) async -> Result<GitStatus, GitError>

    /// 获取当前分支名
    func currentBranch(at path: URL) async -> String?

    /// 检测是否有远端变更
    func hasRemoteChanges(localPath: URL, skipFetch: Bool) async -> Bool

    /// 检测是否有本地未提交或未推送的变更
    func hasLocalChanges(localPath: URL) async -> Bool

    /// 提交所有变更（add -A + commit）
    func commitAll(at path: URL, message: String) async -> Result<String, GitError>

    /// 执行 rebase 操作
    func rebase(at path: URL, onto: String) async -> Result<String, GitError>

    /// 检测仓库是否存在合并冲突
    func detectConflict(at path: URL) async -> Bool

    /// 获取指定引用的 commit hash
    func commitHash(at path: URL, ref: String) async -> String?
}

/// 仅为 commitHash 提供默认参数的便利方法
/// 注意：pull/push 的 branch 默认值已在协议声明中通过参数签名区分，
/// 此处不再提供可能引起无限递归的同签名扩展
extension GitServiceProtocol {
    /// 获取 HEAD 的 commit hash（便捷方法）
    func commitHash(at path: URL) async -> String? {
        await commitHash(at: path, ref: "HEAD")
    }
}

/// 让 GitService 遵循协议
extension GitService: GitServiceProtocol {}
