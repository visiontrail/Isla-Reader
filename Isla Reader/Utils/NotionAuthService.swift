//
//  NotionAuthService.swift
//  LanRead
//
//  Created by Claude on 2026/1/25.
//

import Foundation
import AuthenticationServices
import Security
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Notion OAuth 认证服务
/// 负责处理 Notion OAuth 2.0 授权流程的前半段：生成授权 URL、启动授权、接收回调
@MainActor
final class NotionAuthService: NSObject, ObservableObject {
    static let shared = NotionAuthService()

    // MARK: - Published Properties

    @Published var isAuthorizing = false
    @Published var authorizationCode: String?
    @Published var error: NotionAuthError?

    // MARK: - Configuration

    /// Notion OAuth Client ID
    /// 注意：这是公开的 client_id，可以安全地存储在 iOS App 中
    /// client_secret 应该只在后端使用，不应出现在 iOS 代码中
    /// 优先从 Info.plist 的 `NOTION_CLIENT_ID` 读取，便于用 xcconfig 覆盖
    private var clientID: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "NOTION_CLIENT_ID") as? String
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "YOUR_NOTION_CLIENT_ID"
    }

    /// OAuth 回调 URL Scheme
    private let redirectScheme = "lanread"
    private let redirectHost = "notion-oauth-callback"

    /// 完整的 redirect_uri
    private var redirectURI: String {
        "\(redirectScheme)://\(redirectHost)"
    }

    // MARK: - State Management (CSRF Protection)

    /// 当前授权流程的 state（一次性使用）
    /// 存储在内存中，授权完成后立即清理
    private var pendingState: String?

    /// ASWebAuthenticationSession 实例
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Private Init

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// 启动 Notion OAuth 授权流程
    /// - Parameter presentationContext: 用于展示授权页面的窗口上下文
    func startAuthorization(presentationContext: ASWebAuthenticationPresentationContextProviding? = nil) {
        // 防止重复授权
        guard !isAuthorizing else {
            DebugLogger.warning("Notion OAuth already in progress; ignoring duplicate tap")
            error = .alreadyInProgress
            return
        }

        // 重置状态
        reset()

        // 生成新的 state 用于 CSRF 防护
        let state = generateState()
        pendingState = state

        // 构建授权 URL
        guard let authURL = buildAuthorizationURL(state: state) else {
            DebugLogger.error("Notion OAuth configuration invalid - missing or placeholder client ID")
            error = .invalidConfiguration
            cleanup()
            return
        }

        DebugLogger.info("Starting Notion OAuth: state=\(state.prefix(8))..., redirect=\(redirectURI)")

        // 创建并启动 ASWebAuthenticationSession
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: redirectScheme
        ) { [weak self] callbackURL, sessionError in
            Task { @MainActor [weak self] in
                self?.handleAuthCallback(callbackURL: callbackURL, error: sessionError)
            }
        }

        // 配置展示上下文
        if let context = presentationContext {
            session.presentationContextProvider = context
        } else {
            // 使用默认上下文提供者
            session.presentationContextProvider = DefaultPresentationContextProvider.shared
        }

        // 优先使用 ephemeral session（不共享 cookies）
        session.prefersEphemeralWebBrowserSession = true

        isAuthorizing = true
        authSession = session

        // 启动授权流程
        if !session.start() {
            DebugLogger.error("ASWebAuthenticationSession failed to start")
            isAuthorizing = false
            error = .sessionFailedToStart
            cleanup()
        }
    }

    /// 取消当前授权流程
    func cancelAuthorization() {
        authSession?.cancel()
        cleanup()
    }

    // MARK: - URL Building

    /// 构建 Notion OAuth 授权 URL
    /// - Parameter state: CSRF 防护 state
    /// - Returns: 授权 URL
    private func buildAuthorizationURL(state: String) -> URL? {
        let id = clientID
        guard !id.isEmpty,
              id != "YOUR_NOTION_CLIENT_ID",
              !id.contains("$(") else { // 未被替换的占位符
            return nil
        }

        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "owner", value: "user") // 可选：指定授权类型
        ]

        return components?.url
    }

    // MARK: - Callback Handling

    /// 处理授权回调
    /// - Parameters:
    ///   - callbackURL: 回调 URL
    ///   - error: 可能的错误
    private func handleAuthCallback(callbackURL: URL?, error: Error?) {
        defer {
            isAuthorizing = false
            cleanup()
        }

        // 处理取消或错误
        if let error = error {
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                DebugLogger.info("Notion OAuth cancelled by user")
                self.error = .userCancelled
            } else {
                DebugLogger.error("Notion OAuth session failed", error: error)
                self.error = .authSessionFailed(error)
            }
            return
        }

        guard let callbackURL = callbackURL else {
            DebugLogger.error("Notion OAuth callback URL missing")
            self.error = .invalidCallback
            return
        }

        // 解析回调 URL
        DebugLogger.info("Received Notion OAuth callback: \(callbackURL.absoluteString)")
        parseCallback(url: callbackURL)
    }

    /// 解析回调 URL，提取 code 和 state
    /// - Parameter url: 回调 URL
    private func parseCallback(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              scheme == redirectScheme,
              host == redirectHost else {
            DebugLogger.error("Unexpected callback URL target: \(url.absoluteString)")
            error = .invalidCallback
            return
        }

        guard let expectedState = pendingState else {
            DebugLogger.error("No pending OAuth state available for verification")
            error = .stateMismatch
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            error = .invalidCallback
            return
        }

        // 提取参数
        let code = queryItems.first { $0.name == "code" }?.value
        let state = queryItems.first { $0.name == "state" }?.value
        let errorParam = queryItems.first { $0.name == "error" }?.value

        // 验证 state（CSRF 防护）
        guard let state = state, state == expectedState else {
            DebugLogger.error("Notion OAuth state mismatch")
            error = .stateMismatch
            return
        }

        // 检查是否有错误参数
        if let errorParam = errorParam {
            DebugLogger.error("Notion OAuth error from server: \(errorParam)")
            error = .notionAPIError(errorParam)
            return
        }

        // 验证 code
        guard let code = code, !code.isEmpty else {
            DebugLogger.error("Notion OAuth missing authorization code")
            error = .missingAuthorizationCode
            return
        }

        // 成功！保存 authorization code
        authorizationCode = code

        // 清理 pending state（一次性使用）
        pendingState = nil

        // 这里可以触发后续流程，例如通知 UI 或调用后端交换 token
        // 注意：code → token 的交换应该在你的后端完成，不要在 iOS App 中使用 client_secret
        DebugLogger.success("Notion OAuth succeeded; code prefix=\(code.prefix(8))")
    }

    // MARK: - State Generation

    /// 生成随机 state 字符串（用于 CSRF 防护）
    /// - Returns: 随机 state 字符串
    private func generateState() -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var randomBytes = [UInt8](repeating: 0, count: 32)

        if SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess {
            return String(randomBytes.map { charset[Int($0) % charset.count] })
        }

        DebugLogger.warning("SecRandomCopyBytes failed, falling back to UUID-based state")
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    // MARK: - Cleanup

    /// 清理授权会话和临时状态
    private func cleanup() {
        authSession = nil
        pendingState = nil
    }

    /// 重置所有状态
    private func reset() {
        authorizationCode = nil
        error = nil
        cleanup()
    }
}

// MARK: - NotionAuthError

enum NotionAuthError: LocalizedError, Equatable {
    case invalidConfiguration
    case alreadyInProgress
    case sessionFailedToStart
    case userCancelled
    case authSessionFailed(Error)
    case invalidCallback
    case stateMismatch
    case missingAuthorizationCode
    case notionAPIError(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return NSLocalizedString("Notion OAuth 配置无效，请检查 Client ID", comment: "")
        case .alreadyInProgress:
            return NSLocalizedString("授权流程已在进行中", comment: "")
        case .sessionFailedToStart:
            return NSLocalizedString("无法启动授权会话", comment: "")
        case .userCancelled:
            return NSLocalizedString("用户取消了授权", comment: "")
        case .authSessionFailed(let error):
            return String(format: NSLocalizedString("授权失败: %@", comment: ""), error.localizedDescription)
        case .invalidCallback:
            return NSLocalizedString("无效的回调 URL", comment: "")
        case .stateMismatch:
            return NSLocalizedString("State 验证失败，可能存在 CSRF 攻击", comment: "")
        case .missingAuthorizationCode:
            return NSLocalizedString("未收到授权码", comment: "")
        case .notionAPIError(let errorCode):
            return String(format: NSLocalizedString("Notion 授权错误: %@", comment: ""), errorCode)
        }
    }

    // Equatable 实现
    static func == (lhs: NotionAuthError, rhs: NotionAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidConfiguration, .invalidConfiguration),
             (.alreadyInProgress, .alreadyInProgress),
             (.sessionFailedToStart, .sessionFailedToStart),
             (.userCancelled, .userCancelled),
             (.invalidCallback, .invalidCallback),
             (.stateMismatch, .stateMismatch),
             (.missingAuthorizationCode, .missingAuthorizationCode):
            return true
        case (.authSessionFailed(let lhsError), .authSessionFailed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.notionAPIError(let lhsCode), .notionAPIError(let rhsCode)):
            return lhsCode == rhsCode
        default:
            return false
        }
    }
}

// MARK: - Default Presentation Context Provider

/// 默认的 ASWebAuthenticationSession 展示上下文提供者
private class DefaultPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = DefaultPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let keyWindow = windowScenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        return windowScenes.flatMap(\.windows).first ?? ASPresentationAnchor()
    }
}
