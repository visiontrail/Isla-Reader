//
//  NotionSessionManager.swift
//  LanRead
//

import CryptoKit
import Foundation
import Security
import SwiftUI

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(workspaceName: String)
    case error(String)
}

struct NotionOAuthExchangeResponse: Decodable {
    let accessToken: String
    let workspaceId: String?
    let workspaceName: String?
    let workspaceIcon: String?
    let botId: String?
}

struct StoredNotionSession: Codable, Equatable {
    let accessToken: String
    let botId: String
    let workspaceId: String
    let workspaceName: String
    let workspaceIcon: String?
}

protocol NotionSessionSecureStore {
    func save(_ session: StoredNotionSession) throws
    func load() throws -> StoredNotionSession?
    func delete() throws
}

protocol NotionSessionExchangeProviding {
    func exchangeAuthorizationCode(_ code: String, redirectURI: String) async throws -> NotionOAuthExchangeResponse
}

protocol NotionDatabaseMappingStoring {
    @discardableResult
    func clearAllMappings() -> Int
}

enum NotionSessionError: LocalizedError {
    case invalidAuthorizationCode
    case invalidURL
    case encodingFailed
    case invalidResponse
    case missingRequiredField(String)
    case server(message: String)
    case transport(String)
    case configuration(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationCode:
            return NSLocalizedString("notion.session.error.invalid_code", comment: "")
        case .invalidURL:
            return NSLocalizedString("notion.session.error.invalid_url", comment: "")
        case .encodingFailed:
            return NSLocalizedString("notion.session.error.encoding", comment: "")
        case .invalidResponse:
            return NSLocalizedString("notion.session.error.invalid_response", comment: "")
        case .missingRequiredField(let field):
            return String(
                format: NSLocalizedString("notion.session.error.missing_field", comment: ""),
                field
            )
        case .server(let message):
            return String(
                format: NSLocalizedString("notion.session.error.server", comment: ""),
                message
            )
        case .transport(let reason):
            return String(
                format: NSLocalizedString("notion.session.error.transport", comment: ""),
                reason
            )
        case .configuration(let reason):
            return String(
                format: NSLocalizedString("notion.session.error.configuration", comment: ""),
                reason
            )
        case .keychain(let status):
            let reason = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return String(
                format: NSLocalizedString("notion.session.error.keychain", comment: ""),
                reason
            )
        }
    }
}

@MainActor
final class NotionSessionManager: ObservableObject {
    static let shared = NotionSessionManager()

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var workspaceIcon: String?

    private let secureStore: NotionSessionSecureStore
    private let exchangeService: NotionSessionExchangeProviding
    private let mappingStore: NotionDatabaseMappingStoring

    private var currentSession: StoredNotionSession?

    init(
        secureStore: NotionSessionSecureStore = NotionSessionKeychainStore(),
        exchangeService: NotionSessionExchangeProviding = NotionOAuthExchangeService(),
        mappingStore: NotionDatabaseMappingStoring = NotionDatabaseMappingStore.shared
    ) {
        self.secureStore = secureStore
        self.exchangeService = exchangeService
        self.mappingStore = mappingStore
        restoreConnectionState()
    }

    var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    func accessToken() -> String? {
        currentSession?.accessToken
    }

    func connect(with response: NotionOAuthExchangeResponse) {
        do {
            try persistSession(from: response)
        } catch {
            handleSessionError(error)
        }
    }

    func finalizeOAuth(authorizationCode: String) async {
        let trimmedCode = authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            let message = NotionSessionError.invalidAuthorizationCode.localizedDescription
            connectionState = .error(message)
            return
        }

        connectionState = .connecting

        do {
            let response = try await exchangeService.exchangeAuthorizationCode(
                trimmedCode,
                redirectURI: NotionAuthService.callbackRedirectURI
            )
            try persistSession(from: response)
        } catch {
            handleSessionError(error)
        }
    }

    func disconnect() {
        do {
            try secureStore.delete()
            let removedMappings = mappingStore.clearAllMappings()

            currentSession = nil
            workspaceIcon = nil
            connectionState = .disconnected

            DebugLogger.info("Notion disconnected; cleared \(removedMappings) stored database mappings")
        } catch {
            handleSessionError(error)
        }
    }

    func refreshFromStorage() {
        restoreConnectionState()
    }

    private func persistSession(from response: NotionOAuthExchangeResponse) throws {
        let session = try buildSession(from: response)

        if let existingWorkspaceId = currentSession?.workspaceId,
           existingWorkspaceId != session.workspaceId {
            let removedMappings = mappingStore.clearAllMappings()
            DebugLogger.info("Notion workspace changed; cleared \(removedMappings) stored database mappings")
        }

        try secureStore.save(session)
        currentSession = session
        workspaceIcon = session.workspaceIcon
        connectionState = .connected(workspaceName: session.workspaceName)

        DebugLogger.success("Notion connected to workspace \(session.workspaceName)")
    }

    private func restoreConnectionState() {
        do {
            guard let session = try secureStore.load() else {
                currentSession = nil
                workspaceIcon = nil
                connectionState = .disconnected
                return
            }

            currentSession = session
            workspaceIcon = session.workspaceIcon
            connectionState = .connected(workspaceName: session.workspaceName)
            DebugLogger.info("Notion session restored for workspace \(session.workspaceName)")
        } catch {
            handleSessionError(error)
        }
    }

    private func buildSession(from response: NotionOAuthExchangeResponse) throws -> StoredNotionSession {
        let accessToken = response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw NotionSessionError.missingRequiredField("access_token")
        }

        let botId = (response.botId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !botId.isEmpty else {
            throw NotionSessionError.missingRequiredField("bot_id")
        }

        let workspaceId = (response.workspaceId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspaceId.isEmpty else {
            throw NotionSessionError.missingRequiredField("workspace_id")
        }

        let workspaceNameValue = (response.workspaceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceName = workspaceNameValue.isEmpty
            ? NSLocalizedString("notion.connection.workspace.unknown", comment: "")
            : workspaceNameValue

        let workspaceIconValue = (response.workspaceIcon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceIcon = workspaceIconValue.isEmpty ? nil : workspaceIconValue

        return StoredNotionSession(
            accessToken: accessToken,
            botId: botId,
            workspaceId: workspaceId,
            workspaceName: workspaceName,
            workspaceIcon: workspaceIcon
        )
    }

    private func handleSessionError(_ error: Error) {
        let message: String
        if let sessionError = error as? NotionSessionError {
            message = sessionError.localizedDescription
        } else {
            message = error.localizedDescription
        }

        connectionState = .error(message)
        DebugLogger.error("Notion session operation failed: \(message)", error: error)
    }
}

final class NotionOAuthExchangeService: NotionSessionExchangeProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func exchangeAuthorizationCode(_ code: String, redirectURI: String) async throws -> NotionOAuthExchangeResponse {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            throw NotionSessionError.invalidAuthorizationCode
        }

        let config: SecureServerConfiguration
        do {
            config = try SecureServerConfig.current()
        } catch let error as SecureServerConfigError {
            throw NotionSessionError.configuration(error.localizedDescription)
        } catch {
            throw NotionSessionError.configuration(error.localizedDescription)
        }

        guard let url = URL(string: "/v1/oauth/notion/exchange", relativeTo: config.baseURL) else {
            throw NotionSessionError.invalidURL
        }

        let nonce = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        let signature = sign(
            clientId: config.clientId,
            clientSecret: config.clientSecret,
            nonce: nonce,
            timestamp: timestamp
        )

        let payload = NotionExchangeRequestPayload(
            clientId: config.clientId,
            nonce: nonce,
            timestamp: timestamp,
            signature: signature,
            code: trimmedCode,
            redirectUri: redirectURI
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let body: Data
        do {
            body = try encoder.encode(payload)
        } catch {
            throw NotionSessionError.encodingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NotionSessionError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionSessionError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard (200...299).contains(httpResponse.statusCode) else {
            if let serverError = try? decoder.decode(NotionExchangeErrorPayload.self, from: data) {
                throw NotionSessionError.server(message: serverError.errorDescription ?? serverError.error)
            }

            let fallbackReason = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let fallbackReason, !fallbackReason.isEmpty {
                throw NotionSessionError.server(message: fallbackReason)
            }

            throw NotionSessionError.server(
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        guard let payload = try? decoder.decode(NotionOAuthExchangeResponse.self, from: data) else {
            throw NotionSessionError.invalidResponse
        }

        return payload
    }

    private func sign(clientId: String, clientSecret: String, nonce: String, timestamp: Int) -> String {
        let message = "\(clientId).\(nonce).\(timestamp)"
        let key = SymmetricKey(data: Data(clientSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return signature.map { String(format: "%02hhx", $0) }.joined()
    }
}

final class NotionSessionKeychainStore: NotionSessionSecureStore {
    private let service: String
    private let account = "notion.oauth.session"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.islareader.app") {
        self.service = service
    }

    func save(_ session: StoredNotionSession) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw NotionSessionError.encodingFailed
        }

        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw NotionSessionError.keychain(deleteStatus)
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NotionSessionError.keychain(addStatus)
        }
    }

    func load() throws -> StoredNotionSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw NotionSessionError.keychain(status)
        }

        guard let data = item as? Data else {
            throw NotionSessionError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(StoredNotionSession.self, from: data)
        } catch {
            DebugLogger.warning("Notion session payload invalid; removing corrupted keychain entry")
            try? delete()
            return nil
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NotionSessionError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class NotionDatabaseMappingStore: NotionDatabaseMappingStoring {
    static let shared = NotionDatabaseMappingStore()

    private let defaults: UserDefaults
    private let storageKey = "notion.database_mapping.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pageId(for bookId: UUID) -> String? {
        mappings[bookId.uuidString]
    }

    func setPageId(_ pageId: String, for bookId: UUID) {
        var updated = mappings
        updated[bookId.uuidString] = pageId
        defaults.set(updated, forKey: storageKey)
    }

    func removePageId(for bookId: UUID) {
        var updated = mappings
        updated.removeValue(forKey: bookId.uuidString)
        defaults.set(updated, forKey: storageKey)
    }

    @discardableResult
    func clearAllMappings() -> Int {
        let count = mappings.count
        defaults.removeObject(forKey: storageKey)
        return count
    }

    private var mappings: [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }
}

private struct NotionExchangeRequestPayload: Encodable {
    let clientId: String
    let nonce: String
    let timestamp: Int
    let signature: String
    let code: String
    let redirectUri: String
}

private struct NotionExchangeErrorPayload: Decodable {
    let error: String
    let errorDescription: String?
}
