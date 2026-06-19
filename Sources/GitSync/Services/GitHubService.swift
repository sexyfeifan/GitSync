import Foundation
import Security
import os

// MARK: - GitHub 仓库模型

/// GitHub 仓库信息
struct GitHubRepo: Codable {
    /// 仓库名（不含 owner）
    let name: String
    /// 完整仓库名（owner/name）
    let fullName: String
    /// 仓库所有者信息
    let owner: GitHubOwner
    /// 仓库网页 URL
    let htmlURL: String
    /// 默认分支名
    let defaultBranch: String
    /// 是否为 fork 仓库
    let isFork: Bool
    /// 如果是 fork，指向父仓库信息
    let parent: GitHubParent?
    /// 仓库简介
    let description: String?
    /// 主要编程语言
    let language: String?
    /// Star 数量
    let stargazersCount: Int?
    /// Fork 数量
    let forksCount: Int?
    /// 开源许可证
    let license: GitHubLicense?
    /// 最后推送时间
    let pushedAt: String?

    /// JSON 解码键映射
    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case owner
        case htmlURL = "html_url"
        case defaultBranch = "default_branch"
        case isFork = "fork"
        case parent
        case description
        case language
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case license
        case pushedAt = "pushed_at"
    }
}

/// GitHub 仓库所有者
struct GitHubOwner: Codable {
    /// 用户名
    let login: String
}

/// GitHub 父仓库信息（fork 时存在）
struct GitHubParent: Codable {
    /// 仓库名
    let name: String
    /// 完整仓库名
    let fullName: String
    /// 所有者
    let owner: GitHubOwner

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case owner
    }
}

/// GitHub 许可证信息
struct GitHubLicense: Codable {
    let key: String
    let name: String
    let spdxID: String?

    enum CodingKeys: String, CodingKey {
        case key
        case name
        case spdxID = "spdx_id"
    }
}

// MARK: - GitHub 服务错误

/// GitHub 用户信息（用于测试连接返回）
struct GitHubUserInfo: Codable {
    /// 用户名
    let login: String
    /// 头像 URL
    let avatarURL: String

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}

/// GitHub API 相关错误，保留完整错误上下文
enum GitHubServiceError: LocalizedError {
    /// 缓存的短时间格式化器（避免每次创建新实例）
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    /// URL 格式无效
    case invalidURL(url: String)
    /// HTTP 请求返回非成功状态码
    case httpError(statusCode: Int, body: String)
    /// Token 保存到 Keychain 失败
    case tokenSaveFailed(status: OSStatus)
    /// JSON 解码失败
    case decodingFailed(url: String, underlying: Error)
    /// 网络请求异常
    case networkError(url: String, underlying: Error)
    /// 认证失败（401）
    case unauthorized
    /// API 速率限制（403 且 X-RateLimit-Remaining=0）
    case rateLimited(resetDate: Date)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return String(localized: "无效的 URL：\(url)")
        case .httpError(let statusCode, let body):
            // 截断过长的响应体，保留前 200 字符
            let truncated = body.count > 200 ? String(body.prefix(200)) + "..." : body
            return String(localized: "HTTP 请求失败（状态码 \(statusCode)）：\(truncated)")
        case .tokenSaveFailed(let status):
            return String(localized: "保存 GitHub Token 到 Keychain 失败（OSStatus: \(status)）")
        case .decodingFailed(let url, let underlying):
            return String(localized: "响应解析失败（\(url)）：\(underlying.localizedDescription)")
        case .networkError(let url, let underlying):
            return String(localized: "网络请求失败（\(url)）：\(underlying.localizedDescription)")
        case .unauthorized:
            return String(localized: "GitHub 认证失败（401）：请检查 Token 是否有效")
        case .rateLimited(let resetDate):
            return String(localized: "GitHub API 速率限制已达上限，将在 \(Self.shortTimeFormatter.string(from: resetDate)) 后重置")
        }
    }
}

// MARK: - GitHub API 服务

/// GitHub REST API 封装，使用 URLSession + async/await
/// Token 从 UserDefaults 或 Keychain 读取
/// 标记 @MainActor 保护缓存属性（cachedCurrentUser / hasCachedUser）的并发访问安全
@MainActor
final class GitHubService {
    /// Token 版本号：每次 saveToken 时递增，实例检测到版本变化时清空用户缓存
    /// 使用 OSAllocatedUnfairLock 保证线程安全
    private static let tokenVersionLock = OSAllocatedUnfairLock(initialState: UInt64(0))
    nonisolated(unsafe) static var tokenVersion: UInt64 {
        get { tokenVersionLock.withLock { $0 } }
        set { tokenVersionLock.withLock { $0 = newValue } }
    }

    /// API 基础 URL
    private let baseURL = AppConstants.gitHubAPIBaseURL
    /// GitHub Personal Access Token
    private let token: String?
    /// URL 会话
    private let session: URLSession
    /// fetchCurrentUser 的缓存结果（实例级缓存）
    private var cachedCurrentUser: String?
    /// 缓存是否已填充
    private var hasCachedUser: Bool = false
    /// 记录创建缓存时的 token 版本号，用于检测 token 是否已更换
    private var cachedTokenVersion: UInt64 = 0

    /// 初始化 GitHub 服务
    /// - Parameters:
    ///   - token: 显式传入 token（为 nil 时自动从存储读取）
    ///   - session: URLSession 实例
    init(token: String? = nil, session: URLSession = .shared) {
        self.token = token ?? Self.loadTokenFromStorage()
        self.session = session
        self.cachedTokenVersion = Self.tokenVersion
    }

    // MARK: - 仓库操作

    /// 获取仓库信息
    /// - Parameters:
    ///   - owner: 仓库所有者
    ///   - name: 仓库名
    /// - Returns: Result 包含仓库信息或错误
    func fetchRepo(owner: String, name: String) async -> Result<GitHubRepo, GitHubServiceError> {
        let url = "\(baseURL)/repos/\(owner)/\(name)"
        return await performRequest(url: url, method: "GET")
    }

    /// 获取仓库 README 内容（Base64 解码后的纯文本）
    func fetchREADME(owner: String, name: String) async -> String? {
        let url = "\(baseURL)/repos/\(owner)/\(name)/readme"
        struct ReadmeResponse: Codable {
            let content: String
            let encoding: String
        }
        let result: Result<ReadmeResponse, GitHubServiceError> = await performRequest(url: url, method: "GET")
        switch result {
        case .success(let resp):
            let cleaned = resp.content.replacingOccurrences(of: "\n", with: "")
            guard let data = Data(base64Encoded: cleaned),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        case .failure:
            return nil
        }
    }

    /// Fork 一个仓库到当前用户账户
    /// - Parameters:
    ///   - owner: 源仓库所有者
    ///   - name: 源仓库名
    /// - Returns: Result 包含 fork 后的仓库信息或错误
    func forkRepo(owner: String, name: String) async -> Result<GitHubRepo, GitHubServiceError> {
        let url = "\(baseURL)/repos/\(owner)/\(name)/forks"
        return await performRequest(url: url, method: "POST")
    }

    /// 列出当前用户的所有仓库
    /// - Parameter maxPages: 最大分页数（默认 10，每页 100 个，即最多 1000 个仓库）
    /// - Returns: 仓库列表
    func listUserRepos(maxPages: Int = 10) async -> [GitHubRepo] {
        // 分页获取所有仓库（每页 100 个）
        var allRepos: [GitHubRepo] = []
        var page = 1

        while page <= maxPages {
            let url = "\(baseURL)/user/repos?per_page=100&page=\(page)&sort=updated"
            let result: Result<[GitHubRepo], GitHubServiceError> = await performRequest(url: url, method: "GET")
            switch result {
            case .success(let repos):
                allRepos.append(contentsOf: repos)
                // 如果返回数量不足 100，说明已经是最后一页
                if repos.count < 100 {
                    return allRepos
                }
                page += 1
            case .failure:
                // 遇到错误时返回已获取的部分
                return allRepos
            }
        }
        return allRepos
    }

    /// 检查指定 owner 是否为当前用户（即是否是自己的仓库）
    /// - Parameter owner: 仓库所有者用户名
    /// - Returns: true 表示是当前用户的仓库
    func checkIsOwnRepo(owner: String) async -> Bool {
        guard let currentUser = await fetchCurrentUser() else {
            return false
        }
        return owner.lowercased() == currentUser.lowercased()
    }

    /// 测试连接：调用 GitHub API /user 获取当前用户信息
    /// - Returns: Result 包含用户信息（用户名、头像 URL）或错误
    func testConnection() async -> Result<GitHubUserInfo, GitHubServiceError> {
        let url = "\(baseURL)/user"
        return await performRequest(url: url, method: "GET")
    }

    /// 检查当前用户的 fork 是否已存在
    /// - Parameters:
    ///   - owner: 源仓库所有者
    ///   - name: 源仓库名
    /// - Returns: true 表示 fork 已存在
    func checkForkExists(owner: String, name: String) async -> Bool {
        // 先获取当前用户名
        guard let currentUser = await fetchCurrentUser() else {
            return false
        }
        let result = await fetchRepo(owner: currentUser, name: name)
        switch result {
        case .success(let repo):
            return repo.isFork
        case .failure:
            return false
        }
    }

    // MARK: - URL 解析

    /// 从仓库 URL 中解析 owner 和 name（静态方法，无需实例）
    /// 支持 HTTPS 和 SSH 格式：
    /// - https://github.com/owner/repo.git
    /// - git@github.com:owner/repo.git
    /// - https://github.com/owner/repo
    /// - Parameter url: 仓库 URL 字符串
    /// - Returns: (owner, name) 元组，解析失败返回 nil
    nonisolated static func parseRepoURL(_ url: String) -> (owner: String, name: String)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)

        // 处理 SSH 格式：git@github.com:owner/repo.git
        if trimmed.hasPrefix("git@github.com:") {
            let rest = trimmed.replacingOccurrences(of: "git@github.com:", with: "")
            let parts = rest.split(separator: "/")
            guard parts.count == 2 else { return nil }
            let owner = String(parts[0])
            let name = stripGitSuffix(String(parts[1]))
            return (owner, name)
        }

        // 处理 HTTPS 格式：https://github.com/owner/repo.git
        guard let parsedURL = URL(string: trimmed),
              parsedURL.host?.contains("github.com") == true else {
            return nil
        }
        let components = parsedURL.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }
        let owner = components[0]
        let name = stripGitSuffix(components[1])
        return (owner, name)
    }

    // MARK: - 私有辅助方法

    /// 去掉仓库名末尾的 .git 后缀
    nonisolated private static func stripGitSuffix(_ name: String) -> String {
        guard name.hasSuffix(".git") else { return name }
        return String(name.dropLast(4))
    }

    /// 获取当前登录用户的用户名（带实例级缓存）
    private func fetchCurrentUser() async -> String? {
        // 检测 token 是否已更换，如果已更换则清空缓存
        if Self.tokenVersion != cachedTokenVersion {
            cachedCurrentUser = nil
            hasCachedUser = false
            cachedTokenVersion = Self.tokenVersion
        }
        if hasCachedUser {
            return cachedCurrentUser
        }
        let url = "\(baseURL)/user"
        struct UserResponse: Codable {
            let login: String
        }
        let result: Result<UserResponse, GitHubServiceError> = await performRequest(url: url, method: "GET")
        switch result {
        case .success(let user):
            cachedCurrentUser = user.login
            hasCachedUser = true
            return user.login
        case .failure:
            return nil
        }
    }

    /// 执行 GitHub API 请求并解码响应
    /// - Parameters:
    ///   - url: 完整 API URL
    ///   - method: HTTP 方法
    /// - Returns: Result 包含解码后的对象或具体错误信息
    private func performRequest<T: Decodable>(url: String, method: String) async -> Result<T, GitHubServiceError> {
        guard let requestURL = URL(string: url) else {
            return .failure(.invalidURL(url: url))
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")

        // 添加认证 header（如果有 token）
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)

            // 检查 HTTP 状态码
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkError(url: url, underlying: URLError(.badServerResponse)))
            }

            // 检查 Rate Limit（解析 X-RateLimit-Remaining 和 X-RateLimit-Reset）
            if let remainingStr = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
               let remaining = Int(remainingStr), remaining == 0 {
                let resetTimestamp = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset")
                    .flatMap { Double($0) } ?? 0
                let resetDate = Date(timeIntervalSince1970: resetTimestamp)
                return .failure(.rateLimited(resetDate: resetDate))
            }

            // 401 专用错误处理
            if httpResponse.statusCode == 401 {
                return .failure(.unauthorized)
            }

            // 成功状态码范围：200-299
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? ""
                return .failure(.httpError(statusCode: httpResponse.statusCode, body: errorBody))
            }

            // 解码 JSON 响应
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(T.self, from: data)
            return .success(decoded)
        } catch {
            return .failure(.networkError(url: url, underlying: error))
        }
    }

    // MARK: - Token 存储

    /// 从存储中读取 GitHub Token（统一从 Keychain 读取）
    nonisolated static func loadTokenFromStorage() -> String? {
        if let keychainToken = loadTokenFromKeychain(), !keychainToken.isEmpty {
            return keychainToken
        }
        // 迁移旧 UserDefaults token 到 Keychain
        if let oldToken = UserDefaults.standard.string(forKey: AppConstants.gitHubTokenUserDefaultsKey), !oldToken.isEmpty {
            saveTokenToKeychain(oldToken)
            UserDefaults.standard.removeObject(forKey: AppConstants.gitHubTokenUserDefaultsKey)
            return oldToken
        }
        return nil
    }

    /// 从 Keychain 读取 Token
    nonisolated static func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainServiceName,
            kSecAttrAccount as String: AppConstants.keychainAccountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 保存 Token 到 Keychain
    @discardableResult
    nonisolated static func saveTokenToKeychain(_ token: String) -> Bool {
        tokenVersion &+= 1
        let data = token.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainServiceName,
            kSecAttrAccount as String: AppConstants.keychainAccountName
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            let addStatus = SecItemAdd(create as CFDictionary, nil)
            return addStatus == errSecSuccess || addStatus == errSecDuplicateItem
        }
        return updateStatus == errSecSuccess
    }

    /// 从 Keychain 删除 Token
    nonisolated static func deleteTokenFromKeychain() {
        tokenVersion &+= 1
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainServiceName,
            kSecAttrAccount as String: AppConstants.keychainAccountName
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// 保存 GitHub Token（兼容旧调用）
    nonisolated static func saveToken(_ token: String) throws {
        guard saveTokenToKeychain(token) else {
            throw GitHubServiceError.tokenSaveFailed(status: errSecInternalError)
        }
    }
}
