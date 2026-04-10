import BatchModels
import BatchSupport
import Foundation

public struct BatchAIClient {
    public typealias RequestExecutor = (URLRequest) throws -> (Data, HTTPURLResponse)

    private let fileManager: FileManager
    private let environment: [String: String]
    private let requestExecutor: RequestExecutor

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        requestExecutor: RequestExecutor? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.requestExecutor = requestExecutor ?? Self.defaultRequestExecutor
    }

    public func validateProviderConfiguration(path: String?) throws {
        _ = try loadProviderConfiguration(path: path)
    }

    public func loadProviderConfiguration(path: String?) throws -> BatchAIProviderConfiguration {
        let fileConfig = try readProviderConfigFile(path: path)

        let endpoint = firstNonEmpty(fileConfig?.endpoint, environment["LANREAD_AI_ENDPOINT"])
        let apiKey = firstNonEmpty(fileConfig?.apiKey, environment["LANREAD_AI_KEY"])
        let model = firstNonEmpty(fileConfig?.model, environment["LANREAD_AI_MODEL"])

        var missing: [String] = []
        if endpoint == nil { missing.append("endpoint/LANREAD_AI_ENDPOINT") }
        if apiKey == nil { missing.append("apiKey/LANREAD_AI_KEY") }
        if model == nil { missing.append("model/LANREAD_AI_MODEL") }
        if !missing.isEmpty {
            let joined = missing.joined(separator: ", ")
            throw BatchError.runtime(
                "AI provider configuration is incomplete. Missing \(joined). Provide values via --provider-config or LANREAD_AI_* env vars."
            )
        }

        let timeoutSeconds = parseDouble(
            fileConfig?.timeoutSeconds,
            environment["LANREAD_AI_TIMEOUT_SECONDS"],
            defaultValue: 45
        )
        let maxRetryCount = parseInt(
            fileConfig?.maxRetryCount,
            environment["LANREAD_AI_MAX_RETRIES"],
            defaultValue: 2
        )

        return BatchAIProviderConfiguration(
            endpoint: endpoint!,
            apiKey: apiKey!,
            model: model!,
            timeoutSeconds: max(1, timeoutSeconds),
            maxRetryCount: max(0, maxRetryCount)
        )
    }

    public func stage1ExtractCandidates(
        request: BatchStage1Request,
        provider: BatchAIProviderConfiguration
    ) throws -> BatchStage1ExtractionResult {
        let prompt = makeStage1Prompt(request: request)
        let requestURL = try makeChatCompletionsURL(endpoint: provider.endpoint)
        let requestBody = try makeStage1RequestBody(prompt: prompt, provider: provider)

        var lastError: Error?
        let totalAttempts = provider.maxRetryCount + 1
        for attempt in 1...totalAttempts {
            do {
                var urlRequest = URLRequest(url: requestURL)
                urlRequest.httpMethod = "POST"
                urlRequest.httpBody = requestBody
                urlRequest.timeoutInterval = provider.timeoutSeconds
                urlRequest.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let (data, response) = try requestExecutor(urlRequest)
                guard response.statusCode == 200 else {
                    let serverMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let reason = serverMessage?.isEmpty == false ? serverMessage! : "status=\(response.statusCode)"
                    throw BatchError.runtime("Stage 1 API error for \(request.excerpt.id): \(reason)")
                }

                let responseText = try parseAssistantText(from: data)
                let candidates = try parseStage1Candidates(from: responseText)
                return BatchStage1ExtractionResult(
                    promptText: prompt,
                    responseText: responseText,
                    candidates: candidates,
                    attemptCount: attempt
                )
            } catch {
                lastError = error
                if attempt >= totalAttempts {
                    break
                }
            }
        }

        throw BatchError.runtime(
            "Stage 1 extraction failed for \(request.excerpt.id) after \(totalAttempts) attempts: \(lastError?.localizedDescription ?? "unknown error")"
        )
    }

    public func stage2SelectCandidates(
        request: BatchStage2Request,
        provider: BatchAIProviderConfiguration
    ) throws -> BatchStage2SelectionResult {
        let prompt = makeStage2Prompt(request: request)
        let requestURL = try makeChatCompletionsURL(endpoint: provider.endpoint)
        let requestBody = try makeStage2RequestBody(prompt: prompt, provider: provider)

        var lastError: Error?
        let totalAttempts = provider.maxRetryCount + 1
        for attempt in 1...totalAttempts {
            do {
                var urlRequest = URLRequest(url: requestURL)
                urlRequest.httpMethod = "POST"
                urlRequest.httpBody = requestBody
                urlRequest.timeoutInterval = provider.timeoutSeconds
                urlRequest.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let (data, response) = try requestExecutor(urlRequest)
                guard response.statusCode == 200 else {
                    let serverMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let reason = serverMessage?.isEmpty == false ? serverMessage! : "status=\(response.statusCode)"
                    throw BatchError.runtime("Stage 2 API error: \(reason)")
                }

                let responseText = try parseAssistantText(from: data)
                let selections = try parseStage2Selections(from: responseText)
                return BatchStage2SelectionResult(
                    promptText: prompt,
                    responseText: responseText,
                    selections: selections,
                    attemptCount: attempt
                )
            } catch {
                lastError = error
                if attempt >= totalAttempts {
                    break
                }
            }
        }

        throw BatchError.runtime(
            "Stage 2 selection failed after \(totalAttempts) attempts: \(lastError?.localizedDescription ?? "unknown error")"
        )
    }

    private func readProviderConfigFile(path: String?) throws -> ProviderConfigFile? {
        guard let path = firstNonEmpty(path) else {
            return nil
        }

        guard fileManager.fileExists(atPath: path) else {
            throw BatchError.fileNotFound(path)
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(ProviderConfigFile.self, from: data)
        } catch let error as DecodingError {
            throw BatchError.runtime("Failed to parse provider config JSON at \(path): \(error.localizedDescription)")
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.ioFailure("Failed reading provider config at \(path): \(error.localizedDescription)")
        }
    }

    public func makeStage1Prompt(request: BatchStage1Request) -> String {
        """
        You are helping an eBook team extract shareable highlights.

        Constraints:
        1. Return 3 to 8 candidates.
        2. highlight_text MUST be copied exactly from the excerpt text.
        3. Prefer medium-to-long highlight_text passages that fill a share card well.
        4. When the excerpt allows, choose 2 to 4 connected sentences or a substantial paragraph slice, not a short slogan.
        5. Avoid very short one-line highlights unless that line is exceptionally strong and self-contained.
        6. note_text should be one short framing sentence in \(request.outputLanguage).
        7. tags should contain 1 to 3 concise topic labels.
        8. score is a float between 0 and 1.
        9. reason explains why the quote is shareable.
        10. Output strict JSON only. Do not wrap with markdown.

        Output schema:
        {
          "candidates": [
            {
              "highlight_text": "string",
              "note_text": "string",
              "tags": ["string"],
              "score": 0.0,
              "reason": "string"
            }
          ]
        }

        Book:
        - title: \(request.bookMetadata.title)
        - author: \(request.bookMetadata.author ?? "unknown")
        - language: \(request.bookMetadata.language ?? "unknown")

        Excerpt metadata:
        - excerpt_id: \(request.excerpt.id)
        - chapter_order: \(request.excerpt.chapterOrder)
        - chapter_title: \(request.excerpt.chapterTitle)

        Excerpt text (copy highlight_text only from this block):
        <excerpt>
        \(request.excerpt.text)
        </excerpt>
        """
    }

    public func makeStage2Prompt(request: BatchStage2Request) -> String {
        let candidateRows = request.candidates.enumerated().map { index, candidate in
            Stage2PromptCandidate(
                id: candidate.id,
                order: index + 1,
                chapterOrder: candidate.chapterOrder,
                chapterTitle: candidate.chapterTitle,
                excerptId: candidate.excerptId,
                highlightText: candidate.highlightText,
                noteText: candidate.noteText,
                tags: candidate.tags,
                score: candidate.score
            )
        }
        let candidatesJSON = (try? encodePrettyJSON(candidateRows)) ?? "[]"
        let targetCount = max(1, request.targetCount)
        let minimumCount = min(targetCount, max(3, targetCount / 2))

        return """
        You are helping an eBook team pick final social-shareable highlights from pre-filtered candidates.

        Constraints:
        1. Select around \(targetCount) items (minimum \(minimumCount), maximum \(targetCount)).
        2. Prioritize clarity, shareability, and chapter diversity.
        3. Prefer highlights with enough substance to look visually full on a share card; avoid overly short one-liners when a stronger longer option exists.
        4. Avoid duplicate or near-duplicate highlights.
        5. Keep the result balanced across chapters when possible.
        6. For each selected item, provide a social post title and optional expanded description.
        7. post_title should be concise and hook-driven (about 35 to 110 characters).
        8. post_description should be 1 to 3 sentences and can be empty only if no good expansion is possible.
        9. Output strict JSON only. Do not wrap with markdown.

        Output schema:
        {
          "selected": [
            {
              "candidate_id": "string",
              "rank": 1,
              "score": 0.0,
              "reason": "string",
              "post_title": "string",
              "post_description": "string"
            }
          ]
        }

        Book:
        - title: \(request.bookMetadata.title)
        - author: \(request.bookMetadata.author ?? "unknown")
        - language: \(request.bookMetadata.language ?? "unknown")

        Output language for reason, post_title, and post_description: \(request.outputLanguage)

        Candidate list JSON:
        \(candidatesJSON)
        """
    }

    private func makeStage1RequestBody(prompt: String, provider: BatchAIProviderConfiguration) throws -> Data {
        var body: [String: Any] = [
            "model": provider.model,
            "messages": [
                ["role": "system", "content": "You extract social-shareable quotes from books and strictly follow JSON schema."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 1_200
        ]
        if shouldDisableThinking(for: provider.endpoint) {
            body["enable_thinking"] = false
        }
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw BatchError.runtime("Failed to serialize Stage 1 request body: \(error.localizedDescription)")
        }
    }

    private func makeStage2RequestBody(prompt: String, provider: BatchAIProviderConfiguration) throws -> Data {
        var body: [String: Any] = [
            "model": provider.model,
            "messages": [
                ["role": "system", "content": "You select final social-shareable quotes and strictly output JSON."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "max_tokens": 1_600
        ]
        if shouldDisableThinking(for: provider.endpoint) {
            body["enable_thinking"] = false
        }
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw BatchError.runtime("Failed to serialize Stage 2 request body: \(error.localizedDescription)")
        }
    }

    private func parseAssistantText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BatchError.runtime("Stage 1 response is not a JSON object.")
        }

        if let errorPayload = json["error"] as? [String: Any] {
            let message = (errorPayload["message"] as? String) ?? "unknown provider error"
            throw BatchError.runtime("Stage 1 provider error: \(message)")
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any]
        else {
            throw BatchError.runtime("Stage 1 response is missing choices[0].message.")
        }

        if let content = message["content"] as? String {
            return content
        }

        if let contentParts = message["content"] as? [[String: Any]] {
            let merged = contentParts.compactMap { part -> String? in
                if let text = part["text"] as? String {
                    return text
                }
                return nil
            }.joined(separator: "\n")
            if !merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return merged
            }
        }

        throw BatchError.runtime("Stage 1 response message content is empty.")
    }

    private func parseStage1Candidates(from responseText: String) throws -> [BatchStage1CandidateDraft] {
        let normalized = cleanupResponseBody(responseText)

        if let decodedObject = try? decodeStage1ResponseObject(from: normalized) {
            let sanitized = sanitizeCandidates(decodedObject.candidates)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        if let decodedArray = try? decodeStage1ResponseArray(from: normalized) {
            let sanitized = sanitizeCandidates(decodedArray)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        throw BatchError.runtime("Stage 1 response cannot be parsed into non-empty candidates.")
    }

    private func parseStage2Selections(from responseText: String) throws -> [BatchStage2SelectionDraft] {
        let normalized = cleanupResponseBody(responseText)

        if let decodedObject = try? decodeStage2ResponseObject(from: normalized) {
            let sanitized = sanitizeStage2Selections(decodedObject.selected)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        if let decodedArray = try? decodeStage2ResponseArray(from: normalized) {
            let sanitized = sanitizeStage2Selections(decodedArray)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        throw BatchError.runtime("Stage 2 response cannot be parsed into non-empty selections.")
    }

    private func decodeStage1ResponseObject(from text: String) throws -> Stage1ResponseEnvelope {
        let data = Data(text.utf8)
        return try JSONDecoder().decode(Stage1ResponseEnvelope.self, from: data)
    }

    private func decodeStage1ResponseArray(from text: String) throws -> [Stage1ResponseCandidate] {
        let data = Data(text.utf8)
        return try JSONDecoder().decode([Stage1ResponseCandidate].self, from: data)
    }

    private func decodeStage2ResponseObject(from text: String) throws -> Stage2ResponseEnvelope {
        let data = Data(text.utf8)
        return try JSONDecoder().decode(Stage2ResponseEnvelope.self, from: data)
    }

    private func decodeStage2ResponseArray(from text: String) throws -> [Stage2ResponseSelection] {
        let data = Data(text.utf8)
        return try JSONDecoder().decode([Stage2ResponseSelection].self, from: data)
    }

    private func sanitizeCandidates(_ rows: [Stage1ResponseCandidate]) -> [BatchStage1CandidateDraft] {
        rows.compactMap { row in
            let highlight = row.highlightText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !highlight.isEmpty else {
                return nil
            }

            let note = row.noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = row.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = row.tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let score = max(0, min(1, row.score ?? 0.5))

            return BatchStage1CandidateDraft(
                highlightText: highlight,
                noteText: note,
                tags: Array(tags.prefix(3)),
                score: score,
                reason: reason
            )
        }
    }

    private func sanitizeStage2Selections(_ rows: [Stage2ResponseSelection]) -> [BatchStage2SelectionDraft] {
        rows.compactMap { row in
            let candidateId = row.candidateId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidateId.isEmpty else {
                return nil
            }
            let reason = row.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let postTitle = normalizeOptionalText(row.postTitle)
            let postDescription = normalizeOptionalText(row.postDescription)
            let rank = (row.rank ?? 0) > 0 ? row.rank : nil
            let score = row.score.map { max(0, min(1, $0)) }
            return BatchStage2SelectionDraft(
                candidateId: candidateId,
                rank: rank,
                score: score,
                reason: reason,
                postTitle: postTitle,
                postDescription: postDescription
            )
        }
    }

    private func normalizeOptionalText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanupResponseBody(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if !lines.isEmpty, lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func encodePrettyJSON<T: Encodable>(_ object: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(object)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func makeChatCompletionsURL(endpoint: String) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BatchError.runtime("AI endpoint is empty.")
        }
        guard let baseURL = URL(string: trimmed) else {
            throw BatchError.runtime("Invalid AI endpoint URL: \(endpoint)")
        }
        if baseURL.path.hasSuffix("/chat/completions") {
            return baseURL
        }
        let suffix = trimmed.hasSuffix("/") ? "chat/completions" : "/chat/completions"
        guard let finalURL = URL(string: trimmed + suffix) else {
            throw BatchError.runtime("Invalid AI endpoint URL after path append: \(endpoint)")
        }
        return finalURL
    }

    private func shouldDisableThinking(for endpoint: String) -> Bool {
        guard let host = URL(string: endpoint)?.host?.lowercased() else {
            return false
        }
        return host.contains("dashscope") || host.contains("aliyun") || host.contains("tongyi")
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func parseDouble(_ fileValue: Double?, _ envValue: String?, defaultValue: Double) -> Double {
        if let fileValue, fileValue > 0 {
            return fileValue
        }
        if let envValue, let parsed = Double(envValue), parsed > 0 {
            return parsed
        }
        return defaultValue
    }

    private func parseInt(_ fileValue: Int?, _ envValue: String?, defaultValue: Int) -> Int {
        if let fileValue, fileValue >= 0 {
            return fileValue
        }
        if let envValue, let parsed = Int(envValue), parsed >= 0 {
            return parsed
        }
        return defaultValue
    }

    private static func defaultRequestExecutor(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()

        var responseData: Data?
        var response: URLResponse?
        var responseError: Error?

        let task = URLSession.shared.dataTask(with: request) { data, urlResponse, error in
            lock.lock()
            responseData = data
            response = urlResponse
            responseError = error
            lock.unlock()
            semaphore.signal()
        }
        task.resume()

        let timeout = max(request.timeoutInterval + 5, 10)
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            throw BatchError.runtime("AI request timed out after \(Int(request.timeoutInterval))s.")
        }

        lock.lock()
        defer { lock.unlock() }

        if let responseError {
            throw BatchError.runtime("AI request failed: \(responseError.localizedDescription)")
        }
        guard let responseData, let httpResponse = response as? HTTPURLResponse else {
            throw BatchError.runtime("AI response missing data or HTTP status.")
        }
        return (responseData, httpResponse)
    }
}

private struct ProviderConfigFile: Decodable {
    var endpoint: String?
    var apiKey: String?
    var model: String?
    var timeoutSeconds: Double?
    var maxRetryCount: Int?

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case apiKey
        case api_key
        case model
        case timeoutSeconds
        case timeout_seconds
        case maxRetryCount
        case max_retry_count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        if apiKey == nil {
            apiKey = try container.decodeIfPresent(String.self, forKey: .api_key)
        }
        model = try container.decodeIfPresent(String.self, forKey: .model)
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds)
        if timeoutSeconds == nil {
            timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeout_seconds)
        }
        maxRetryCount = try container.decodeIfPresent(Int.self, forKey: .maxRetryCount)
        if maxRetryCount == nil {
            maxRetryCount = try container.decodeIfPresent(Int.self, forKey: .max_retry_count)
        }
    }
}

private struct Stage1ResponseEnvelope: Decodable {
    var candidates: [Stage1ResponseCandidate]
}

private struct Stage1ResponseCandidate: Decodable {
    var highlightText: String
    var noteText: String
    var tags: [String]
    var score: Double?
    var reason: String

    enum CodingKeys: String, CodingKey {
        case highlightText
        case highlight_text
        case noteText
        case note_text
        case tags
        case score
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let camel = try container.decodeIfPresent(String.self, forKey: .highlightText) {
            highlightText = camel
        } else {
            highlightText = try container.decodeIfPresent(String.self, forKey: .highlight_text) ?? ""
        }
        if let camel = try container.decodeIfPresent(String.self, forKey: .noteText) {
            noteText = camel
        } else {
            noteText = try container.decodeIfPresent(String.self, forKey: .note_text) ?? ""
        }
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

private struct Stage2PromptCandidate: Encodable {
    var id: String
    var order: Int
    var chapterOrder: Int
    var chapterTitle: String
    var excerptId: String
    var highlightText: String
    var noteText: String
    var tags: [String]
    var score: Double

    enum CodingKeys: String, CodingKey {
        case id
        case order
        case chapterOrder = "chapter_order"
        case chapterTitle = "chapter_title"
        case excerptId = "excerpt_id"
        case highlightText = "highlight_text"
        case noteText = "note_text"
        case tags
        case score
    }
}

private struct Stage2ResponseEnvelope: Decodable {
    var selected: [Stage2ResponseSelection]

    private enum CodingKeys: String, CodingKey {
        case selected
        case selections
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let selected = try container.decodeIfPresent([Stage2ResponseSelection].self, forKey: .selected) {
            self.selected = selected
            return
        }
        if let selections = try container.decodeIfPresent([Stage2ResponseSelection].self, forKey: .selections) {
            self.selected = selections
            return
        }
        self.selected = try container.decodeIfPresent([Stage2ResponseSelection].self, forKey: .items) ?? []
    }
}

private struct Stage2ResponseSelection: Decodable {
    var candidateId: String
    var rank: Int?
    var score: Double?
    var reason: String
    var postTitle: String?
    var postDescription: String?

    enum CodingKeys: String, CodingKey {
        case candidateId
        case candidate_id
        case id
        case rank
        case score
        case reason
        case postTitle
        case post_title
        case title
        case postDescription
        case post_description
        case description
        case body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let camel = try container.decodeIfPresent(String.self, forKey: .candidateId) {
            candidateId = camel
        } else if let snake = try container.decodeIfPresent(String.self, forKey: .candidate_id) {
            candidateId = snake
        } else {
            candidateId = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        }
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        if let camel = try container.decodeIfPresent(String.self, forKey: .postTitle) {
            postTitle = camel
        } else if let snake = try container.decodeIfPresent(String.self, forKey: .post_title) {
            postTitle = snake
        } else {
            postTitle = try container.decodeIfPresent(String.self, forKey: .title)
        }
        if let camel = try container.decodeIfPresent(String.self, forKey: .postDescription) {
            postDescription = camel
        } else if let snake = try container.decodeIfPresent(String.self, forKey: .post_description) {
            postDescription = snake
        } else if let description = try container.decodeIfPresent(String.self, forKey: .description) {
            postDescription = description
        } else {
            postDescription = try container.decodeIfPresent(String.self, forKey: .body)
        }
    }
}
