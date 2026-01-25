//
//  NotionAuthService.swift
//  LanRead
//
//  Created by Claude on 2026/1/25.
//

import Foundation
import AuthenticationServices
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
    private let clientID = "YOUR_NOTION_CLIENT_ID" // TODO: 替换为你的 Notion Client ID

    /// OAuth 回调 URL Scheme
    private let redirectScheme = "lanread"
    private let redirectPath = "notion-oauth-callback"

    /// 完整的 redirect_uri
    private var redirectURI: String {
        "\(redirectScheme)://\(redirectPath)"
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
            error = .invalidConfiguration
            return
        }

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
        guard !clientID.isEmpty, clientID != "YOUR_NOTION_CLIENT_ID" else {
            return nil
        }

        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
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
                self.error = .userCancelled
            } else {
                self.error = .authSessionFailed(error)
            }
            return
        }

        guard let callbackURL = callbackURL else {
            self.error = .invalidCallback
            return
        }

        // 解析回调 URL
        parseCallback(url: callbackURL)
    }

    /// 解析回调 URL，提取 code 和 state
    /// - Parameter url: 回调 URL
    private func parseCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            error = .invalidCallback
            return
        }

        // 提取参数
        let code = queryItems.first { $0.name == "code" }?.value
        let state = queryItems.first { $0.name == "state" }?.value
        let errorParam = queryItems.first { $0.name == "error" }?.value

        // 检查是否有错误参数
        if let errorParam = errorParam {
            error = .notionAPIError(errorParam)
            return
        }

        // 验证 state（CSRF 防护）
        guard let state = state, state == pendingState else {
            error = .stateMismatch
            return
        }

        // 验证 code
        guard let code = code, !code.isEmpty else {
            error = .missingAuthorizationCode
            return
        }

        // 成功！保存 authorization code
        authorizationCode = code

        // 清理 pending state（一次性使用）
        pendingState = nil

        // 这里可以触发后续流程，例如通知 UI 或调用后端交换 token
        // 注意：code → token 的交换应该在你的后端完成，不要在 iOS App 中使用 client_secret
    }

    // MARK: - State Generation

    /// 生成随机 state 字符串（用于 CSRF 防护）
    /// - Returns: 随机 state 字符串
    private func generateState() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).map { _ in letters.randomElement()! })
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
        // 获取当前活跃的窗口
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            // Fallback: 返回第一个窗口
            return UIApplication.shared.windows.first ?? ASPresentationAnchor()
        }
        return window
    }
}
