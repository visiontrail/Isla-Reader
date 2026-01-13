//
//  UsageMetricsReporter.swift
//  LanRead
//

import Foundation

enum UsageMetricsSource: String {
    case startReading = "start_reading"
    case chapterSummary = "chapter_summary"
    case inlineTranslation = "inline_translation"
    case inlineExplain = "inline_explain"
    case skimming = "skimming"
    case secureConfig = "secure_config"
    case other = "other"
}

private struct APIMetricPayload: Encodable {
    let interface: String
    let statusCode: Int
    let latencyMs: Double
    let requestBytes: Int
    let tokens: Int?
    let retryCount: Int
    let source: String
    let requestId: String?
    let errorReason: String?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case interface
        case statusCode = "status_code"
        case latencyMs = "latency_ms"
        case requestBytes = "request_bytes"
        case tokens
        case retryCount = "retry_count"
        case source
        case requestId = "request_id"
        case errorReason = "error_reason"
        case timestamp
    }
}

final class UsageMetricsReporter {
    static let shared = UsageMetricsReporter()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let queue = DispatchQueue(label: "io.lanread.metrics", qos: .utility)

    init(session: URLSession = .shared) {
        self.session = session
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let value = formatter.string(from: date)
            try container.encode(value)
        }
        self.encoder = encoder
    }

    func record(
        interface: String,
        statusCode: Int,
        latencyMs: Double,
        requestBytes: Int,
        tokens: Int? = nil,
        retryCount: Int = 0,
        source: UsageMetricsSource,
        requestId: String? = nil,
        errorReason: String? = nil
    ) {
        queue.async { [weak self] in
            self?._record(
                interface: interface,
                statusCode: statusCode,
                latencyMs: latencyMs,
                requestBytes: requestBytes,
                tokens: tokens,
                retryCount: retryCount,
                source: source.rawValue,
                requestId: requestId,
                errorReason: errorReason
            )
        }
    }

    private func _record(
        interface: String,
        statusCode: Int,
        latencyMs: Double,
        requestBytes: Int,
        tokens: Int?,
        retryCount: Int,
        source: String,
        requestId: String?,
        errorReason: String?
    ) {
        guard let config = try? SecureServerConfig.current() else {
            DebugLogger.warning("UsageMetricsReporter: 未配置安全服务器，跳过指标上报")
            return
        }
        guard let url = URL(string: "/v1/metrics", relativeTo: config.baseURL) else {
            DebugLogger.warning("UsageMetricsReporter: 无效的指标上报地址")
            return
        }

        let normalizedErrorReason: String?
        if let reason = errorReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            normalizedErrorReason = String(reason.prefix(500))
        } else {
            normalizedErrorReason = nil
        }

        let payload = APIMetricPayload(
            interface: interface,
            statusCode: statusCode,
            latencyMs: max(0, latencyMs),
            requestBytes: max(0, requestBytes),
            tokens: tokens,
            retryCount: retryCount,
            source: source,
            requestId: requestId,
            errorReason: normalizedErrorReason,
            timestamp: Date()
        )

        guard let body = try? encoder.encode(payload) else {
            DebugLogger.warning("UsageMetricsReporter: 序列化指标失败")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.metricsIngestToken ?? config.clientSecret, forHTTPHeaderField: "X-Metrics-Key")

        session.dataTask(with: request).resume()
    }
}
