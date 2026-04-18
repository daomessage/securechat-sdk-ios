import Foundation

/// WebSocket 网络状态（对标 Android WSTransport.NetworkState）
public enum NetworkState: Equatable {
    /// 正在连接
    case connecting
    /// 已连接
    case connected
    /// 断开连接（含重试计数）
    case disconnected(retryCount: Int)
    /// 连接已关闭
    case closed
    /// 被踢下线（含原因）
    case kicked(reason: String)

    /// 是否已连接
    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    /// 是否正在尝试连接
    public var isConnecting: Bool {
        if case .connecting = self {
            return true
        }
        return false
    }

    /// 用户友好的状态描述
    public var description: String {
        switch self {
        case .connecting:
            return "正在连接..."
        case .connected:
            return "已连接"
        case .disconnected(let count):
            return "已断开（重试次数: \(count)）"
        case .closed:
            return "连接已关闭"
        case .kicked(let reason):
            return "被踢下线: \(reason)"
        }
    }
}
