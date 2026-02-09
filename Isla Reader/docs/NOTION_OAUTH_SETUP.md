# Notion OAuth 集成配置指南（客户端 + BFF）

## 概览

LanRead 当前使用以下安全闭环：

1. iOS 端仅负责拉起 Notion 授权页并接收 `lanread://` 回调。
2. Notion `code -> token` 仅在后端完成（后端持有 `client_secret`）。
3. iOS 端通过一次性 `session_id` 调用后端 `/v1/oauth/finalize` 换取最终会话数据并写入 Keychain。

## 时序（与实现一致）

1. App 生成随机 `state`。
2. App 通过 `ASWebAuthenticationSession` 打开：
   - `https://api.notion.com/v1/oauth/authorize?client_id=...&response_type=code&owner=user&redirect_uri=https://your-domain.com/notion/callback&state=...`
3. Notion 回调到后端 `https://your-domain.com/notion/callback?code=...&state=...`。
4. 后端完成 token 交换，生成一次性 `session_id`（建议 TTL 60 秒），然后 302 到：
   - `lanread://notion/finish?session={SESSION_ID}&state={STATE}`
5. `ASWebAuthenticationSession` 捕获该 URL 并自动关闭授权页。
6. App 校验 `state`，提取 `session`。
7. App `POST /v1/oauth/finalize`，请求体：
   - `{ "session_id": "..." }`
8. 后端返回：
   - `{ "access_token": "...", "workspace_name": "...", "workspace_id": "...", "workspace_icon": "...", "bot_id": "..." }`
9. App 写入 Keychain（`kSecAttrAccessibleAfterFirstUnlock`），UI 进入 Connected。

## Notion 后台配置

1. 进入 [Notion Integrations](https://www.notion.so/my-integrations)。
2. 创建/编辑 Public integration。
3. OAuth Redirect URI 必须配置为：
   - `https://your-domain.com/notion/callback`

注意：`lanread://...` 不是 Notion 的 redirect URI，它是后端处理完后的二次跳转目标。

## iOS 配置

### 1. Info.plist

必须包含 URL Types（用于拦截 `lanread://`）：

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>lanread</string>
    </array>
  </dict>
</array>
```

### 2. 配置项（xcconfig / Info.plist）

需要配置：

- `NOTION_CLIENT_ID`：Notion OAuth Client ID（可公开）
- `NOTION_REDIRECT_URI`：`https://your-domain.com/notion/callback`
- `SecureServerBaseURL`：后端基地址（例如 `https://your-domain.com`）
- `SecureServerRequireTLS`：生产建议 `true`

`client_secret` 不应存在于 iOS 代码或 iOS 配置中。

## UI 状态机

Settings -> Data & Sync 使用状态机驱动：

- `Idle`
- `Authenticating`（正在授权）
- `Finalizing`（正在交换 Token）
- `Connected(workspace)`
- `Error(message)`

## 调试检查清单

1. 点击“连接 Notion”后，是否拉起系统授权页（`ASWebAuthenticationSession`）。
2. 授权后是否收到 `lanread://notion/finish?...`。
3. 回调 URL 中是否包含 `session` 与 `state`。
4. App 是否请求 `POST /v1/oauth/finalize`，且 body 为 `{ "session_id": "..." }`。
5. 成功后是否显示 workspace 名称并可持久化恢复连接状态。

## 常见问题

### 1) 回调后报“无效的回调 URL”

检查：
- URL scheme 是否为 `lanread`
- host 是否为 `notion`
- path 是否为 `/finish`

### 2) 回调后报“State 验证失败”

说明回调里的 `state` 与 App 发起授权时保存的不一致。优先检查后端重定向时是否透传了原始 `state`。

### 3) Finalize 失败

检查：
- `session_id` 是否一次性可用（读取后即销毁）
- `session_id` 是否过期（TTL 太短）
- `SecureServerBaseURL` 是否配置正确且可达
