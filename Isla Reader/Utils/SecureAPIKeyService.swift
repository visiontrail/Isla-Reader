//
//  SecureAPIKeyService.swift
//  LanRead
//

import CryptoKit
import Foundation

private actor SecureAIConfigCache {
    private var config: SecureAIConfiguration?

    func cached() -> SecureAIConfiguration? {
        config
    }

    func store(_ config: SecureAIConfiguration) {
        self.config = config
    }
}

struct SecureAIConfiguration {
    let apiKey: String
    let endpoint: String
    let model: String
}

enum SecureAPIKeyError: LocalizedError {
    case invalidURL
    case encodingFailed
    case invalidResponse
    case server(message: String)
    case decodingFailed
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "安全服务器地址无效"
        case .encodingFailed:
            return "无法序列化安全请求"
        case .invalidResponse:
            return "安全服务器响应无效"
        case .server(let message):
            return "安全服务器返回错误：\(message)"
        case .decodingFailed:
            return "无法解析安全服务器响应"
        case .transport(let reason):
            return "网络请求失败：\(reason)"
        }
    }
}

final class SecureAPIKeyService {
    static let shared = SecureAPIKeyService()

    private let session: URLSession
    private let cache = SecureAIConfigCache()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAIConfiguration() async throws -> SecureAIConfiguration {
        let config = try SecureServerConfig.current()
        DebugLogger.info("SecureAPIKeyService: 正在向 \(config.baseURL.absoluteString) 请求 AI 配置")

        if let cached = await cache.cached() {
            return cached
        }

        let nonce = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        let signature = try sign(clientId: config.clientId, clientSecret: config.clientSecret, nonce: nonce, timestamp: timestamp)

        let payload = KeyRequestPayload(
            clientId: config.clientId,
            nonce: nonce,
            timestamp: timestamp,
            signature: signature
        )

        guard let url = URL(string: "/v1/keys/ai", relativeTo: config.baseURL) else {
            throw SecureAPIKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = makeEncoder()

        guard let body = try? encoder.encode(payload) else {
            throw SecureAPIKeyError.encodingFailed
        }
        request.httpBody = body

        let startTime = Date()
        let requestBytes = body.count
        var statusCode = 0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SecureAPIKeyError.invalidResponse
            }
            statusCode = httpResponse.statusCode

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SecureAPIKeyError.server(message: "HTTP \(httpResponse.statusCode): \(message)")
            }

            let decoder = makeDecoder()

            guard let responsePayload = try? decoder.decode(KeyResponsePayload.self, from: data) else {
                throw SecureAPIKeyError.decodingFailed
            }

            let aiConfig = SecureAIConfiguration(
                apiKey: responsePayload.apiKey,
                endpoint: responsePayload.apiEndpoint,
                model: responsePayload.model
            )

            await cache.store(aiConfig)
            DebugLogger.success("SecureAPIKeyService: 成功获取 AI 配置")
            UsageMetricsReporter.shared.record(
                interface: "/v1/keys/ai",
                statusCode: statusCode,
                latencyMs: Date().timeIntervalSince(startTime) * 1000,
                requestBytes: requestBytes,
                tokens: nil,
                retryCount: 0,
                source: .secureConfig
            )
            return aiConfig
        } catch let error as SecureAPIKeyError {
            UsageMetricsReporter.shared.record(
                interface: "/v1/keys/ai",
                statusCode: statusCode,
                latencyMs: Date().timeIntervalSince(startTime) * 1000,
                requestBytes: requestBytes,
                tokens: nil,
                retryCount: 0,
                source: .secureConfig
            )
            throw error
        } catch {
            UsageMetricsReporter.shared.record(
                interface: "/v1/keys/ai",
                statusCode: statusCode,
                latencyMs: Date().timeIntervalSince(startTime) * 1000,
                requestBytes: requestBytes,
                tokens: nil,
                retryCount: 0,
                source: .secureConfig
            )
            throw SecureAPIKeyError.transport(error.localizedDescription)
        }
    }

    func fetchAPIKey() async throws -> String {
        try await fetchAIConfiguration().apiKey
    }

    private func sign(clientId: String, clientSecret: String, nonce: String, timestamp: Int) throws -> String {
        let message = "\(clientId).\(nonce).\(timestamp)"
        let key = SymmetricKey(data: Data(clientSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return signature.map { String(format: "%02hhx", $0) }.joined()
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: value) {
                return date
            }
            let fallback = ISO8601DateFormatter()
            if let date = fallback.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid ISO8601 date: \(value)"
                )
            )
        }

        return decoder
    }
}

private struct KeyRequestPayload: Encodable {
    let clientId: String
    let nonce: String
    let timestamp: Int
    let signature: String
}

private struct KeyResponsePayload: Decodable {
    let apiKey: String
    let apiEndpoint: String
    let model: String
    let expiresIn: Int
    let issuedAt: Date
    let nonce: String
}
