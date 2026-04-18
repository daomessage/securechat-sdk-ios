import Foundation

/// WebSocket 传输层（对标 Android WSTransport）
///
/// 基于 Apple 标准的 `URLSessionWebSocketTask` 实现；不依赖任何第三方库。
public actor WSTransport: NSObject, URLSessionWebSocketDelegate {

    public typealias NetworkStateHandler = @Sendable (NetworkState) -> Void
    public typealias MessageHandler = @Sendable (String) -> Void

    private var websocket: URLSessionWebSocketTask?
    private var url: String?
    private var receiveTask: Task<Void, Never>?

    private var networkStateHandlers: [UUID: NetworkStateHandler] = [:]
    private var messageHandlers: [UUID: MessageHandler] = [:]
    private var openHandlers: [UUID: @Sendable () -> Void] = [:]
    private var closeHandlers: [UUID: @Sendable () -> Void] = [:]
    private var goawayHandlers: [UUID: @Sendable (String) -> Void] = [:]

    public private(set) var networkState: NetworkState = .disconnected(retryCount: 0)

    private var reconnectCount = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay = 1.0  // 秒

    // URLSession 在连接时创建；actor-isolated var 是允许的
    private var session: URLSession?

    public override init() {
        super.init()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - URLSessionWebSocketDelegate
    // ──────────────────────────────────────────────────────────────────────

    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task {
            await self.handleWebSocketOpened()
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task {
            await self.handleWebSocketClosed(closeCode: closeCode)
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 连接管理
    // ──────────────────────────────────────────────────────────────────────

    /// 连接到服务器
    public func connect(uuid: String, token: String) {
        disconnect()

        // 注：token 走 Sec-WebSocket-Protocol `bearer,<jwt>` 子协议而非 URL 参数
        //      （?token= URL 降级通道已在 P3.1 安全加固中废弃）
        let wsURL = "wss://relay.daomessage.com/ws?uuid=\(uuid)"
        self.url = wsURL

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let newSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = newSession

        guard let url = URL(string: wsURL) else {
            emitNetworkState(.disconnected(retryCount: 0))
            return
        }

        var req = URLRequest(url: url)
        req.setValue("bearer,\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let ws = newSession.webSocketTask(with: req)
        self.websocket = ws
        ws.resume()

        emitNetworkState(.connecting)
        startHeartbeat()
        startReceiveLoop(websocket: ws)
    }

    /// 断开连接
    public func disconnect() {
        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
        receiveTask?.cancel()
        receiveTask = nil
        stopHeartbeat()
        emitNetworkState(.closed)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 发送消息
    // ──────────────────────────────────────────────────────────────────────

    /// 发送消息
    public func send(_ message: String) async {
        guard let ws = websocket else {
            return
        }
        do {
            try await ws.send(.string(message))
        } catch {
            print("WebSocket 发送失败: \(error)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 事件订阅
    // ──────────────────────────────────────────────────────────────────────

    /// 监听网络状态变更
    public func onNetworkStateChange(_ handler: @escaping NetworkStateHandler) -> UUID {
        let id = UUID()
        networkStateHandlers[id] = handler
        return id
    }

    /// 监听消息
    public func onMessage(_ handler: @escaping MessageHandler) -> UUID {
        let id = UUID()
        messageHandlers[id] = handler
        return id
    }

    /// 监听连接打开
    public func onOpen(_ handler: @Sendable @escaping () -> Void) -> UUID {
        let id = UUID()
        openHandlers[id] = handler
        return id
    }

    /// 监听连接关闭
    public func onClose(_ handler: @Sendable @escaping () -> Void) -> UUID {
        let id = UUID()
        closeHandlers[id] = handler
        return id
    }

    /// 监听被踢下线
    public func onGoaway(_ handler: @Sendable @escaping (String) -> Void) -> UUID {
        let id = UUID()
        goawayHandlers[id] = handler
        return id
    }

    /// 取消订阅
    public func unsubscribe(_ id: UUID) {
        networkStateHandlers.removeValue(forKey: id)
        messageHandlers.removeValue(forKey: id)
        openHandlers.removeValue(forKey: id)
        closeHandlers.removeValue(forKey: id)
        goawayHandlers.removeValue(forKey: id)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 内部：消息接收循环
    // ──────────────────────────────────────────────────────────────────────

    private func startReceiveLoop(websocket ws: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        await self.handleIncomingMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleIncomingMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        print("WebSocket 接收失败: \(error)")
                        await self.handleWebSocketClosed(closeCode: .abnormalClosure)
                    }
                    break
                }
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        // 检查是否是 GOAWAY 帧
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String,
           type == "goaway" {
            let reason = json["reason"] as? String ?? "未知"
            for handler in goawayHandlers.values {
                handler(reason)
            }
            disconnect()
            return
        }

        // 分发给所有消息监听器
        for handler in messageHandlers.values {
            handler(text)
        }
    }

    private func handleWebSocketOpened() {
        reconnectCount = 0
        emitNetworkState(.connected)
        for handler in openHandlers.values {
            handler()
        }
    }

    private func handleWebSocketClosed(closeCode: URLSessionWebSocketTask.CloseCode) {
        stopHeartbeat()
        receiveTask?.cancel()
        receiveTask = nil

        // 判断是否需要重新连接
        if closeCode == .goingAway || closeCode == .normalClosure {
            emitNetworkState(.closed)
        } else if reconnectCount < maxReconnectAttempts {
            // 指数退避重连
            reconnectCount += 1
            let delay = baseReconnectDelay * pow(2.0, Double(reconnectCount - 1))
            scheduleReconnect(after: delay)
        } else {
            emitNetworkState(.disconnected(retryCount: reconnectCount))
        }

        for handler in closeHandlers.values {
            handler()
        }
    }

    private func scheduleReconnect(after delay: TimeInterval) {
        emitNetworkState(.disconnected(retryCount: reconnectCount))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.attemptReconnect()
        }
    }

    private func attemptReconnect() {
        guard let url = url else { return }
        // 从 URL 中提取 uuid，token 因已不再走 URL 参数，需要上层重新提供
        // 这里简化处理：仅使用 uuid 重建 URL；token 由 SecureChatClient.connect() 重新 setToken。
        if let components = URLComponents(string: url),
           let queryItems = components.queryItems {
            var uuid = ""
            for item in queryItems where item.name == "uuid" {
                uuid = item.value ?? ""
            }
            if !uuid.isEmpty {
                // 无 token 的纯重连仅在 auth 层主动提供 token 后才实际建连
                // 为简单起见这里直接给空 token，上层会在收到 disconnected 后重新调用 connect
                emitNetworkState(.disconnected(retryCount: reconnectCount))
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - 心跳和状态管理
    // ──────────────────────────────────────────────────────────────────────

    private var heartbeatTask: Task<Void, Never>?

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30 秒
                if !Task.isCancelled {
                    await self.send("{\"type\":\"ping\"}")
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func emitNetworkState(_ state: NetworkState) {
        self.networkState = state
        for handler in networkStateHandlers.values {
            handler(state)
        }
    }
}
