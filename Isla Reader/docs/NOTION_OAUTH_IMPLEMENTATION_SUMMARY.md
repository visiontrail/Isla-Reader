# Notion OAuth 实现摘要

> 当前实现已切换为 BFF finalize 方案。
> 本文档用于标记当前代码的关键入口，避免继续使用旧版 code-exchange 客户端流程。

## 客户端关键点

1. `Isla Reader/Utils/NotionAuthService.swift`
   - `ASWebAuthenticationSession` 拉起授权
   - 监听 `lanread://notion/finish`
   - 解析 `session` 和校验 `state`
   - 调用 `POST /v1/oauth/finalize`（body: `{session_id}`）
   - Keychain 持久化会话

2. `Isla Reader/Utils/NotionSessionManager.swift`
   - 对外连接生命周期管理（状态、断开、映射清理）
   - 状态机：`Disconnected / Connecting / Connected(workspaceName) / Error`
   - App 启动时恢复 Keychain 会话并同步 UI 状态

3. `Isla Reader/Views/SettingsView.swift`
   - Settings 中 Data & Sync 的 Notion 入口
   - 展示当前 Workspace 名称与 Icon

4. `Isla Reader/Info.plist`
   - URL Types: `lanread`
   - `NOTION_CLIENT_ID`
   - `NOTION_REDIRECT_URI`

## 安全边界

- iOS 端不包含 Notion `client_secret`。
- Notion token 交换仅在后端进行。
- App 仅处理一次性 `session_id` finalize。

## 配置前提

- Notion Redirect URI: `https://your-domain.com/notion/callback`
- 后端回跳：`lanread://notion/finish?session=...&state=...`

## 详细配置文档

请使用：`Isla Reader/docs/NOTION_OAUTH_SETUP.md`
