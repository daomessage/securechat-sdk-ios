import Foundation

/// 频道管理器（对标 Android ChannelsManager）
public actor ChannelsManager {

    private let http: HttpClient

    public init(http: HttpClient) {
        self.http = http
    }

    /// 搜索频道
    public func search(query: String) async throws -> [ChannelInfo] {
        return try await http.get("/api/v1/channels/search?q=\(query)") as [ChannelInfo]
    }

    /// 获取我的频道
    public func getMine() async throws -> [ChannelInfo] {
        return try await http.get("/api/v1/channels/mine") as [ChannelInfo]
    }

    /// 获取频道详情
    public func getDetail(channelId: String) async throws -> ChannelInfo {
        return try await http.get("/api/v1/channels/\(channelId)") as ChannelInfo
    }

    /// 创建频道，返回新建 channelId
    public func create(name: String, description: String, isPublic: Bool = true) async throws -> String {
        struct CreateChannelRequest: Codable {
            let name: String
            let description: String
            let isPublic: Bool

            enum CodingKeys: String, CodingKey {
                case name, description
                case isPublic = "is_public"
            }
        }

        let req = CreateChannelRequest(name: name, description: description, isPublic: isPublic)
        let resp = try await http.post("/api/v1/channels", body: req) as [String: String]
        return resp["channel_id"] ?? ""
    }

    /// 订阅频道
    public func subscribe(channelId: String) async throws {
        try await http.postVoid("/api/v1/channels/\(channelId)/subscribe", body: [:] as [String: String])
    }

    /// 取消订阅
    public func unsubscribe(channelId: String) async throws {
        try await http.delete("/api/v1/channels/\(channelId)/subscribe")
    }

    /// 发布频道消息，返回 postId
    public func postMessage(channelId: String, content: String, type: String = "text") async throws -> String {
        struct PostMessageRequest: Codable {
            let content: String
            let type: String
        }

        let req = PostMessageRequest(content: content, type: type)
        let resp = try await http.post("/api/v1/channels/\(channelId)/posts", body: req) as [String: String]
        return resp["post_id"] ?? ""
    }

    /// 获取频道帖子
    public func getPosts(channelId: String) async throws -> [ChannelPost] {
        return try await http.get("/api/v1/channels/\(channelId)/posts") as [ChannelPost]
    }

    /// 检查是否可发帖
    public func canPost(channelInfo: ChannelInfo?) -> Bool {
        guard let info = channelInfo else { return false }
        return info.role == "owner" || info.role == "moderator"
    }

    /// 将频道挂牌出售
    public func listForSale(channelId: String, priceUsdt: Int) async throws {
        struct ListForSaleRequest: Codable {
            let priceUsdt: Int

            enum CodingKeys: String, CodingKey {
                case priceUsdt = "price_usdt"
            }
        }

        let req = ListForSaleRequest(priceUsdt: priceUsdt)
        try await http.putVoid("/api/v1/channels/\(channelId)/forsale", body: req)
    }

    /// 购买频道
    public func buyChannel(channelId: String) async throws -> ChannelTradeOrder {
        return try await http.post("/api/v1/channels/\(channelId)/buy", body: [:] as [String: String]) as ChannelTradeOrder
    }

    /// 购买频道创建配额
    public func buyQuota() async throws -> ChannelTradeOrder {
        return try await http.post("/api/v1/channels/quota/buy", body: [:] as [String: String]) as ChannelTradeOrder
    }
}
