# Notion OAuth 集成 - 快速开始

## 已完成的工作

✅ **新增文件**
1. `NotionAuthService.swift` - Notion OAuth 核心服务
2. `NOTION_OAUTH_SETUP.md` - 详细配置指南

✅ **修改文件**
1. `SettingsView.swift` - 添加 Notion Sync UI 入口和 NotionAuthView
2. `Isla_ReaderApp.swift` - 添加 URL Scheme 处理
3. `Info.plist` - 添加自定义 URL Types
4. `zh-Hans.lproj/Localizable.strings` - 添加中文本地化字符串
5. `en.lproj/Localizable.strings` - 添加英文本地化字符串

## 立即配置（3 分钟）

### 第 1 步：获取 Notion Client ID

1. 访问 https://www.notion.so/my-integrations
2. 点击 "New integration" 或使用已有的 Public integration
3. 在 OAuth 设置中：
   - 添加 Redirect URI: `lanread://notion-oauth-callback`
   - 复制 **Client ID**

### 第 2 步：配置 Client ID

打开 `NotionAuthService.swift` (第 34 行)，替换：

```swift
private let clientID = "YOUR_NOTION_CLIENT_ID"
```

为：

```swift
private let clientID = "你的实际 Client ID"
```

### 第 3 步：编译运行

```bash
# 确保项目可以编译
xcodebuild -scheme "Isla Reader" -configuration Debug build
```

或在 Xcode 中 `Command + B` 编译。

## 测试流程

1. **启动 App**
   - 进入 设置 → 数据与同步

2. **开始授权**
   - 点击 "连接 Notion"
   - 点击 "开始授权" 按钮

3. **完成授权**
   - 在弹出的浏览器中登录 Notion
   - 选择要授权的工作区
   - 点击 "Select pages" / "选择页面"
   - 点击 "Allow access" / "允许访问"

4. **验证结果**
   - 自动返回 App
   - 看到 ✓ "授权成功" 消息
   - 显示授权码的前 8 位

## 功能说明

### 已实现功能

✅ OAuth 授权 URL 构建
✅ ASWebAuthenticationSession 集成
✅ State 生成与验证（CSRF 防护）
✅ 授权回调处理
✅ Authorization Code 提取
✅ 错误处理（取消/失败/无效配置）
✅ UI 状态管理（授权中/成功/失败）
✅ 中英文本地化

### 待实现功能（后端）

⏳ Authorization Code → Access Token 交换
⏳ Access Token 安全存储
⏳ Token 刷新机制
⏳ Notion API 调用（创建页面、同步笔记等）

## 安全特性

🔒 **State 验证** - 每次授权生成随机 state，防止 CSRF
🔒 **一次性 State** - State 使用后立即清理
🔒 **Ephemeral Session** - 独立浏览器会话，不共享 cookies
🔒 **Client Secret 保护** - Secret 不存储在 iOS 中
🔒 **ASWebAuthenticationSession** - iOS 官方推荐方式

## URL Scheme 配置

已在 `Info.plist` 中配置：

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.lanread.notion-oauth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>lanread</string>
        </array>
    </dict>
</array>
```

**回调 URL**: `lanread://notion-oauth-callback`

## 代码结构

```
NotionAuthService (ObservableObject)
├── Published Properties
│   ├── isAuthorizing: Bool
│   ├── authorizationCode: String?
│   └── error: NotionAuthError?
│
├── Public Methods
│   ├── startAuthorization()
│   └── cancelAuthorization()
│
└── Private Methods
    ├── buildAuthorizationURL(state:)
    ├── handleAuthCallback(callbackURL:error:)
    ├── parseCallback(url:)
    └── generateState()
```

## 下一步：实现 Token 交换（后端）

建议在你的后端实现以下 API：

```
POST /api/notion/exchange-code
Request: { "code": "..." }
Response: { "success": true, "user_id": "..." }
```

后端流程：
1. 接收 iOS App 发送的 authorization code
2. 使用 code + client_secret 向 Notion 换取 access_token
3. 安全存储 access_token（关联到用户账户）
4. 返回成功状态给 iOS

示例实现见 `NOTION_OAUTH_SETUP.md` 文档。

## 常见问题

### Q: 点击"开始授权"后没反应？
A: 检查 `NotionAuthService.swift` 中 `clientID` 是否已替换为实际值。

### Q: 授权后没有返回 App？
A: 确认 Notion Integration 的 Redirect URI 是否设置为 `lanread://notion-oauth-callback`。

### Q: 出现 "State 验证失败" 错误？
A: 这是安全特性。重新点击"开始授权"即可。每次授权会生成新的 state。

### Q: 如何查看详细日志？
A: 在 Xcode Console 中查找 `📱 Received Notion OAuth callback:` 日志。

## 参考文档

- **详细配置指南**: `docs/NOTION_OAUTH_SETUP.md`
- **Notion API 文档**: https://developers.notion.com/docs/authorization
- **Apple ASWebAuthenticationSession**: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession

---

🎉 恭喜！Notion OAuth 的前半段已完成。现在可以获取 authorization code 了。

下一步建议实现后端 Token 交换服务，以安全地获取和存储 access token。
