//
//  NotionAPIClient.swift
//  LanRead
//

import Foundation
import Security

typealias NotionObject = [String: JSONValue]
typealias Object = NotionObject
typealias Block = NotionObject

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object(NotionObject)
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(NotionObject.self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: NotionObject? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }
}

enum NotionAPIError: LocalizedError, Equatable {
    case missingAccessToken
    case invalidHTTPResponse
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String?)
    case invalidPayload
    case transportFailure(String)
    case encodingFailure
    case tokenReadFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return NSLocalizedString("Notion token 不存在，请先完成授权", comment: "")
        case .invalidHTTPResponse:
            return NSLocalizedString("Notion 响应无效", comment: "")
        case .unauthorized:
            return NSLocalizedString("Notion token 已失效，请重新登录", comment: "")
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return String(format: NSLocalizedString("Notion 请求过快，请在 %.0f 秒后重试", comment: ""), retryAfter)
            }
            return NSLocalizedString("Notion 请求过快，请稍后重试", comment: "")
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Notion API Error (\(statusCode)): \(message)"
            }
            return "Notion API Error (\(statusCode))"
        case .invalidPayload:
            return NSLocalizedString("Notion 返回数据格式不正确", comment: "")
        case .transportFailure(let reason):
            return String(format: NSLocalizedString("Notion 网络错误: %@", comment: ""), reason)
        case .encodingFailure:
            return NSLocalizedString("Notion 请求编码失败", comment: "")
        case .tokenReadFailure(let reason):
            return String(format: NSLocalizedString("Notion token 读取失败: %@", comment: ""), reason)
        }
    }
}

extension Notification.Name {
    static let notionAccessTokenExpired = Notification.Name("notion.accessTokenExpired")
}

protocol NotionAccessTokenProviding {
    func accessToken() throws -> String?
}

final class NotionKeychainAccessTokenProvider: NotionAccessTokenProviding {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.islareader.app",
        account: String = "notion.oauth.session"
    ) {
        self.service = service
        self.account = account
    }

    func accessToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw NotionAPIError.tokenReadFailure(osStatusMessage(status))
        }

        guard let data = result as? Data,
              let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            return nil
        }

        let token = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
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

private struct StoredSession: Decodable {
    let accessToken: String
}

final class NotionAPIClient {
    static let notionVersion = "2022-06-28"

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: NotionAccessTokenProviding
    private let notificationCenter: NotificationCenter

    init(
        baseURL: URL = URL(string: "https://api.notion.com/v1")!,
        session: URLSession = .shared,
        tokenProvider: NotionAccessTokenProviding = NotionKeychainAccessTokenProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.notificationCenter = notificationCenter
    }

    func search(query: String, filter: Object) async throws -> NotionObject {
        let payload: NotionObject = [
            "query": .string(query),
            "filter": .object(filter)
        ]

        return try await send(path: "search", method: "POST", body: payload)
    }

    func createDatabase(parentPageId: String, schema: Object) async throws -> NotionObject {
        var payload = schema
        payload["parent"] = .object([
            "type": .string("page_id"),
            "page_id": .string(parentPageId)
        ])

        return try await send(path: "databases", method: "POST", body: payload)
    }

    func queryDatabase(databaseId: String, filter: Object) async throws -> NotionObject {
        let payload: NotionObject = [
            "filter": .object(filter)
        ]

        return try await send(path: "databases/\(databaseId)/query", method: "POST", body: payload)
    }

    func createPage(databaseId: String, properties: Object, children: [Block]) async throws -> NotionObject {
        var payload: NotionObject = [
            "parent": .object([
                "database_id": .string(databaseId)
            ]),
            "properties": .object(properties)
        ]

        if !children.isEmpty {
            payload["children"] = .array(children.map { .object($0) })
        }

        return try await send(path: "pages", method: "POST", body: payload)
    }

    func appendBlockChildren(blockId: String, children: [Block]) async throws -> NotionObject {
        let payload: NotionObject = [
            "children": .array(children.map { .object($0) })
        ]

        return try await send(path: "blocks/\(blockId)/children", method: "PATCH", body: payload)
    }

    private func send(path: String, method: String, body: NotionObject?) async throws -> NotionObject {
        let token: String
        do {
            guard let accessToken = try tokenProvider.accessToken() else {
                throw NotionAPIError.missingAccessToken
            }
            token = accessToken
        } catch let error as NotionAPIError {
            throw error
        } catch {
            throw NotionAPIError.tokenReadFailure(error.localizedDescription)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            guard let bodyData = try? JSONEncoder().encode(body) else {
                throw NotionAPIError.encodingFailure
            }
            request.httpBody = bodyData
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NotionAPIError.transportFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionAPIError.invalidHTTPResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try decodeObject(from: data)
        case 401:
            notifyUnauthorized()
            throw NotionAPIError.unauthorized
        case 429:
            let retryAfter = parseRetryAfter(httpResponse.value(forHTTPHeaderField: "Retry-After"))
            throw NotionAPIError.rateLimited(retryAfter: retryAfter)
        default:
            throw NotionAPIError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data)
            )
        }
    }

    private func decodeObject(from data: Data) throws -> NotionObject {
        guard !data.isEmpty else {
            return [:]
        }

        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let object) = decoded else {
            throw NotionAPIError.invalidPayload
        }

        return object
    }

    private func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        if let payload = try? JSONDecoder().decode(NotionObject.self, from: data) {
            return payload["message"]?.stringValue
                ?? payload["error"]?.stringValue
                ?? payload["code"]?.stringValue
        }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    private func parseRetryAfter(_ rawValue: String?) -> TimeInterval? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(trimmed) {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        guard let date = formatter.date(from: trimmed) else {
            return nil
        }

        return max(0, date.timeIntervalSinceNow)
    }

    private func notifyUnauthorized() {
        DispatchQueue.main.async { [notificationCenter] in
            notificationCenter.post(name: .notionAccessTokenExpired, object: nil)
        }
    }
}
