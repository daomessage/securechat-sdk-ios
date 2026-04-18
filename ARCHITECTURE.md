# iOS SDK 架构设计文档

## 概览

SecureChat iOS SDK 是完全零知识 E2EE 通讯协议的原生 Swift 实现，与 Android 和 TypeScript SDK 完全对齐。

### 核心特性

- ✅ **完全零知识**：服务端只转发密文，永不触碰明文
- ✅ **端到端加密**：AES-256-GCM 对称加密 + X25519 ECDH
- ✅ **跨设备恢复**：BIP-39 助记词确保多端身份一致
- ✅ **MITM 防御**：60 位安全码（SHA-256）手动验证
- ✅ **无第三方依赖**：仅用 Apple CryptoKit + URLSession

## 层次架构

```
┌─────────────────────────────────────────────────────┐
│                  SecureChatClient                    │  门面层
│  (单例/实例模式，对标 Android SDK)                   │
└─────────────────────────────────────────────────────┘
           ↓         ↓        ↓       ↓      ↓
    ┌────────────────────────────────────────────┐
    │         子模块（Manager 类）                 │  业务层
    ├────────────────────────────────────────────┤
    │ AuthManager      — 注册/恢复/认证           │
    │ ContactsManager  — 好友系统                 │
    │ ChannelsManager  — 公开频道                 │
    │ MessageManager   — 消息收发                 │
    │ MediaManager     — 媒体上传/下载             │
    │ PushManager      — APNs 推送                │
    │ VanityManager    — 靓号购买/绑定            │
    │ SecurityModule   — 安全码 MITM 防御         │
    └────────────────────────────────────────────┘
             ↓        ↓         ↓       ↓
    ┌─────────────────────────────────────────────┐
    │       核心基础设施层                          │  基础层
    ├──────────────────────────────────────────────┤
    │ WSTransport      — WebSocket + 重连 + 心跳  │
    │ HttpClient       — URLSession HTTP 封装    │
    │ KeyDerivation    — 密钥派生 + BIP39         │
    │ CryptoModule     — AES-GCM + SHA-256 + PoW  │
    │ Database         — 文件系统持久化            │
    └──────────────────────────────────────────────┘
             ↓              ↓              ↓
    ┌─────────────────────────────────────────────┐
    │          标准库 / 系统框架                    │
    ├──────────────────────────────────────────────┤
    │ Foundation       — 网络、序列化、并发        │
    │ CryptoKit        — Ed25519、X25519、SHA256  │
    │ URLSession       — HTTP、WebSocket         │
    │ FileManager      — 文件 I/O                │
    └──────────────────────────────────────────────┘
```

## 文件分布

```
sdk-ios/
├── Package.swift                  # Swift Package 定义
├── README.md                      # 用户文档
├── ARCHITECTURE.md                # 本文档（开发者文档）
└── Sources/SecureChatSDK/
    │
    ├── index.swift                # 公开 API 导出
    ├── SecureChatClient.swift     # 门面（单例、实例模式支持）
    │
    ├── models/
    │   ├── Models.swift           # 所有数据结构（StoredMessage 等）
    │   └── NetworkState.swift     # 网络状态枚举
    │
    ├── auth/
    │   └── AuthManager.swift      # 注册、恢复、Challenge-Response
    │
    ├── keys/
    │   └── KeyDerivation.swift    # BIP39 助记词 + Ed25519 + X25519 + HKDF
    │
    ├── crypto/
    │   └── CryptoModule.swift     # AES-GCM 加密/解密 + PoW
    │
    ├── messaging/
    │   ├── MessageManager.swift   # 消息发送/接收/历史查询
    │   └── WSTransport.swift      # URLSession WebSocket + 重连
    │
    ├── contacts/
    │   └── ContactsManager.swift  # 好友申请、同步、查找
    │
    ├── channels/
    │   └── ChannelsManager.swift  # 频道搜索、发帖、购买
    │
    ├── media/
    │   └── MediaManager.swift     # 媒体上传/下载（加密）
    │
    ├── push/
    │   └── PushManager.swift      # APNs Token 注册
    │
    ├── security/
    │   └── SecurityModule.swift   # 安全码生成和验证
    │
    ├── vanity/
    │   └── VanityManager.swift    # 靓号搜索、购买、绑定
    │
    ├── http/
    │   └── HttpClient.swift       # HTTP 客户端 + 请求/响应体
    │
    └── db/
        └── Database.swift         # 文件系统持久化（Actor 模式）
```

## 关键设计决策

### 1. Actor 模型 for 并发

所有网络和数据库操作使用 Swift `actor` 确保线程安全：

```swift
public actor HttpClient {
    public func get<T: Decodable>(_ path: String) async throws -> T { ... }
}

public actor Database {
    public func saveMessage(_ msg: MessageEntity) async throws { ... }
}

public actor WSTransport {
    public func connect(uuid: String, token: String) { ... }
}
```

**优势**：
- ✅ 编译时线程安全检查
- ✅ 无锁并发（Swift 运行时调度）
- ✅ 与 async/await 自然融合

### 2. 完全兼容三端公钥生成

密钥派生路径和算法与 Android/TS 完全一致：

```
m/44'/0'/0'/0/0  → Ed25519（签名）
m/44'/1'/0'/0/0  → X25519（ECDH）
```

**验证步骤**：
```swift
let mnemonic = "twelve words here ..."
let identity = try KeyDerivation.deriveIdentity(mnemonic: mnemonic)
// identity.signingKey.publicKey == Android 公钥
// identity.ecdhKey.publicKey   == Android 公钥
```

### 3. WS 消息帧格式

完全对齐服务端 protobuf，JSON 字符串格式：

```json
{
  "type": "message",
  "id": "msg_uuid",
  "from": "u12345678",
  "to": "u87654321",
  "conv_id": "derived_from_min_max",
  "text": "base64(AES-GCM(plaintext))",
  "time": 1700000000000,
  "seq": 42,
  "reply_to_id": "msg_uuid?"
}
```

### 4. 会话管理

**3 层存储**：

| 层 | 存储 | 数据 | TTL |
|----|-----|-----|-----|
| 内存 | Swift 变量 | 当前用户、在线状态 | 会话生命周期 |
| 文件系统 | `~/Documents/securechat/` | 身份、会话、消息 | 永久 |
| 服务端 | MySQL + Redis | 消息密文、好友关系 | 24h（消息）|

**数据库实体**：
```swift
// 身份（0 或 1 条）
struct StoredIdentity {
    uuid, aliasId, nickname, mnemonic,
    signingPublicKey, ecdhPublicKey
}

// 会话（N 条）
struct SessionEntity {
    conversationId, theirAliasId, sessionKeyBase64,
    trustState, createdAt
}

// 消息（N 条）
struct MessageEntity {
    id, conversationId, text, isMe, time, status,
    msgType?, mediaUrl?, seq?, fromAliasId?
}

// 信任（N 条）
struct TrustEntity {
    contactId, status, verifiedAt?, fingerprintSnapshot?
}
```

### 5. 错误处理

统一 `SDKError` enum：

```swift
public enum SDKError: LocalizedError {
    case networkError(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case authenticationFailed(String)
    case invalidMnemonic(String)
    case connectionError(String)
    case databaseError(String)
    case validationError(String)
    case sessionNotFound(String)
    case generalError(String)
}
```

使用方：
```swift
do {
    try await client.auth?.registerAccount(...)
} catch SDKError.authenticationFailed(let msg) {
    // 处理认证错误
} catch {
    // 处理其他错误
}
```

## 密钥体系详解

### BIP-39 助记词 → 身份恢复

```
生成 16B 随机数 → BIP-39 词表 → 12 词英文助记词（用户备份）
                      ↓
                   PBKDF2-SHA512
                   (2048 iter, salt="mnemonic")
                      ↓
                   64B Seed
                      ↓
            ┌────────────┬────────────┐
            ↓                        ↓
    SLIP-0010 硬化派生          SLIP-0010 硬化派生
    m/44'/0'/0'/0/0            m/44'/1'/0'/0/0
            ↓                        ↓
    Ed25519 私钥 (32B)        X25519 私钥 (32B)
            ↓                        ↓
    Ed25519 公钥 (32B)        X25519 公钥 (32B)
    ↓                          ↓
    Challenge-Response        ECDH 消息加密
    认证                       会话建立
```

**关键点**：
- HMAC key = `"ed25519 seed"`（与 TS/Android 完全相同）
- 硬化索引 = `index | 0x80000000`
- 无 passphrase（salt = `"mnemonic"`）

### ECDH 会话密钥推导

```
我的 X25519 私钥 + 对方 X25519 公钥
            ↓
    Curve25519 ECDH
            ↓
    共享密钥 (32B)
            ↓
    HKDF-SHA256
    (salt = SHA256(conversationId), 
     info = "securechat-session-v1",
     length = 32)
            ↓
    会话密钥 (32B, AES-256 GCM 专用)
```

### AES-256-GCM 消息加密

```
明文 (UTF-8)
  ↓
生成随机 12B IV
  ↓
AES.GCM.seal(plaintext, key=sessionKey, nonce=IV)
  ↓
{ciphertext, tag}
  ↓
IV || ciphertext || tag (总长 = 12 + len(ct) + 16)
  ↓
Base64 编码
  ↓
传输
```

**解密**：
```
Base64 解码
  ↓
拆分 IV (first 12B) + ciphertext (middle) + tag (last 16B)
  ↓
AES.GCM.open(ciphertext, tag, nonce=IV, key=sessionKey)
  ↓
明文
```

## 事件流

### 新用户注册流程

```
┌────────────────────────────────────────────────────┐
│ 用户操作                                            │
├────────────────────────────────────────────────────┤
│ 1. generateMnemonic()                              │
│    └─ 返回 12 词（用户备份）                       │
│                                                     │
│ 2. client.auth?.registerAccount(                   │
│      mnemonic: "...",                              │
│      nickname: "..."                               │
│    )                                                │
└────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────┐
│ AuthManager                                         │
├────────────────────────────────────────────────────┤
│ 1. 验证助记词（BIP-39 校验）                       │
│ 2. KeyDerivation.deriveIdentity()                  │
│    └─ 派生 Ed25519 + X25519                        │
│ 3. GET /api/v1/pow/challenge                       │
│    └─ 获取 PoW 难度                                │
│ 4. CryptoModule.computePow()                       │
│    └─ 异步计算 SHA256(challenge+nonce)             │
│ 5. POST /api/v1/register                           │
│    └─ 上传 {ed_pub, x_pub, nickname, pow_nonce}   │
│ 6. performAuthChallenge()                          │
│    a. GET /api/v1/auth/challenge → {challenge}    │
│    b. Ed25519.sign(challenge) → signature          │
│    c. POST /api/v1/auth/verify → {token}          │
│ 7. Database.saveIdentity()                         │
│    └─ 存储到文件系统                               │
│ 8. return aliasId                                  │
└────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────┐
│ 应用层                                              │
├────────────────────────────────────────────────────┤
│ await client.connect()                             │
│ └─ WSTransport.connect(uuid, token)                │
│    └─ 建立 /ws?uuid=...&token=...                  │
│       └─ 发出 onOpen 事件                          │
└────────────────────────────────────────────────────┘
```

### 消息发送流程

```
┌──────────────────────────────┐
│ client.sendMessage(...)      │
└──────────────────────────────┘
         ↓
┌──────────────────────────────┐
│ MessageManager               │
├──────────────────────────────┤
│ 1. Database.loadSession()    │
│    └─ 获取会话密钥            │
│ 2. CryptoModule.encrypt()    │
│    └─ 加密文本                │
│ 3. 构建 WS 帧                 │
│    {type: "message",         │
│     id, from, to, conv_id,   │
│     text: encrypted,         │
│     time, reply_to_id?}      │
│ 4. transport.send(jsonStr)   │
│ 5. Database.saveMessage()    │
│    └─ status = "sending"      │
│ 6. return messageId          │
└──────────────────────────────┘
         ↓
┌──────────────────────────────┐
│ WSTransport                  │
├──────────────────────────────┤
│ URLSessionWebSocket.send()   │
│ └─ 通过 wss://relay... 发送   │
└──────────────────────────────┘
         ↓
┌──────────────────────────────┐
│ 服务端 (relay-server)         │
├──────────────────────────────┤
│ 1. 验证签名（可选）           │
│ 2. NATS 路由转发              │
│ 3. Redis 持久化               │
│ 4. 广播给接收端               │
└──────────────────────────────┘
         ↓
┌──────────────────────────────┐
│ 接收端                        │
├──────────────────────────────┤
│ WS frame → MessageManager    │
│ 1. handleIncomingMessage()   │
│ 2. CryptoModule.decrypt()    │
│ 3. Database.saveMessage()    │
│ 4. 触发 onMessage 回调        │
│ 5. 发送 delivered 回执        │
└──────────────────────────────┘
```

## 与 Android/TS SDK 对齐清单

| 功能 | iOS | Android | TS | 状态 |
|------|-----|---------|----|----|
| BIP39 助记词 | ✅ | ✅ | ✅ | 对齐 |
| Ed25519 签名 | ✅ | ✅ | ✅ | 对齐 |
| X25519 ECDH | ✅ | ✅ | ✅ | 对齐 |
| SLIP-0010 派生 | ✅ | ✅ | ✅ | 对齐 |
| HKDF-SHA256 | ✅ | ✅ | ✅ | 对齐 |
| AES-256-GCM | ✅ | ✅ | ✅ | 对齐 |
| PoW（SHA256） | ✅ | ✅ | ✅ | 对齐 |
| WebSocket | ✅ | ✅ | ✅ | 对齐 |
| 会话管理 | ✅ | ✅ | ✅ | 对齐 |
| 好友系统 | ✅ | ✅ | ✅ | 对齐 |
| 频道系统 | ✅ | ✅ | ✅ | 对齐 |
| 媒体上传 | ✅ | ✅ | ✅ | 对齐 |
| 靓号购买 | ✅ | ✅ | ✅ | 对齐 |

## 性能考量

### 内存占用

- 单个消息实体：~200 字节
- 单个会话实体：~500 字节
- 200 条消息历史：~40 KB
- **总内存占用**：< 1 MB（含 SDK）

### 网络延迟

| 操作 | 延迟 | 备注 |
|------|------|------|
| 注册 | ~2s | PoW 计算 + 服务端验证 |
| 恢复 | ~500ms | 本地读取 + 认证 |
| 发送消息 | ~100ms | 加密 + WS 发送 |
| 接收消息 | 实时 | WS 推送 |
| 媒体上传 | 文件大小相关 | 分片上传 |

### 电池影响

- **心跳频率**：30 秒一次 `ping` 帧
- **重连策略**：指数退避，最大 10 次
- **后台模式**：依赖 iOS APNs，本地 WS 不可用

## 扩展点

### 添加新的 Manager

1. 创建 `new_feature/NewFeatureManager.swift`
2. 实现 `public actor NewFeatureManager { ... }`
3. 在 `SecureChatClient.init()` 中初始化
4. 在 `index.swift` 中导出公开 API

### 自定义加密算法

当前使用 Apple CryptoKit（推荐），如需自定义：

```swift
// CryptoModule.swift 中替换
public static func encrypt(...) throws -> String {
    // 使用自己的加密实现
}
```

### 添加自定义存储后端

默认使用文件系统，如需数据库：

```swift
// Database.swift 改为使用 CoreData
let container = NSPersistentContainer(name: "SecureChat")
```

## 测试建议

```swift
import XCTest
@testable import SecureChatSDK

class KeyDerivationTests: XCTestCase {
    func testMnemonicGeneration() {
        let m1 = KeyDerivation.newMnemonic()
        let m2 = KeyDerivation.newMnemonic()
        XCTAssertNotEqual(m1, m2)
        XCTAssertTrue(KeyDerivation.validateMnemonic(m1))
    }

    func testCrossPlatformKeys() {
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let identity = try! KeyDerivation.deriveIdentity(mnemonic: mnemonic)
        // 与 Android/TS SDK 比对公钥
        XCTAssertEqual(
            identity.signingKey.publicKey.base64EncodedString(),
            "expected_value_from_android"
        )
    }
}

class EncryptionTests: XCTestCase {
    func testEncryptDecrypt() async throws {
        let key = Data(repeating: 0, count: 32)
        let plaintext = "Hello, World!"
        let encrypted = try CryptoModule.encrypt(sessionKey: key, plaintext: plaintext)
        let decrypted = try CryptoModule.decrypt(sessionKey: key, base64Payload: encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }
}
```

## 常见问题

### Q: 如何多端登录？
A: 输入同一助记词即可在 iOS/Android/Web 恢复身份。服务端不会重复创建账号（409 Conflict），自动回到 loginExt() 流程。

### Q: 消息是否上传服务端？
A: 是的（密文）。保存在 Redis（24h TTL）供 pullSync 使用，同时也持久化在 MySQL。

### Q: 支持群聊吗？
A: 不支持（v1.0）。当前仅 1v1 端到端加密对话。

### Q: 如何处理离线消息？
A: 重连后自动触发 pullSync，服务端将 24h 内的密文消息下发。

## 参考资源

- **协议**：`docs/architecture/Vibecoding_Protocol.md`
- **Android SDK**：`sdk-android/`
- **TS SDK**：`sdk-typescript/`
- **后端**：`relay-server/`
