# GitSync

> macOS 菜单栏 Git 同步工具 —— 一键管理多个 GitHub 仓库的本地同步

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

GitSync 是一个运行在 macOS 菜单栏的轻量级工具，帮助你自动管理和同步多个 Git/GitHub 仓库。无需打开终端或 IDE，即可完成 pull、push、rebase 等常见操作。

---

## 功能特性

- **菜单栏常驻**：随时查看和操作所有项目，不占用 Dock 栏位
- **智能同步**：自动检测本地/远端变更，选择最优同步策略
  - 仅远端更新 → `pull --rebase`
  - 仅本地变更 → 自动 `commit` + `push`
  - 双方变更 → `commit` → `rebase` → `push`
  - 冲突检测与报告
- **自动定时同步**：可配置 1/5/15/60 分钟间隔，支持暂停/恢复
- **系统通知**：同步完成、冲突、错误的 macOS 原生通知
- **网络感知**：断网自动暂停同步，网络恢复自动继续
- **GitHub 集成**：
  - 一键添加仓库（输入 URL 自动解析）
  - 非自有仓库自动 Fork
  - Token 安全存储于 Keychain
- **同步历史**：记录每次操作的类型、结果、耗时、commit hash
- **项目管理**：搜索、排序、批量同步
- **快捷操作**：在 Finder/终端中打开、复制 GitHub URL
- **数据持久化**：配置和历史以 JSON 存储于 `~/Library/Application Support/GitSync/`

## 截图

> 菜单栏弹出窗口，显示项目列表和同步状态：

```
┌─────────────────────────────┐
│ 🔍 搜索项目...              │
├─────────────────────────────┤
│ ✅ MyRepo        3 分钟前   │
│ ⬇️  SomeLib       1 小时前  │
│ ⚠️  Conflict      冲突      │
├─────────────────────────────┤
│ [全部同步]        [设置] [退出]│
└─────────────────────────────┘
```

> 项目详情视图，显示同步状态、本地变更和操作按钮。

---

## 安装

### 从 GitHub Releases 下载

1. 前往 [Releases](https://github.com/nookdesk-collab/GitSync/releases) 页面
2. 下载最新版本的 `GitSync.app.zip`
3. 解压后拖入 `/Applications` 目录
4. 首次打开需在「系统设置 → 隐私与安全性」中允许运行

### 从源码构建

**前置条件：**
- macOS 13 Ventura 或更高版本
- Xcode 15+ 或 Swift 5.9+ 工具链

```bash
# 克隆仓库
git clone https://github.com/nookdesk-collab/GitSync.git
cd GitSync

# 构建 Release 版本
swift build -c release

# 可执行文件位于
# .build/release/GitSync
```

**打包为 .app（可选）：**

```bash
# 使用 Xcode 打开 Package.swift，Product → Archive
# 或使用 create-dmg 等工具创建安装包
```

---

## 使用说明

### 首次启动

1. 启动 GitSync 后，菜单栏会出现同步图标
2. 点击图标打开面板
3. 点击 **设置** → **GitHub** 标签页，输入你的 Personal Access Token
   - 需要 `repo` 权限（推荐使用 Fine-grained Token）
   - 获取地址：https://github.com/settings/tokens
4. 在 **通用** 标签页设置默认同步目录（默认 `~/GitHub`）

### 添加项目

1. 点击 **+** 按钮
2. 粘贴 GitHub 仓库 URL（支持 HTTPS 和 SSH 格式）
3. 点击 **检查** 查看仓库信息
4. 点击 **添加并同步**，自动克隆并开始同步

### 日常使用

- **自动同步**：默认开启，每 5 分钟检查一次远端更新
- **手动同步**：点击项目行的刷新图标，或底部的「全部同步」
- **查看状态**：图标颜色表示状态
  - 🟢 绿色 = 已同步
  - 🔵 蓝色 = 远端有更新
  - 🟠 橙色 = 本地有变更
  - 🔴 红色 = 冲突或错误
- **右键菜单**：在 Finder 打开、终端打开、复制 URL、删除项目
- **双击项目**：在 Finder 中打开本地目录

---

## 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI（macOS 13+ `MenuBarExtra`） |
| 架构模式 | MVVM（Store + 协议抽象 + 视图分层） |
| Git 操作 | `Process` 封装 git CLI 命令 |
| GitHub API | `URLSession` + async/await |
| 数据持久化 | JSON 文件（`Codable`） |
| Token 存储 | macOS Keychain（`Security` 框架） |
| 构建工具 | Swift Package Manager |

### 项目结构

```
GitSync/
├── Package.swift                       # SPM 配置
├── README.md
├── Sources/GitSync/
│   ├── GitSyncApp.swift                # 应用入口（仅 App 声明）
│   ├── Constants.swift                 # 全局常量集中管理
│   ├── Models/
│   │   ├── SyncProject.swift           # 项目数据模型
│   │   ├── SyncStatus.swift            # 同步状态枚举
│   │   ├── SyncHistory.swift           # 同步历史记录模型
│   │   └── AppResult.swift             # 统一结果类型（AppSyncResult + AppError）
│   ├── Views/                          # SwiftUI 视图层
│   │   ├── MenuBarView.swift           # 菜单栏主视图
│   │   ├── ProjectRowView.swift        # 项目行视图
│   │   └── SettingsView.swift          # 设置面板
│   ├── Protocols/                      # 协议抽象层（便于测试）
│   │   ├── GitServiceProtocol.swift    # Git 服务协议
│   │   ├── SyncEngineProtocol.swift    # 同步引擎协议
│   │   └── GitHubServiceProtocol.swift # GitHub 服务协议
│   ├── Services/
│   │   ├── GitService.swift            # Git CLI 封装
│   │   ├── SyncEngine.swift            # 同步引擎（策略决策）
│   │   ├── SyncResultHandler.swift     # 统一同步结果处理
│   │   ├── GitHubService.swift         # GitHub API 服务
│   │   ├── AutoSyncService.swift       # 自动同步定时服务
│   │   ├── NotificationService.swift   # 系统通知服务
│   │   └── NetworkMonitor.swift        # 网络状态监控
│   └── Stores/
│       ├── ProjectStore.swift          # 项目持久化存储
│       ├── SyncHistoryStore.swift      # 同步历史存储
│       └── AppSettings.swift           # 集中管理 @AppStorage 设置
```

---

## 开发指南

### 开发环境

1. 安装 Xcode 15+（含 Command Line Tools）
2. 克隆仓库
3. 打开 `Package.swift`：
   ```bash
   open Package.swift
   # 或
   xed .
   ```

### 构建与运行

```bash
# 调试构建
swift build

# 运行
swift run

# 使用 Xcode 运行（推荐，支持 SwiftUI Preview）
# Product → Run (⌘R)
```

### 调试技巧

- Git 命令输出通过临时文件捕获，日志在 `/tmp/gitsync-*.log`
- GitHub API 请求失败会打印到控制台 `[GitHubService]` 前缀
- 项目数据存储在 `~/Library/Application Support/GitSync/`

---

## 许可证

MIT License. 详见 [LICENSE](LICENSE) 文件。
