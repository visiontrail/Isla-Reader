//
//  SkimmingModeService.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/1/22.
//

import Foundation
import CoreData

struct SkimmingChapterMetadata: Identifiable, Hashable {
    let title: String
    let content: String
    let order: Int
    
    var id: Int { order }
}

struct SkimmingStructurePoint: Codable, Hashable, Identifiable {
    let label: String
    let insight: String
    
    var id: String {
        "\(label)-\(insight)"
    }
}

struct SkimmingChapterSummary: Codable, Identifiable, Hashable {
    let chapterTitle: String
    let readingGoal: String
    let structure: [SkimmingStructurePoint]
    let keySentences: [String]
    let keywords: [String]
    let inspectionQuestions: [String]
    let aiNarrative: String
    let estimatedMinutes: Int
    
    var id: String {
        chapterTitle + "-" + readingGoal
    }
    
    enum CodingKeys: String, CodingKey {
        case chapterTitle
        case readingGoal
        case structure
        case keySentences
        case keywords
        case inspectionQuestions
        case aiNarrative
        case estimatedMinutes
    }
    
    init(chapterTitle: String,
         readingGoal: String,
         structure: [SkimmingStructurePoint],
         keySentences: [String],
         keywords: [String],
         inspectionQuestions: [String],
         aiNarrative: String,
         estimatedMinutes: Int) {
        self.chapterTitle = chapterTitle
        self.readingGoal = readingGoal
        self.structure = structure
        self.keySentences = keySentences
        self.keywords = keywords
        self.inspectionQuestions = inspectionQuestions
        self.aiNarrative = aiNarrative
        self.estimatedMinutes = estimatedMinutes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chapterTitle = try container.decodeIfPresent(String.self, forKey: .chapterTitle) ?? ""
        self.readingGoal = try container.decodeIfPresent(String.self, forKey: .readingGoal) ?? ""
        self.structure = try container.decodeIfPresent([SkimmingStructurePoint].self, forKey: .structure) ?? []
        self.keySentences = try container.decodeIfPresent([String].self, forKey: .keySentences) ?? []
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.inspectionQuestions = try container.decodeIfPresent([String].self, forKey: .inspectionQuestions) ?? []
        self.aiNarrative = try container.decodeIfPresent(String.self, forKey: .aiNarrative) ?? ""
        
        if let minutes = try? container.decode(Int.self, forKey: .estimatedMinutes) {
            self.estimatedMinutes = minutes
        } else if let minuteString = try? container.decode(String.self, forKey: .estimatedMinutes),
                  let minutes = Int(minuteString.filter({ $0.isNumber })) {
            self.estimatedMinutes = minutes
        } else {
            self.estimatedMinutes = 3
        }
    }
}

enum SkimmingModeError: LocalizedError {
    case metadataMissing
    case metadataCorrupted
    case networkError
    case apiError(String)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .metadataMissing:
            return NSLocalizedString("skimming.error.metadata_missing", comment: "")
        case .metadataCorrupted:
            return NSLocalizedString("skimming.error.metadata_corrupted", comment: "")
        case .networkError:
            return NSLocalizedString("skimming.error.network", comment: "")
        case .apiError(let message):
            return message
        case .parseError:
            return NSLocalizedString("skimming.error.parse", comment: "")
        }
    }
}

final class SkimmingModeService {
    static let shared = SkimmingModeService()
    
    private let decoder = JSONDecoder()
    private let cacheLock = NSLock()
    private var cache: [String: SkimmingChapterSummary] = [:]
    private let defaults = UserDefaults.standard
    private let skimmingProgressKeyPrefix = "skimming_last_chapter_"
    
    private init() {}
    
    func chapters(from book: Book) throws -> [SkimmingChapterMetadata] {
        if let enriched = try? buildChaptersFromFile(book: book), !enriched.isEmpty {
            return enriched
        }
        
        return try decodeChaptersFromMetadata(book)
    }
    
    private func decodeChaptersFromMetadata(_ book: Book) throws -> [SkimmingChapterMetadata] {
        guard let metadataString = book.metadata,
              let data = metadataString.data(using: .utf8) else {
            throw SkimmingModeError.metadataMissing
        }
        
        guard let rawChapters = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            throw SkimmingModeError.metadataCorrupted
        }
        
        let chapters = rawChapters.compactMap { dict -> SkimmingChapterMetadata? in
            guard let title = dict["title"],
                  let content = dict["content"],
                  let orderString = dict["order"],
                  let order = Int(orderString) else {
                return nil
            }
            return SkimmingChapterMetadata(title: title, content: content, order: order)
        }
        
        return chapters.sorted { $0.order < $1.order }
    }
    
    private func buildChaptersFromFile(book: Book) throws -> [SkimmingChapterMetadata] {
        guard let resolution = BookFileLocator.resolveFileURL(from: book.filePath) else {
            DebugLogger.error("SkimmingModeService: 找不到书籍文件，路径: \(book.filePath)")
            throw SkimmingModeError.metadataMissing
        }
        
        let fileURL = resolution.url
        let metadata = try EPubParser.parseEPub(from: fileURL)
        let parsedChapters = metadata.chapters
        
        guard !parsedChapters.isEmpty else {
            throw SkimmingModeError.metadataMissing
        }
        
        let tocItems = metadata.tocItems
        guard !tocItems.isEmpty else {
            return parsedChapters.map {
                SkimmingChapterMetadata(title: $0.title, content: $0.content, order: $0.order)
            }
        }
        
        var skimmingChapters: [SkimmingChapterMetadata] = []
        
        for (index, item) in tocItems.enumerated() {
            guard item.chapterIndex < parsedChapters.count else { continue }
            
            let startIndex = max(0, item.chapterIndex)
            let nextSiblingChapterIndex = tocItems[(index + 1)...].first(where: { $0.level <= item.level })?.chapterIndex ?? parsedChapters.count
            let endIndex = max(startIndex + 1, min(nextSiblingChapterIndex, parsedChapters.count))
            
            let combinedContent = parsedChapters[startIndex..<endIndex]
                .map { $0.content }
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let safeContent = combinedContent.isEmpty ? parsedChapters[startIndex].content : combinedContent
            
            skimmingChapters.append(
                SkimmingChapterMetadata(
                    title: item.title,
                    content: safeContent,
                    order: index
                )
            )
        }
        
        return skimmingChapters
    }
    
    func cachedSummary(for book: Book, chapter: SkimmingChapterMetadata) -> SkimmingChapterSummary? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        
        // 首先检查内存缓存
        let key = cacheKey(for: book, chapter: chapter)
        if let memoryCached = cache[key] {
            return memoryCached
        }
        
        // 如果内存中没有，从Core Data加载
        if let persistedSummary = loadSummaryFromPersistence(for: book, chapter: chapter) {
            cache[key] = persistedSummary // 同时放入内存缓存
            return persistedSummary
        }
        
        return nil
    }
    
    func store(summary: SkimmingChapterSummary, for book: Book, chapter: SkimmingChapterMetadata) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        let key = cacheKey(for: book, chapter: chapter)
        cache[key] = summary
        
        // 持久化到Core Data
        saveSummaryToPersistence(summary, for: book, chapter: chapter)
    }
    
    func lastVisitedChapterIndex(for book: Book) -> Int? {
        let key = skimmingProgressKey(for: book)
        let index = defaults.object(forKey: key) as? Int
        guard let index, index >= 0 else { return nil }
        return index
    }
    
    func storeLastVisitedChapterIndex(_ index: Int, for book: Book) {
        guard index >= 0 else { return }
        defaults.set(index, forKey: skimmingProgressKey(for: book))
    }
    
    func clearInMemoryCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
    
    func clearStoredProgress(for bookIds: [UUID]) {
        guard !bookIds.isEmpty else { return }
        for id in bookIds {
            let key = skimmingProgressKey(for: id)
            defaults.removeObject(forKey: key)
        }
    }
    
    func clearAllStoredProgress() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(skimmingProgressKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
    
    func generateSkimmingSummary(for book: Book, chapter: SkimmingChapterMetadata) async throws -> SkimmingChapterSummary {
        if let cached = cachedSummary(for: book, chapter: chapter) {
            return cached
        }
        
        let prompt = buildPrompt(book: book, chapter: chapter)
        DebugLogger.info("SkimmingModeService: === 略读提示词开始 ===")
        DebugLogger.info("\n\(prompt)")
        DebugLogger.info("SkimmingModeService: === 略读提示词结束 ===")
        DebugLogger.info("SkimmingModeService: 提示词长度 = \(prompt.count) 字符")
        
        let response = try await callAIAPI(prompt: prompt)
        let summary = try parseSummary(from: response, fallbackTitle: chapter.title)
        store(summary: summary, for: book, chapter: chapter)
        return summary
    }
    
    private func parseSummary(from response: String, fallbackTitle: String) throws -> SkimmingChapterSummary {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let summary = try? decoder.decode(SkimmingChapterSummary.self, from: data) {
            return summary
        }
        
        if let jsonRange = trimmed.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) {
            let jsonString = String(trimmed[jsonRange])
            if let data = jsonString.data(using: .utf8),
               let summary = try? decoder.decode(SkimmingChapterSummary.self, from: data) {
                return summary
            }
        }
        
        let fallbackStructure = [
            SkimmingStructurePoint(label: NSLocalizedString("skimming.fallback.structure_title", comment: ""), insight: fallbackTitle)
        ]
        return SkimmingChapterSummary(
            chapterTitle: fallbackTitle,
            readingGoal: NSLocalizedString("skimming.fallback.goal", comment: ""),
            structure: fallbackStructure,
            keySentences: [NSLocalizedString("skimming.fallback.key_sentence", comment: "")],
            keywords: [NSLocalizedString("skimming.fallback.keyword", comment: "")],
            inspectionQuestions: [NSLocalizedString("skimming.fallback.question", comment: "")],
            aiNarrative: response,
            estimatedMinutes: 3
        )
    }
    
    private func buildPrompt(book: Book, chapter: SkimmingChapterMetadata) -> String {
        let chapterExcerpt = chapter.content
        let language = AppSettings.shared.language == .en ? "English" : "Simplified Chinese"
        
        return """
        You are IslaBooks' inspectional reading coach.
        Follow Mortimer J. Adler's "How to Read a Book" skimming method to help readers quickly grasp the structure, turning points, and key questions of a chapter without diving into full detail.
        
        TASK CONTEXT:
        - Book Title: \(book.title)
        - Chapter Title: \(chapter.title)
        - Chapter Order: \(chapter.order)
        - Reading Goal: expose architecture, thesis, transitions, and entry questions for deeper study.
        
        OUTPUT FORMAT: respond ONLY with valid JSON matching this schema:
        {
          "chapterTitle": string,
          "readingGoal": string,
          "structure": [{"label": string, "insight": string} x3-5],
          "keySentences": [string x3],
          "keywords": [string x5 with conceptual importance],
          "inspectionQuestions": [string x2-3],
          "aiNarrative": "markdown paragraphs summarizing chapter skeleton, transitions, and quick takeaways",
          "estimatedMinutes": integer between 2 and 6
        }
        
        RENDERING RULES:
        - Use \(language).
        - structure entries should surface chapter spine: opening hook, argumentative peaks, closing signal.
        - keySentences must be original sentences extracted or paraphrased from the chapter to illustrate turning points.
        - aiNarrative must stay concise (<220 words) but vivid, referencing keywords inline.
        - Align tone with Isla Reader docs/reading_interaction_design.md guidance on "略读模式".
        - Respect How to Read a Book inspectional reading mindset: emphasize skeleton first, questions second, details last.
        
        CHAPTER CONTENT START
        \(chapterExcerpt)
        CHAPTER CONTENT END
        """
    }
    
    private func callAIAPI(prompt: String) async throws -> String {
        let config: AIConfiguration
        do {
            config = try await AIConfig.current()
        } catch {
            throw SkimmingModeError.apiError(error.localizedDescription)
        }
        
        guard let url = URL(string: "\(config.endpoint)/chat/completions") else {
            throw SkimmingModeError.apiError("Invalid API endpoint")
        }
        
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.4,
            "max_tokens": 1200
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw SkimmingModeError.apiError("Unable to encode request body")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SkimmingModeError.networkError
            }
            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SkimmingModeError.apiError("HTTP \(httpResponse.statusCode): \(message)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SkimmingModeError.parseError
            }
            return content
        } catch let error as SkimmingModeError {
            throw error
        } catch {
            throw SkimmingModeError.networkError
        }
    }
    
    private func cacheKey(for book: Book, chapter: SkimmingChapterMetadata) -> String {
        "\(book.id.uuidString)-\(chapter.order)"
    }
    
    private func skimmingProgressKey(for book: Book) -> String {
        skimmingProgressKey(for: book.id)
    }
    
    private func skimmingProgressKey(for bookId: UUID) -> String {
        "\(skimmingProgressKeyPrefix)\(bookId.uuidString)"
    }
    
    // MARK: - Persistence Methods
    
    private func loadSummaryFromPersistence(for book: Book, chapter: SkimmingChapterMetadata) -> SkimmingChapterSummary? {
        guard let summariesJSON = book.skimmingSummaries,
              let data = summariesJSON.data(using: .utf8),
              let summariesDict = try? JSONDecoder().decode([String: SkimmingChapterSummary].self, from: data) else {
            return nil
        }
        
        let key = cacheKey(for: book, chapter: chapter)
        return summariesDict[key]
    }
    
    private func saveSummaryToPersistence(_ summary: SkimmingChapterSummary, for book: Book, chapter: SkimmingChapterMetadata) {
        let context = PersistenceController.shared.container.viewContext
        
        context.perform {
            // 加载现有的摘要字典
            var summariesDict: [String: SkimmingChapterSummary] = [:]
            if let existingJSON = book.skimmingSummaries,
               let data = existingJSON.data(using: .utf8),
               let existing = try? JSONDecoder().decode([String: SkimmingChapterSummary].self, from: data) {
                summariesDict = existing
            }
            
            // 添加新的摘要
            let key = self.cacheKey(for: book, chapter: chapter)
            summariesDict[key] = summary
            
            // 序列化并保存
            if let data = try? JSONEncoder().encode(summariesDict),
               let jsonString = String(data: data, encoding: .utf8) {
                book.skimmingSummaries = jsonString
                
                do {
                    try context.save()
                    DebugLogger.info("SkimmingModeService: 摘要已持久化 - \(chapter.title)")
                } catch {
                    DebugLogger.error("SkimmingModeService: 持久化失败 - \(error.localizedDescription)")
                }
            }
        }
    }
}
