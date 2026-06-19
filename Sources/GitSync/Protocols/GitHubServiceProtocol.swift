// GitHubServiceProtocol.swift
// GitHub 服务协议抽象，便于测试和替换实现

import Foundation

/// GitHub 服务协议
/// 定义所有 GitHub API 操作的接口
protocol GitHubServiceProtocol {
    /// 获取仓库信息
    func fetchRepo(owner: String, name: String) async -> Result<GitHubRepo, GitHubServiceError>

    /// Fork 一个仓库到当前用户账户
    func forkRepo(owner: String, name: String) async -> Result<GitHubRepo, GitHubServiceError>

    /// 列出当前用户的所有仓库
    func listUserRepos(maxPages: Int) async -> [GitHubRepo]

    /// 检查指定 owner 是否为当前用户
    func checkIsOwnRepo(owner: String) async -> Bool

    /// 检查当前用户的 fork 是否已存在
    func checkForkExists(owner: String, name: String) async -> Bool

    /// 从仓库 URL 中解析 owner 和 name
    static func parseRepoURL(_ url: String) -> (owner: String, name: String)?
}

/// 让 GitHubService 遵循协议
extension GitHubService: GitHubServiceProtocol {}
