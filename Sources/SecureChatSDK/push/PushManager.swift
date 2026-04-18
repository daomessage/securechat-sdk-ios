import Foundation

/// 推送管理器（对标 Android PushManager）
public actor PushManager {

    private let http: HttpClient

    public init(http: HttpClient) {
        self.http = http
    }

    /// 注册 APNs 推送凭证
    /// iOS 应用需要在 AppDelegate 中获取 APNs token，然后调用此方法
    public func registerAPNsToken(_ token: String) async throws {
        struct RegisterPushRequest: Codable {
            let deviceToken: String
            let platform: String

            enum CodingKeys: String, CodingKey {
                case deviceToken = "device_token"
                case platform
            }
        }

        let req = RegisterPushRequest(deviceToken: token, platform: "ios")
        try await http.postVoid("/api/v1/push/register", body: req)
    }

    /// 禁用推送
    public func disablePush() async throws {
        try await http.postVoid("/api/v1/push/disable", body: [:] as [String: String])
    }
}
