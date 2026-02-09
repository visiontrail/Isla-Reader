# Notion OAuth 集成 - 快速开始

> 本文档已更新为 **session_id + finalize** 流程。
> 旧版 `authorization_code -> /v1/oauth/notion/exchange` 方案已弃用。

## 1. Notion 后台配置

在 Notion Integration 的 OAuth Redirect URI 中配置：

- `https://your-domain.com/notion/callback`

## 2. iOS 配置

确保 `Info.plist` 已配置 URL Scheme：

- `lanread`

并在本地配置中提供：

- `NOTION_CLIENT_ID`
- `NOTION_REDIRECT_URI=https://your-domain.com/notion/callback`
- `SecureServerBaseURL=https://your-domain.com`

## 3. 授权闭环

1. App 打开 Notion 授权页（`ASWebAuthenticationSession`）。
2. Notion 回调后端 `https://your-domain.com/notion/callback`。
3. 后端完成 token 交换后，302 到：
   - `lanread://notion/finish?session=...&state=...`
4. App 捕获 `session`，POST `/v1/oauth/finalize`：
   - `{ "session_id": "..." }`
5. App 持久化返回的 `access_token/workspace_name/...` 到 Keychain。

## 4. UI 状态机

- `Idle -> Authenticating -> Finalizing -> Connected / Error`

## 5. 详细文档

请优先参考：`Isla Reader/docs/NOTION_OAUTH_SETUP.md`
