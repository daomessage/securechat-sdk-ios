# SecureChat SDK for iOS

完全零知识 E2EE 通讯协议的 iOS Swift 实现，对标 Android/TypeScript SDK。

## 概况

- **语言**：Swift 5.9+
- **最低支持**：iOS 16+
- **包管理**：Swift Package Manager
- **加密**：Apple CryptoKit（内置，无第三方依赖）
- **网络**：URLSession + WebSocket（原生）
- **存储**：文件系统持久化（CoreData 兼容接口）

## 快速开始

### 1. 添加依赖

在 `Package.swift` 或 Xcode 项目中添加：

```swift
.package(path: "./sdk-ios")
```

### 2. 初始化

```swift
import SecureChatSDK

// 创建或获取单例
let client = SecureChatClient.shared()

// 或创建实例
let client = SecureChatClient()
```

### 3. 新用户注册

```swift
// 生成助记词（必须备份！）
let mnemonic = KeyDerivation.newMnemonic()

// 注册账号
let aliasId = try await client.auth?.registerAccount(
    mnemonic: mnemonic,
    nickname: "你的昵称"
)

// 连接
await client.connect()
```

### 4. 老用户恢复

```swift
// 自动从本地数据库恢复
if let (aliasId, nickname) = try await client.restoreSession() {
    print("欢迎回来，\(nickname)！")
    await client.connect()
} else {
    print("首次使用，请注册")
}
```

### 5. 接收消息

```swift
let id = await client.onMessage { msg in
    print("来自 \(msg.fromAliasId ?? "?") 的消息：\(msg.text)")
    print("状态：\(msg.status)")
}

// 取消订阅（可选）
await client.unsubscribe(id)
```

### 6. 发送消息

```swift
let msgId = try await client.sendMessage(
    conversationId: "conv_id",
    toAliasId: "u87654321",
    text: "Hello, SecureChat!"
)

print("消息已发送：\(msgId)")
```

### 7. 其他操作

#### 好友管理
```swift
// 同步好友
let friends = try await client.contacts?.syncFriends()

// 发送好友请求
try await client.contacts?.sendFriendRequest(toAliasId: "u12345678")

// 查找用户
let user = try await client.contacts?.lookupUser(aliasId: "u87654321")
```

#### 频道功能
```swift
// 搜索频道
let channels = try await client.channels?.search(query: "技术")

// 订阅频道
try await client.channels?.subscribe(channelId: "ch_abc123")

// 发布消息
let (postId) = try await client.channels?.postMessage(
    channelId: "ch_abc123",
    content: "Hello Channel!"
) ?? ("",)
```

#### 靓号管理
```swift
// 搜索靓号
let vanities = try await client.vanity?.search(query: "lucky")

// 购买靓号（需要 JWT）
let order = try await client.vanity?.purchase(aliasId: "u88888888")
print("支付地址：\(order?.payTo ?? "")")
```

#### 安全码（MITM 防御）
```swift
// 获取安全码（用户手动比对防中间人）
let securityCode = try await client.getSecurityCode(conversationId: "conv_id")
print("安全码（告诉对方）：\(securityCode.code)")
```

#### 推送
```swift
// 注册 APNs token（从 AppDelegate 获取）
try await client.push?.registerAPNsToken("apns_token_here")
```

## 数据模型

### StoredMessage
```swift
struct StoredMessage {
    let id: String                  // 消息 ID
    let conversationId: String      // 对话 ID
    let text: String                // 消息文本
    let isMe: Bool                  // 是否是我发送
    let time: Int64                 // 时间戳（毫秒）
    let status: MessageStatus       // 发送/已读/失败等
    var msgType: String?            // 消息类型（text/image/file/voice）
    var mediaUrl: String?           // 媒体 URL
    var caption: String?            // 标题/文件名
    var seq: Int64?                 // 服务端序列号
    var fromAliasId: String?        // 发送方别名
    var replyToId: String?          // 回复的消息 ID
}
```

### SessionRecord
```swift
struct SessionRecord {
    let conversationId: String      // 对话 ID
    let theirAliasId: String        // 对方别名
    let theirEcdhPublicKey: String  // 对方 ECDH 公钥（Base64）
    let sessionKeyBase64: String    // 会话密钥（Base64，32B）
    let trustState: TrustState      // unverified / verified
    let createdAt: Int64            // 创建时间
}
```

### FriendProfile
```swift
struct FriendProfile {
    let friendshipId: Int           // 关系 ID
    let aliasId: String             // 别名
    let nickname: String            // 昵称
    let status: FriendshipStatus    // pending / accepted / rejected
    let conversationId: String      // 对话 ID
    let x25519PublicKey: String     // X25519 公钥
    let ed25519PublicKey: String    // Ed25519 公钥
    let createdAt: String           // ISO 8601 时间
}
```

## 密钥体系

### BIP-39 助记词 → 双重密钥对

```
12 词英文助记词（128bit 熵）
    ↓
BIP-39 Seed (PBKDF2-HMAC-SHA512, 2048 iter)
    ↓
    ├─ m/44'/0'/0'/0/0 → Ed25519 (签名身份)
    └─ m/44'/1'/0'/0/0 → X25519 (ECDH 加密)
```

### 会话建立流程

```
我的私钥 + 对方公钥
    ↓
ECDH 共享密钥 (32B)
    ↓
HKDF-SHA256(shared_secret, salt=SHA256(conv_id))
    ↓
会话密钥 (32B, AES-256-GCM)
```

### 消息加密

```
明文
  ↓
随机 IV (12B)
  ↓
AES-256-GCM 加密
  ↓
Base64(IV || Ciphertext || Tag)
```

## 错误处理

```swift
do {
    try await client.auth?.registerAccount(mnemonic: mnemonic, nickname: "test")
} catch SDKError.invalidMnemonic(let msg) {
    print("助记词错误：\(msg)")
} catch SDKError.authenticationFailed(let msg) {
    print("认证失败：\(msg)")
} catch SDKError.networkError(let msg) {
    print("网络错误：\(msg)")
} catch {
    print("其他错误：\(error)")
}
```

## WebSocket 事件

SDK 自动处理以下 WS 帧：

- `type: "message"` — 新消息
- `type: "typing"` — 对方正在输入
- `type: "delivered"` — 已递送回执
- `type: "read"` — 已读回执
- `type: "retract"` — 消息撤回
- `type: "goaway"` — 被踢下线

## 与 Android/TS SDK 兼容性

✅ **完全对齐**：
- 密钥派生路径完全一致
- AES-GCM 加密格式相同
- WS 帧格式兼容
- 会话密钥推导算法一致

## 跨设备特性

1. **同一助记词恢复**：在任何平台（iOS/Android/Web）输入同一助记词，恢复完全相同的身份和公钥
2. **多设备消息同步**：所有消息存储在服务端（密文），多设备自动同步
3. **一次性认证**：注册后可在不同设备登录，无需重复认证

## 安全最佳实践

1. **助记词备份**：
   - 生成后立即备份到安全位置
   - 不要截图、不要备份到云端
   - 一旦泄露，账号可能被恢复到他人设备

2. **安全码验证**：
   - 首次通话时，双方手动比对 60 位安全码
   - 防止中间人劫持（MITM）攻击

3. **Token 管理**：
   - JWT 自动存储在 HttpClient 中
   - Keychain 建议由应用层自行加密存储
   - 登出时自动清除

## 限制和注意

- ⚠️ **不支持群聊**：当前仅支持一对一对话
- ⚠️ **消息存储**：本地只存储历史摘要，完整消息加密存储在服务端
- ⚠️ **媒体上传**：示例实现简化，完整版需自行实现分片上传和压缩
- ⚠️ **iOS 16+ 专属**：使用 Swift 5.9 async/await，不支持回调风格

## 文件结构

```
sdk-ios/
├── Package.swift                    # Swift Package 定义
├── README.md                        # 本文档
└── Sources/SecureChatSDK/
    ├── index.swift                  # 公开导出
    ├── SecureChatClient.swift       # 主门面
    ├── models/
    │   ├── Models.swift             # 数据结构
    │   └── NetworkState.swift       # 网络状态
    ├── auth/
    │   └── AuthManager.swift        # 认证
    ├── keys/
    │   └── KeyDerivation.swift      # 密钥派生 + BIP39
    ├── crypto/
    │   └── CryptoModule.swift       # AES-GCM + PoW
    ├── messaging/
    │   ├── MessageManager.swift     # 消息收发
    │   └── WSTransport.swift        # WebSocket
    ├── contacts/
    │   └── ContactsManager.swift    # 好友管理
    ├── channels/
    │   └── ChannelsManager.swift    # 频道管理
    ├── media/
    │   └── MediaManager.swift       # 媒体上传/下载
    ├── push/
    │   └── PushManager.swift        # APNs 推送
    ├── security/
    │   └── SecurityModule.swift     # 安全码
    ├── vanity/
    │   └── VanityManager.swift      # 靓号管理
    ├── http/
    │   └── HttpClient.swift         # HTTP 客户端
    └── db/
        └── Database.swift           # 文件系统存储
```

## 开发指南

### 添加新功能

1. 在对应的 `*Manager.swift` 中添加方法
2. 在 `HttpClient.swift` 中定义请求/响应体
3. 在 `SecureChatClient.swift` 中公开接口
4. 在 `index.swift` 中导出 API

### 单元测试

```swift
import XCTest
@testable import SecureChatSDK

class SDKTests: XCTestCase {
    func testMnemonicGeneration() {
        let mnemonic = KeyDerivation.newMnemonic()
        XCTAssertTrue(KeyDerivation.validateMnemonic(mnemonic))
    }
}
```

## 许可证

SecureChat 加密通讯协议
专有实现，仅供内部使用

## 支持

- 文档：见 `docs/architecture/` 目录
- 协议规范：`docs/architecture/Vibecoding_Protocol.md`
- Prompt：`docs/architecture/Vibecoding_Web_React.md`（iOS 适配）
