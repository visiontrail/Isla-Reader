//
//  NotionAuthService.swift
//  LanRead
//

import AuthenticationServices
import Foundation
import Security
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class NotionAuthService: NSObject, ObservableObject {
    static let shared = NotionAuthService()

    static let callbackScheme = "lanread"
    static let callbackHost = "notion"
    static let callbackPath = "/finish"
    static var callbackRedirectURI: String {
        "\(callbackScheme)://\(callbackHost)\(callbackPath)"
    }

    @Published private(set) var state: NotionAuthState = .idle
    @Published private(set) var workspaceIcon: String?

    private var pendingState: String?
    private var authSession: ASWebAuthenticationSession?
    private var currentSession: NotionOAuthStoredSession?

    private let secureStore: NotionAuthSecureStore
    private let networkSession: URLSession

    private override init() {
        self.secureStore = NotionAuthKeychainStore()
        self.networkSession = .shared
        super.init()
        restoreSession()
    }

    var isBusy: Bool {
        switch state {
        case .authenticating, .finalizing:
            return true
        default:
            return false
        }
    }

    var isConnected: Bool {
        if case .connected = state {
            return true
        }
        return false
    }

    var accessToken: String? {
        currentSession?.accessToken
    }

    func startAuthorization(presentationContext: ASWebAuthenticationPresentationContextProviding? = nil) {
        guard !isBusy else {
            state = .error(NotionAuthError.alreadyInProgress.localizedDescription)
            return
        }

        let generatedState = generateState()
        pendingState = generatedState

        guard let authURL = buildAuthorizationURL(state: generatedState) else {
            state = .error(NotionAuthError.invalidConfiguration.localizedDescription)
            pendingState = nil
            return
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: Self.callbackScheme
        ) { [weak self] callbackURL, sessionError in
            Task { @MainActor [weak self] in
                self?.handleAuthCallback(callbackURL: callbackURL, error: sessionError)
            }
        }

        if let presentationContext {
            session.presentationContextProvider = presentationContext
        } else {
            #if canImport(UIKit)
            session.presentationContextProvider = DefaultPresentationContextProvider.shared
            #endif
        }

        session.prefersEphemeralWebBrowserSession = true

        authSession = session
        state = .authenticating

        if !session.start() {
            state = .error(NotionAuthError.sessionFailedToStart.localizedDescription)
            cleanupAuthSession()
        }
    }

    func disconnect() {
        authSession?.cancel()
        cleanupAuthSession()

        do {
            try secureStore.delete()
            _ = NotionDatabaseMappingStore.shared.clearAllMappings()
        } catch {
            state = .error(NotionAuthError.keychainFailure(error.localizedDescription).localizedDescription)
            return
        }

        currentSession = nil
        workspaceIcon = nil
        state = .idle
    }

    func clearErrorIfNeeded() {
        if case .error = state {
            state = .idle
        }
    }

    private func restoreSession() {
        do {
            guard let session = try secureStore.load() else {
                state = .idle
                workspaceIcon = nil
                currentSession = nil
                return
            }

            currentSession = session
            workspaceIcon = session.workspaceIcon
            state = .connected(workspaceName: session.workspaceName)
        } catch {
            DebugLogger.error("Failed to restore Notion session", error: error)
            try? secureStore.delete()
            currentSession = nil
            workspaceIcon = nil
            state = .idle
        }
    }

    private func buildAuthorizationURL(state: String) -> URL? {
        let clientID = trimmedInfoValue(for: "NOTION_CLIENT_ID")
        let redirectURI = trimmedInfoValue(for: "NOTION_REDIRECT_URI")

        guard !clientID.isEmpty, !redirectURI.isEmpty else {
            return nil
        }

        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state)
        ]

        return components?.url
    }

    private func handleAuthCallback(callbackURL: URL?, error: Error?) {
        authSession = nil

        if let error {
            let nsError = error as NSError
            if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                state = .error(NotionAuthError.userCancelled.localizedDescription)
            } else {
                state = .error(NotionAuthError.authSessionFailed(error.localizedDescription).localizedDescription)
            }
            pendingState = nil
            return
        }

        guard let callbackURL else {
            state = .error(NotionAuthError.invalidCallback.localizedDescription)
            pendingState = nil
            return
        }

        do {
            let sessionID = try parseSessionID(from: callbackURL)
            Task { [weak self] in
                await self?.finalizeOAuth(sessionID: sessionID)
            }
        } catch {
            let authError = (error as? NotionAuthError) ?? .invalidCallback
            state = .error(authError.localizedDescription)
        }
    }

    private func parseSessionID(from url: URL) throws -> String {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              scheme == Self.callbackScheme,
              host == Self.callbackHost else {
            throw NotionAuthError.invalidCallback
        }

        let normalizedPath = url.path.hasPrefix("/") ? url.path : "/\(url.path)"
        guard normalizedPath == Self.callbackPath else {
            throw NotionAuthError.invalidCallback
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw NotionAuthError.invalidCallback
        }

        if let expectedState = pendingState {
            let returnedState = queryItems.first(where: { $0.name == "state" })?.value
            guard returnedState == expectedState else {
                throw NotionAuthError.stateMismatch
            }
        }

        if let errorCode = queryItems.first(where: { $0.name == "error" })?.value,
           !errorCode.isEmpty {
            throw NotionAuthError.finalizeFailed(errorCode)
        }

        let sessionID = queryItems.first(where: { $0.name == "session" || $0.name == "session_id" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        pendingState = nil

        guard let sessionID, !sessionID.isEmpty else {
            throw NotionAuthError.missingSessionID
        }

        return sessionID
    }

    private func finalizeOAuth(sessionID: String) async {
        state = .finalizing

        do {
            let payload = try await finalizeRequest(sessionID: sessionID)
            let session = try buildStoredSession(from: payload)

            if let existingWorkspaceId = currentSession?.workspaceId,
               let newWorkspaceId = session.workspaceId,
               existingWorkspaceId != newWorkspaceId {
                _ = NotionDatabaseMappingStore.shared.clearAllMappings()
            }

            try secureStore.save(session)

            currentSession = session
            workspaceIcon = session.workspaceIcon
            state = .connected(workspaceName: session.workspaceName)
            DebugLogger.success("Notion OAuth connected workspace=\(session.workspaceName)")
        } catch {
            let authError = (error as? NotionAuthError) ?? .networkFailure(error.localizedDescription)
            state = .error(authError.localizedDescription)
            DebugLogger.error("Notion OAuth finalize failed", error: error)
        }
    }

    private func finalizeRequest(sessionID: String) async throws -> NotionFinalizeResponse {
        let url = try finalizeEndpointURL()

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let body: Data
        do {
            body = try encoder.encode(NotionFinalizeRequest(sessionID: sessionID))
        } catch {
            throw NotionAuthError.invalidFinalizeResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkSession.data(for: request)
        } catch {
            throw NotionAuthError.networkFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionAuthError.invalidFinalizeResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? decoder.decode(NotionFinalizeErrorResponse.self, from: data) {
                let message = errorResponse.errorDescription ?? errorResponse.message ?? errorResponse.error
                throw NotionAuthError.finalizeFailed(message)
            }

            let fallback = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let fallback, !fallback.isEmpty {
                throw NotionAuthError.finalizeFailed(fallback)
            }

            throw NotionAuthError.finalizeFailed(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        guard let payload = try? decoder.decode(NotionFinalizeResponse.self, from: data) else {
            throw NotionAuthError.invalidFinalizeResponse
        }

        return payload
    }

    private func finalizeEndpointURL() throws -> URL {
        let baseURLString = trimmedInfoValue(for: "SecureServerBaseURL")
        guard !baseURLString.isEmpty, let baseURL = URL(string: baseURLString) else {
            throw NotionAuthError.invalidConfiguration
        }

        let requireTLS = parseBool(trimmedInfoValue(for: "SecureServerRequireTLS"), defaultValue: true)
        if requireTLS && baseURL.scheme?.lowercased() != "https" {
            throw NotionAuthError.invalidConfiguration
        }

        guard let url = URL(string: "/v1/oauth/finalize", relativeTo: baseURL) else {
            throw NotionAuthError.invalidConfiguration
        }

        return url
    }

    private func buildStoredSession(from payload: NotionFinalizeResponse) throws -> NotionOAuthStoredSession {
        let accessToken = payload.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw NotionAuthError.invalidFinalizeResponse
        }
        let workspaceNameRaw = (payload.workspaceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceName = workspaceNameRaw.isEmpty
            ? NSLocalizedString("notion.connection.workspace.unknown", comment: "")
            : workspaceNameRaw

        return NotionOAuthStoredSession(
            accessToken: accessToken,
            workspaceName: workspaceName,
            workspaceId: payload.workspaceId,
            workspaceIcon: payload.workspaceIcon,
            botId: payload.botId
        )
    }

    private func cleanupAuthSession() {
        authSession = nil
        pendingState = nil
    }

    private func parseBool(_ value: String, defaultValue: Bool) -> Bool {
        guard !value.isEmpty else { return defaultValue }
        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return defaultValue
        }
    }

    private func trimmedInfoValue(for key: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") || trimmed == "YOUR_NOTION_CLIENT_ID" {
            return ""
        }

        return trimmed.replacingOccurrences(of: "\\/", with: "/")
    }

    private func generateState() -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var randomBytes = [UInt8](repeating: 0, count: 32)

        if SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess {
            return String(randomBytes.map { charset[Int($0) % charset.count] })
        }

        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

enum NotionAuthState: Equatable {
    case idle
    case authenticating
    case finalizing
    case connected(workspaceName: String)
    case error(String)
}

enum NotionAuthError: LocalizedError, Equatable {
    case invalidConfiguration
    case alreadyInProgress
    case sessionFailedToStart
    case userCancelled
    case authSessionFailed(String)
    case invalidCallback
    case stateMismatch
    case missingSessionID
    case finalizeFailed(String)
    case invalidFinalizeResponse
    case networkFailure(String)
    case keychainFailure(String)

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
        case .authSessionFailed(let description):
            return String(format: NSLocalizedString("授权失败: %@", comment: ""), description)
        case .invalidCallback:
            return NSLocalizedString("无效的回调 URL", comment: "")
        case .stateMismatch:
            return NSLocalizedString("State 验证失败，可能存在 CSRF 攻击", comment: "")
        case .missingSessionID:
            return NSLocalizedString("notion.auth.error.missing_session", comment: "")
        case .finalizeFailed(let message):
            return String(format: NSLocalizedString("notion.session.error.server", comment: ""), message)
        case .invalidFinalizeResponse:
            return NSLocalizedString("notion.session.error.invalid_response", comment: "")
        case .networkFailure(let reason):
            return String(format: NSLocalizedString("notion.session.error.transport", comment: ""), reason)
        case .keychainFailure(let reason):
            return String(format: NSLocalizedString("notion.session.error.keychain", comment: ""), reason)
        }
    }
}

private struct NotionFinalizeRequest: Encodable {
    let sessionID: String
}

private struct NotionFinalizeResponse: Decodable {
    let accessToken: String
    let workspaceName: String?
    let workspaceId: String?
    let workspaceIcon: String?
    let botId: String?
}

private struct NotionFinalizeErrorResponse: Decodable {
    let error: String
    let errorDescription: String?
    let message: String?
}

private struct NotionOAuthStoredSession: Codable {
    let accessToken: String
    let workspaceName: String
    let workspaceId: String?
    let workspaceIcon: String?
    let botId: String?
}

private protocol NotionAuthSecureStore {
    func save(_ session: NotionOAuthStoredSession) throws
    func load() throws -> NotionOAuthStoredSession?
    func delete() throws
}

private final class NotionAuthKeychainStore: NotionAuthSecureStore {
    private let service: String
    private let account = "notion.oauth.session"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.islareader.app") {
        self.service = service
    }

    func save(_ session: NotionOAuthStoredSession) throws {
        let data = try JSONEncoder().encode(session)

        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw NotionAuthError.keychainFailure(osStatusMessage(deleteStatus))
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NotionAuthError.keychainFailure(osStatusMessage(addStatus))
        }
    }

    func load() throws -> NotionOAuthStoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw NotionAuthError.keychainFailure(osStatusMessage(status))
        }

        guard let data = result as? Data else {
            throw NotionAuthError.invalidFinalizeResponse
        }

        do {
            return try JSONDecoder().decode(NotionOAuthStoredSession.self, from: data)
        } catch {
            try? delete()
            return nil
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NotionAuthError.keychainFailure(osStatusMessage(status))
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func osStatusMessage(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
    }
}

#if canImport(UIKit)
private final class DefaultPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = DefaultPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        return scenes.flatMap(\.windows).first ?? ASPresentationAnchor()
    }
}
#endif
