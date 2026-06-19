import Foundation
import Security

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

    /// JSON 解码键映射
    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case owner
        case htmlURL = "html_url"
        case defaultBranch = "default_branch"
        case isFork = "fork"
        case parent
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

// MARK: - GitHub API 服务

/// GitHub REST API 封装，使用 URLSession + async/await
/// Token 从 UserDefaults 或 Keychain 读取
final class GitHubService {
    /// API 基础 URL
    private let baseURL = "https://api.github.com"
    /// GitHub Personal Access Token
    private let token: String?
    /// URL 会话
    private let session: URLSession

    /// 初始化 GitHub 服务
    /// - Parameters:
    ///   - token: 显式传入 token（为 nil 时自动从存储读取）
    ///   - session: URLSession 实例
    init(token: String? = nil, session: URLSession = .shared) {
        self.token = token ?? Self.loadTokenFromStorage()
        self.session = session
    }

    // MARK: - 仓库操作

    /// 获取仓库信息
    /// - Parameters:
    ///   - owner: 仓库所有者
    ///   - name: 仓库名
    /// - Returns: 仓库信息，失败返回 nil
    func fetchRepo(owner: String, name: String) async -> GitHubRepo? {
        let url = "\(baseURL)/repos/\(owner)/\(name)"
        return await performRequest(url: url, method: "GET")
    }

    /// Fork 一个仓库到当前用户账户
    /// - Parameters:
    ///   - owner: 源仓库所有者
    ///   - name: 源仓库名
    /// - Returns: fork 后的仓库信息，失败返回 nil
    func forkRepo(owner: String, name: String) async -> GitHubRepo? {
        let url = "\(baseURL)/repos/\(owner)/\(name)/forks"
        return await performRequest(url: url, method: "POST")
    }

    /// 列出当前用户的所有仓库
    /// - Returns: 仓库列表
    func listUserRepos() async -> [GitHubRepo] {
        // 分页获取所有仓库（每页 100 个）
        var allRepos: [GitHubRepo] = []
        var page = 1

        while true {
            let url = "\(baseURL)/user/repos?per_page=100&page=\(page)&sort=updated"
            guard let repos: [GitHubRepo] = await performRequest(url: url, method: "GET") else {
                break
            }
            allRepos.append(contentsOf: repos)
            // 如果返回数量不足 100，说明已经是最后一页
            if repos.count < 100 {
                break
            }
            page += 1
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
        let repo = await fetchRepo(owner: currentUser, name: name)
        return repo?.isFork == true
    }

    // MARK: - URL 解析

    /// 从仓库 URL 中解析 owner 和 name（静态方法，无需实例）
    /// 支持 HTTPS 和 SSH 格式：
    /// - https://github.com/owner/repo.git
    /// - git@github.com:owner/repo.git
    /// - https://github.com/owner/repo
    /// - Parameter url: 仓库 URL 字符串
    /// - Returns: (owner, name) 元组，解析失败返回 nil
    static func parseRepoURL(_ url: String) -> (owner: String, name: String)? {
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
    private static func stripGitSuffix(_ name: String) -> String {
        guard name.hasSuffix(".git") else { return name }
        return String(name.dropLast(4))
    }

    /// 获取当前登录用户的用户名
    private func fetchCurrentUser() async -> String? {
        let url = "\(baseURL)/user"
        struct UserResponse: Codable {
            let login: String
        }
        let user: UserResponse? = await performRequest(url: url, method: "GET")
        return user?.login
    }

    /// 执行 GitHub API 请求并解码响应
    /// - Parameters:
    ///   - url: 完整 API URL
    ///   - method: HTTP 方法
    /// - Returns: 解码后的对象，失败返回 nil
    private func performRequest<T: Decodable>(url: String, method: String) async -> T? {
        guard let requestURL = URL(string: url) else { return nil }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitSync/1.0", forHTTPHeaderField: "User-Agent")

        // 添加认证 header（如果有 token）
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)

            // 检查 HTTP 状态码
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }

            // 成功状态码范围：200-299
            guard (200...299).contains(httpResponse.statusCode) else {
                // 打印错误信息便于调试
                let errorBody = String(data: data, encoding: .utf8) ?? "无响应体"
                print("[GitHubService] 请求失败 (\(httpResponse.statusCode)): \(url)\n\(errorBody)")
                return nil
            }

            // 解码 JSON 响应
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            print("[GitHubService] 请求异常: \(url) - \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Token 存储

    /// 从存储中读取 GitHub Token
    /// 优先从 Keychain 读取，其次从 UserDefaults 读取
    private static func loadTokenFromStorage() -> String? {
        // 优先从 Keychain 读取
        if let keychainToken = loadFromKeychain(), !keychainToken.isEmpty {
            return keychainToken
        }
        // 回退到 UserDefaults
        return UserDefaults.standard.string(forKey: "GitSync.GitHubToken")
    }

    /// 从 Keychain 读取 GitHub Token
    private static func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.gitsync.github.token",
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// 保存 GitHub Token 到 Keychain
    /// - Parameter token: 要保存的 token
    /// - Throws: 保存失败时抛出错误
    static func saveToken(_ token: String) throws {
        let data = token.data(using: .utf8) ?? Data()

        // 先尝试更新已有条目
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.gitsync.github.token",
            kSecAttrAccount as String: "default"
        ]

        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecItemNotFound {
            // 条目不存在，创建新条目
            var create = query
            create[kSecValueData as String] = data
            let addStatus = SecItemAdd(create as CFDictionary, nil)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
                throw GitHubServiceError.tokenSaveFailed(status: addStatus)
            }
        }
    }
}

// MARK: - GitHub 服务错误

enum GitHubServiceError: LocalizedError {
    case tokenSaveFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .tokenSaveFailed(status):
            return "保存 GitHub Token 到 Keychain 失败（OSStatus: \(status)）"
        }
    }
}
