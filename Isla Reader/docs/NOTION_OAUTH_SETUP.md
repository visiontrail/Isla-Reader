# Notion OAuth 集成配置指南

## 概览

本文档说明如何在 LanRead iOS App 中配置和使用 Notion OAuth 授权流程。

## 架构说明

### OAuth 流程分为两个阶段：

1. **前端（iOS App）- 已实现**
   - 使用 ASWebAuthenticationSession 打开 Notion 授权页面
   - 用户在 Notion 网页中完成授权
   - 获取 authorization code 和 state
   - 验证 state 防止 CSRF 攻击

2. **后端（推荐）- 待实现**
   - 使用 authorization code 交换 access token
   - 需要使用 client_secret（不应存储在 iOS App 中）
   - 安全存储 access token

## 配置步骤

### 1. 获取 Notion OAuth 凭证

1. 访问 [Notion Integrations](https://www.notion.so/my-integrations)
2. 点击 "New integration" 创建新的集成
3. 填写以下信息：
   - **Name**: LanRead（或你的应用名称）
   - **Associated workspace**: 选择你的工作区
   - **Type**: Public integration
4. 在 OAuth 设置中配置：
   - **Redirect URIs**: 添加 `lanread://notion-oauth-callback`
5. 提交后获取：
   - **Client ID**: 公开的客户端 ID（可以存储在 iOS App 中）
   - **Client Secret**: 密钥（仅用于后端，不要存储在 iOS App 中）

### 2. 配置 iOS App

1. **更新 Client ID**

   打开 `NotionAuthService.swift`，找到第 34 行：

   ```swift
   private let clientID = "YOUR_NOTION_CLIENT_ID"
   ```

   将 `YOUR_NOTION_CLIENT_ID` 替换为你在 Notion 中获取的 Client ID。

2. **验证 URL Scheme 配置**

   确认 `Info.plist` 中已包含以下配置（已自动添加）：

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

3. **（可选）自定义 URL Scheme**

   如果你想使用不同的 URL Scheme，需要同时修改：

   - `NotionAuthService.swift` 中的 `redirectScheme` 常量
   - `Info.plist` 中的 `CFBundleURLSchemes`
   - Notion Integration 设置中的 Redirect URI

## 使用说明

### 用户流程

1. 打开 App，进入 **设置 (Settings)**
2. 在 **数据与同步** 区域，点击 **连接 Notion**
3. 点击 **开始授权** 按钮
4. 系统会打开 Notion 授权页面（使用安全的 ASWebAuthenticationSession）
5. 在 Notion 页面登录并授权
6. 授权成功后自动返回 App
7. 显示授权成功消息和授权码（前 8 位）

### 安全特性

- ✅ **State 验证**: 每次授权生成唯一的随机 state，防止 CSRF 攻击
- ✅ **一次性 State**: State 在授权完成后立即清理，不可重复使用
- ✅ **Ephemeral Session**: 使用独立的 Web 浏览器会话，不共享 cookies
- ✅ **Client Secret 保护**: Client Secret 不存储在 iOS App 中
- ✅ **ASWebAuthenticationSession**: 使用 iOS 官方推荐的 OAuth 认证方式

## 代码结构

```
Isla Reader/
├── Utils/
│   └── NotionAuthService.swift       # OAuth 核心服务
├── Views/
│   └── SettingsView.swift            # Settings UI + NotionAuthView
├── Isla_ReaderApp.swift              # URL Scheme 处理
└── Info.plist                        # URL Types 配置
```

### 核心文件说明

#### NotionAuthService.swift
- 负责 OAuth URL 组装
- 管理 ASWebAuthenticationSession
- 处理授权回调
- State 生成和验证
- 错误处理

#### SettingsView.swift
- Settings 页面中的 Notion Sync 入口
- NotionAuthView: 授权 UI 界面
- 状态显示（已连接/未连接/授权中）

#### Isla_ReaderApp.swift
- 处理自定义 URL Scheme 回调
- onOpenURL modifier

## 下一步：实现 Token 交换

**重要**：Authorization code 需要在你的后端服务器上交换为 access token。

### 推荐架构

```
iOS App                 Your Backend              Notion API
--------                ------------              ----------
   |                         |                        |
   |--授权成功(code)-------->|                        |
   |                         |--code+secret---------->|
   |                         |<--access_token---------|
   |<--保存token到账户------|                        |
   |                         |                        |
   |--使用API--------------->|                        |
   |                         |--token+request-------->|
   |                         |<--response-------------|
   |<--返回数据-------------|                        |
```

### 后端 API 示例（Node.js/Express）

```javascript
// POST /api/notion/exchange-code
app.post('/api/notion/exchange-code', async (req, res) => {
  const { code } = req.body;

  const response = await fetch('https://api.notion.com/v1/oauth/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Basic ${Buffer.from(
        `${CLIENT_ID}:${CLIENT_SECRET}`
      ).toString('base64')}`
    },
    body: JSON.stringify({
      grant_type: 'authorization_code',
      code: code,
      redirect_uri: 'lanread://notion-oauth-callback'
    })
  });

  const data = await response.json();
  // 保存 data.access_token 到用户账户
  res.json({ success: true });
});
```

## 本地化字符串

已添加以下本地化 key（需要在 Localizable.strings 中定义）：

- `连接 Notion`
- `连接到 Notion`
- `授权 LanRead 访问你的 Notion 工作区，以便同步你的阅读笔记和高亮。`
- `授权成功`
- `已获取授权码`
- `正在授权...`
- `开始授权`
- `重新授权`
- `Notion 同步`
- `授权失败`
- `notion.auth.privacy_notice` (隐私声明)

## 测试

### 测试步骤

1. **配置验证**
   - 确认 Client ID 已正确配置
   - 确认 Redirect URI 与 Notion Integration 设置匹配

2. **授权流程测试**
   - 点击"开始授权"
   - 验证浏览器页面打开
   - 完成 Notion 授权
   - 验证返回 App 并显示成功消息

3. **错误处理测试**
   - 测试用户取消授权
   - 测试网络错误
   - 测试 State 不匹配（安全测试）

4. **日志检查**
   ```
   📱 Received Notion OAuth callback: lanread://notion-oauth-callback?code=...&state=...
   ```

## 常见问题

### Q: 为什么不在 iOS App 中直接交换 token？
A: Client Secret 必须保密。如果存储在 iOS App 中，任何人都可以通过反编译获取，造成安全风险。

### Q: Authorization code 有效期多久？
A: Notion authorization code 通常在 10 分钟内有效，且只能使用一次。

### Q: 如何撤销授权？
A: 用户可以在 Notion Settings → My connections 中撤销授权。

### Q: 支持多账户吗？
A: 当前实现支持单个账户。如需多账户支持，需要扩展存储逻辑。

## 参考资料

- [Notion OAuth Documentation](https://developers.notion.com/docs/authorization)
- [ASWebAuthenticationSession - Apple](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [OAuth 2.0 RFC](https://tools.ietf.org/html/rfc6749)

## 维护者

如有问题，请联系开发团队或提交 Issue。

---

最后更新：2026-01-25
