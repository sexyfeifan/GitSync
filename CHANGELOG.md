# Changelog

## v0.2.2 (2026-06-19) — 一致性检查与死常量清理

### 一致性修复
- NotificationService 的 7 处 notification categoryIdentifier 改为引用 AppConstants 常量
- ProjectStore/SyncHistoryStore 的目录名和文件名改为引用 AppConstants 常量
- SyncHistoryStore.recentEntries 默认参数改用 AppConstants.recentHistoryCount
- SettingsView 的高度参数改用 AppConstants.settingsHeight
- GitHubService 的 Keychain accountName 改为引用 AppConstants.keychainAccountName
- 消除所有"死常量"，所有 Constants.swift 中的常量均被实际使用

### 文档更新
- CHANGELOG.md 添加 v0.2.2 条目
- README.md 项目结构补充 SyncEngineFactory.swift 和 Logger.swift

## v0.2.0 (2026-06-19) — 目标 8/10

### Architecture (5→8)
- 拆分 GitSyncApp.swift 到 Views/MenuBarView + ProjectRowView + SettingsView
- 提取 3 个协议：GitServiceProtocol、SyncEngineProtocol、GitHubServiceProtocol
- 统一结果类型 AppSyncResult + AppError
- 提取 Constants.swift 集中管理常量
- 统一 @AppStorage 到 AppSettings ObservableObject
- 提取 SyncResultHandler 消除三处重复同步逻辑
- 更新 README 与实际代码结构对齐

### Concurrency (5→8)
- GitService.extraPATHComponents 改为 let，标记 Sendable
- SyncHistoryStore.deinit 移除 entries 访问
- 所有 GitService 方法改为 async（withCheckedContinuation）
- 添加进程超时（默认 30s，clone 120s）

### Git Robustness (6→8)
- rebase abort 前检查冲突标记
- status() 返回 Result<GitStatus, GitError>
- clone 前检查目标路径
- commitAll 自动创建 .gitignore 排除 .DS_Store

### GitHub API (4→8)
- Token 统一 Keychain 存储，旧 UserDefaults 自动迁移
- Rate Limit 处理（解析 X-RateLimit-Remaining/Reset）
- 401 专用 .unauthorized 错误
- fetchCurrentUser 实例级缓存
- listUserRepos 添加 maxPages 限制
- User-Agent 动态版本号

### Data Persistence (7→8)
- SyncProject 添加 CodingKeys + decodeIfPresent 向后兼容
- 写入前备份（轮转 .bak.1/.bak.2/.bak.3）
- maxEntries 可配置（UserDefaults 100...10000）
- DateFormatter/RelativeDateTimeFormatter 全部 static let 缓存

### UX (5→8)
- 删除项目 Alert 确认（取消/仅删除/删除+本地文件）
- 测试连接实现真正的 GitHub API 验证
- 批量同步进度指示（当前项目名 + ProgressView）
- 错误信息分层（友好提示 + 可展开技术详情）
- 键盘快捷键（⌘S 同步/⌘N 添加/⌘Q 退出/⌘, 设置）
- 26 处 accessibilityLabel
- NSOpenPanel 改为 async

### Code Quality (6→8)
- 统一三套结果类型为 AppSyncResult
- 提取 SyncResultHandler 消除代码重复
- 所有 DateFormatter 改为 static let
- Magic number 提取到 Constants.swift

## v0.1.1 (2026-06-19)

- 修复 24 个问题（Token/并发/SF Symbol/单位/死代码清理）

## v0.1.0 (2026-06-19)

- 初始版本：菜单栏同步工具
