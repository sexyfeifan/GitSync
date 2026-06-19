# Changelog

## v0.1.1 (2026-06-19)

### Bug Fixes
- 修复 GitHub Token 键名不匹配导致 API 不工作
- 修复 Token 明文存储改为 Keychain 安全存储
- 修复 SF Symbol `arrow.branch` 不存在
- 修复自动同步间隔单位不一致（分钟→秒）
- 修复 `isOwnRepo` 语义错误（fork 仓库不再标记为自己的）
- 修复 ProjectDetailView 主线程阻塞（git status 改为异步）
- 修复 SyncEngine `@MainActor` 并发访问问题
- 修复 AutoSyncService/NetworkMonitor 线程安全问题
- 修复 GitService rename 操作解析错误
- 修复 AddProjectSheet 失败时仍 dismiss 的问题

### Improvements
- 删除 4 个死代码文件（净减 736 行）
- GitService 改为共享实例模式
- GitHubService 错误处理改为 Result 类型
- ProjectStore/SyncHistoryStore 添加 debounce 写入
- 所有用户可见字符串改为 `String(localized:)`
- 注入 AutoSyncService/NetworkMonitor/NotificationService
- 状态栏图标支持 5 种动态状态（含无网络）

## v0.1.0 (2026-06-19)

### Features
- 菜单栏常驻图标，动态显示同步状态
- 添加 GitHub 仓库 URL，自动克隆到本地
- 非自己的仓库自动 Fork
- 智能同步引擎：fetch → 检测变更 → pull/push/rebase
- 冲突检测与自动 rebase
- 自动定时同步（可暂停）
- 网络状态监控
- 系统通知（同步完成/有更新/冲突/错误）
- 今日同步统计
- 设置面板（同步目录/自动同步/GitHub Token）
