//
//  ReadingAIService.swift
//  LanRead
//
//  Created by AI Assistant on 2025/3/6.
//

import Foundation

enum ReadingAIError: LocalizedError {
    case invalidEndpoint
    case network
    case api(String)
    case parse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return NSLocalizedString("ai.error.endpoint", comment: "Invalid AI endpoint")
        case .network:
            return NSLocalizedString("ai.error.network", comment: "Network error")
        case .parse:
            return NSLocalizedString("ai.error.parse", comment: "Failed to parse AI response")
        case .api(let message):
            return message
        }
    }
}

final class ReadingAIService {
    static let shared = ReadingAIService()

    private init() {}

    func translate(text: String, targetLanguage: AppLanguage) async throws -> String {
        let languageName = displayName(for: targetLanguage)
        let prompt = """
        You are a professional translator inside an eBook reader. Translate the following passage into \(languageName) with clear, natural phrasing. Keep the meaning faithful and avoid extra commentary.

        Passage:
        \(text)
        """

        return try await callAI(with: prompt, temperature: 0.35, maxTokens: 480, source: .inlineTranslation)
    }

    func explain(text: String, locale: AppLanguage) async throws -> String {
        let languageName = displayName(for: locale)
        let prompt = """
        You help readers understand tricky passages. In \(languageName), briefly explain the following excerpt in under 120 words. Start with a one-sentence summary, then list 2-3 concise bullet insights only if helpful. Keep tone clear and neutral.

        Excerpt:
        \(text)
        """

        return try await callAI(with: prompt, temperature: 0.5, maxTokens: 520, source: .inlineExplain)
    }

    // MARK: - Private

    private func callAI(with prompt: String, temperature: Double, maxTokens: Int, source: UsageMetricsSource) async throws -> String {
        let config: AIConfiguration
        do {
            config = try await AIConfig.current()
        } catch let error as AIConfigError {
            DebugLogger.error("ReadingAIService: 加载AI配置失败 - \(error.localizedDescription)")
            throw ReadingAIError.api(error.localizedDescription)
        }

        guard let url = URL(string: "\(config.endpoint)/chat/completions") else {
            DebugLogger.error("ReadingAIService: 无效的AI端点")
            throw ReadingAIError.invalidEndpoint
        }

        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": "You are an assistant embedded in an eBook reader. Keep answers concise and reader-friendly."],
                ["role": "user", "content": prompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            DebugLogger.error("ReadingAIService: 请求体序列化失败")
            throw ReadingAIError.api("Invalid request body")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 45.0

        let startTime = Date()
        let requestBytes = jsonData.count
        var statusCode = 0
        var tokensUsed: Int?
        var errorReason: String?
        defer {
            let latencyMs = Date().timeIntervalSince(startTime) * 1000
            UsageMetricsReporter.shared.record(
                interface: "/chat/completions",
                statusCode: statusCode,
                latencyMs: latencyMs,
                requestBytes: requestBytes,
                tokens: tokensUsed,
                retryCount: 0,
                source: source,
                errorReason: errorReason
            )
        }

        DebugLogger.info("ReadingAIService: 发送AI请求 model=\(config.model)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                DebugLogger.error("ReadingAIService: 响应类型无效")
                throw ReadingAIError.network
            }
            statusCode = httpResponse.statusCode

            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                DebugLogger.error("ReadingAIService: AI接口返回错误 \(httpResponse.statusCode) - \(message)")
                errorReason = message
                throw ReadingAIError.api(message)
            }

            guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                DebugLogger.error("ReadingAIService: 解析AI响应失败")
                throw ReadingAIError.parse
            }
            if let usage = jsonResponse["usage"] as? [String: Any] {
                tokensUsed = usage["total_tokens"] as? Int ?? usage["completion_tokens"] as? Int
            }

            DebugLogger.success("ReadingAIService: 收到AI响应")
            return content
        } catch let error as ReadingAIError {
            errorReason = error.localizedDescription
            throw error
        } catch {
            DebugLogger.error("ReadingAIService: 网络或解析异常 - \(error.localizedDescription)")
            errorReason = error.localizedDescription
            throw ReadingAIError.network
        }
    }

    private func displayName(for language: AppLanguage) -> String {
        switch language {
        case .system:
            return Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "your language"
        case .en:
            return "English"
        case .zhHans:
            return "中文"
        case .ja:
            return "日本語"
        case .ko:
            return "한국어"
        }
    }
}
