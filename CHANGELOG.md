# 更新日志 (CHANGELOG)

所有显著更改都会记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [0.1.0] - 2026-06-19

### 新增
- **菜单栏常驻**：macOS 13+ `MenuBarExtra` 菜单栏图标，一键访问所有项目
- **项目管理**：添加、删除、搜索 Git 仓库项目
- **自动同步**：可配置间隔（1/5/15/60 分钟）的定时自动同步
- **智能同步策略**：
  - 远端有更新时自动 `pull --rebase`
  - 本地有变更时自动 `commit` + `push`
  - 双方都有变更时 `commit` → `rebase` → `push`
  - 冲突检测与报告
- **GitHub 集成**：
  - GitHub REST API 仓库信息查询
  - 自动 Fork 非自有仓库
  - URL 解析（支持 HTTPS 和 SSH 格式）
  - Token 安全存储（Keychain）
- **同步历史**：记录每次同步的操作类型、结果、耗时、commit hash
- **状态检测**：实时检测本地/远端变更、冲突状态
- **文件操作**：在 Finder/终端中打开、复制 GitHub URL
- **设置面板**：同步目录配置、自动同步开关、GitHub Token 管理
- **数据持久化**：项目配置和同步历史以 JSON 存储在 Application Support
- **自动同步服务**：定时扫描所有项目并执行同步，支持暂停/恢复
- **系统通知**：UNUserNotificationCenter 推送同步完成、冲突、错误通知
- **网络监控**：NWPathMonitor 监听网络状态，断网自动暂停，恢复自动继续
