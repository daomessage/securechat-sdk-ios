import Foundation

/// 靓号管理器（对标 Android VanityManager）
public actor VanityManager {

    private let http: HttpClient

    public init(http: HttpClient) {
        self.http = http
    }

    /// 搜索靓号
    public func search(query: String) async throws -> [VanityItem] {
        return try await http.get("/api/v1/vanity/search?q=\(query)") as [VanityItem]
    }

    /// 购买靓号（需要 JWT）
    public func purchase(aliasId: String) async throws -> PurchaseOrder {
        struct PurchaseVanityRequest: Codable {
            let aliasId: String

            enum CodingKeys: String, CodingKey {
                case aliasId = "alias_id"
            }
        }

        let req = PurchaseVanityRequest(aliasId: aliasId)
        return try await http.post("/api/v1/vanity/purchase", body: req) as PurchaseOrder
    }

    /// 绑定靓号（支付后调用）
    public func bind(orderId: String) async throws {
        struct BindVanityRequest: Codable {
            let orderId: String

            enum CodingKeys: String, CodingKey {
                case orderId = "order_id"
            }
        }

        let req = BindVanityRequest(orderId: orderId)
        try await http.postVoid("/api/v1/vanity/bind", body: req)
    }

    /// 查询订单状态
    public func getOrderStatus(orderId: String) async throws -> (status: String, aliasId: String) {
        struct OrderStatusResponse: Codable {
            let status: String
            let aliasId: String

            enum CodingKeys: String, CodingKey {
                case status
                case aliasId = "alias_id"
            }
        }

        let resp = try await http.get("/api/v1/vanity/order/\(orderId)/status") as OrderStatusResponse
        return (status: resp.status, aliasId: resp.aliasId)
    }
}
