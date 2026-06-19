// NetworkMonitor.swift
// 网络状态监控服务，使用 NWPathMonitor 监听网络变化

import Foundation
import Network
import Combine

/// 网络状态监控器
/// 监听设备网络连接状态，网络断开时通知暂停同步，恢复时自动恢复
@MainActor
class NetworkMonitor: ObservableObject {
    /// 当前是否有网络连接
    @Published private(set) var isConnected: Bool = true

    /// 当前网络连接类型描述
    @Published private(set) var connectionType: String = "未知"

    /// 网络是否为受限模式（如蜂窝数据需付费）
    @Published private(set) var isExpensive: Bool = false

    /// 网络路径监控器（非隔离，用于底层回调）
    private let monitor = NWPathMonitor()

    /// 监控器专用队列
    private let queue = DispatchQueue(label: "com.gitsync.networkmonitor")

    /// 存储 Combine 订阅
    private var cancellables = Set<AnyCancellable>()

    /// 网络状态变化回调（供 AutoSyncService 使用）
    var onNetworkStatusChanged: ((Bool) -> Void)?

    init() {
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    /// 开始监听网络状态
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            let isExpensive = path.isExpensive
            let connectionType = Self.detectConnectionType(path: path)

            // 在主线程更新状态
            DispatchQueue.main.async {
                guard let self = self else { return }
                let wasConnected = self.isConnected
                self.isConnected = isConnected
                self.isExpensive = isExpensive
                self.connectionType = connectionType

                // 网络状态发生变化时触发回调
                if wasConnected != isConnected {
                    self.onNetworkStatusChanged?(isConnected)
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// 检测当前网络连接类型
    /// - Parameter path: NWPath 网络路径
    /// - Returns: 连接类型的中文描述
    private static func detectConnectionType(path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "Wi-Fi"
        } else if path.usesInterfaceType(.cellular) {
            return "蜂窝网络"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "有线网络"
        } else if path.usesInterfaceType(.loopback) {
            return "本地回环"
        } else {
            return "其他网络"
        }
    }

    /// 网络状态的图标名称
    var iconName: String {
        if !isConnected {
            return "wifi.slash"
        } else if isExpensive {
            return "wifi.exclamationmark"
        } else {
            return "wifi"
        }
    }

    /// 网络状态的中文描述
    var statusDescription: String {
        if !isConnected {
            return "无网络连接"
        } else if isExpensive {
            return "受限网络（\(connectionType)）"
        } else {
            return connectionType
        }
    }
}
