//
//  SkimmingModeService.swift
//  LanRead
//
//  Created by AI Assistant on 2025/1/22.
//

import Foundation
import CoreData

struct SkimmingChapterMetadata: Identifiable, Hashable {
    let title: String
    let content: String
    let order: Int
    let sourceChapterIndex: Int
    let sourceFragment: String?
    
    var id: Int { order }

    var readerChapterIndex: Int { max(sourceChapterIndex, 0) }

    init(
        title: String,
        content: String,
        order: Int,
        sourceChapterIndex: Int? = nil,
        sourceFragment: String? = nil
    ) {
        self.title = title
        self.content = content
        self.order = order
        self.sourceChapterIndex = max(sourceChapterIndex ?? order, 0)

        let trimmedFragment = sourceFragment?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedFragment, !trimmedFragment.isEmpty else {
            self.sourceFragment = nil
            return
        }
        self.sourceFragment = trimmedFragment.hasPrefix("#")
            ? String(trimmedFragment.dropFirst())
            : trimmedFragment
    }
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

struct SkimmingAdProgress: Codable, Equatable {
    var skimmingAIRequestCount: Int
    var forwardChapterSwipeCount: Int
    var interstitialPresentedCount: Int
    var thirdNoticeShownTriggerCounts: [Int]

    static let empty = SkimmingAdProgress(
        skimmingAIRequestCount: 0,
        forwardChapterSwipeCount: 0,
        interstitialPresentedCount: 0,
        thirdNoticeShownTriggerCounts: []
    )

    func normalized() -> SkimmingAdProgress {
        SkimmingAdProgress(
            skimmingAIRequestCount: max(0, skimmingAIRequestCount),
            forwardChapterSwipeCount: max(0, forwardChapterSwipeCount),
            interstitialPresentedCount: max(0, interstitialPresentedCount),
            thirdNoticeShownTriggerCounts: Array(
                Set(thirdNoticeShownTriggerCounts.filter { $0 > 0 })
            ).sorted()
        )
    }
}

enum SkimmingModeError: LocalizedError {
    case metadataMissing
    case metadataCorrupted
    case networkError
    case apiError(String)
    case parseError
    case permissionRequired
    
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
        case .permissionRequired:
            return NSLocalizedString("ai.error.permission_required", comment: "")
        }
    }
}

final class SkimmingModeService {
    static let shared = SkimmingModeService()
    
    private enum SkimmingPromptStrategy: String {
        case knownByModel = "known_by_model"
        case fullChapterFallback = "full_chapter_fallback"
    }

    private struct SkimmingPromptContext {
        let strategy: SkimmingPromptStrategy
        let chapterContent: String
        let decisionReason: String
        let originalChapterLength: Int
        let cleanedChapterLength: Int
    }

    private let decoder = JSONDecoder()
    private let cacheLock = NSLock()
    private var cache: [String: SkimmingChapterSummary] = [:]
    private let defaults = UserDefaults.standard
    private let skimmingProgressKeyPrefix = "skimming_last_chapter_"
    private let skimmingAdProgressKeyPrefix = "skimming_ad_progress_"
    
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
            return SkimmingChapterMetadata(
                title: title,
                content: content,
                order: order,
                sourceChapterIndex: order
            )
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
                SkimmingChapterMetadata(
                    title: $0.title,
                    content: $0.content,
                    order: $0.order,
                    sourceChapterIndex: $0.order
                )
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
                    order: index,
                    sourceChapterIndex: startIndex,
                    sourceFragment: item.fragment
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

    func adProgress(for book: Book) -> SkimmingAdProgress {
        let key = skimmingAdProgressKey(for: book)
        guard let data = defaults.data(forKey: key) else {
            return .empty
        }

        do {
            return try JSONDecoder().decode(SkimmingAdProgress.self, from: data).normalized()
        } catch {
            DebugLogger.warning("SkimmingModeService: 广告进度反序列化失败，已重置 - \(error.localizedDescription)")
            defaults.removeObject(forKey: key)
            return .empty
        }
    }

    func storeAdProgress(_ progress: SkimmingAdProgress, for book: Book) {
        let normalizedProgress = progress.normalized()
        do {
            let data = try JSONEncoder().encode(normalizedProgress)
            defaults.set(data, forKey: skimmingAdProgressKey(for: book))
        } catch {
            DebugLogger.warning("SkimmingModeService: 广告进度序列化失败，已跳过保存 - \(error.localizedDescription)")
        }
    }
    
    func clearInMemoryCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
    
    func clearStoredProgress(for bookIds: [UUID]) {
        guard !bookIds.isEmpty else { return }
        for id in bookIds {
            defaults.removeObject(forKey: skimmingProgressKey(for: id))
            defaults.removeObject(forKey: skimmingAdProgressKey(for: id))
        }
    }

    func clearAllStoredProgress() {
        for key in defaults.dictionaryRepresentation().keys where
            key.hasPrefix(skimmingProgressKeyPrefix) || key.hasPrefix(skimmingAdProgressKeyPrefix)
        {
            defaults.removeObject(forKey: key)
        }
    }
    
    func generateSkimmingSummary(for book: Book, chapter: SkimmingChapterMetadata) async throws -> SkimmingChapterSummary {
        if let cached = cachedSummary(for: book, chapter: chapter) {
            DebugLogger.info(
                "SkimmingModeService: 略读流程[缓存命中] book=\(book.displayTitle), chapter=\(chapter.title), order=\(chapter.order)"
            )
            return cached
        }

        DebugLogger.info(
            "SkimmingModeService: 略读流程[开始] book=\(book.displayTitle), author=\(book.displayAuthor), chapter=\(chapter.title), order=\(chapter.order), 原始章节长度=\(chapter.content.count) 字符"
        )
        
        let modelKnowsChapter: Bool
        do {
            DebugLogger.info("SkimmingModeService: 略读流程[步骤1] 开始章节知识探测")
            modelKnowsChapter = try await checkModelKnowledge(for: book, chapter: chapter)
            DebugLogger.info(
                "SkimmingModeService: 略读流程[步骤1结果] 章节知识探测结果 = \(modelKnowsChapter ? "YES(模型称已知)" : "NO(模型称未知)")"
            )
        } catch {
            DebugLogger.warning("SkimmingModeService: 章节知识探测失败，按未知处理 - \(error.localizedDescription)")
            modelKnowsChapter = false
            DebugLogger.info("SkimmingModeService: 略读流程[步骤1结果] 章节知识探测异常，强制按 NO 处理")
        }
        
        let context = buildPromptContext(for: chapter, modelKnowsChapter: modelKnowsChapter)
        DebugLogger.info(
            """
            SkimmingModeService: 略读流程[步骤2] 上下文策略判定完成
            - strategy = \(context.strategy.rawValue)
            - reason = \(context.decisionReason)
            - 原始章节长度 = \(context.originalChapterLength) 字符
            - 清洗后章节长度 = \(context.cleanedChapterLength) 字符
            - 最终注入提示词章节长度 = \(context.chapterContent.count) 字符
            """
        )
        
        let prompt = buildPrompt(book: book, chapter: chapter, context: context)
        DebugLogger.info("SkimmingModeService: === 略读提示词开始 ===")
        DebugLogger.info("\n\(prompt)")
        DebugLogger.info("SkimmingModeService: === 略读提示词结束 ===")
        DebugLogger.info("SkimmingModeService: 提示词长度 = \(prompt.count) 字符")
        
        let response = try await callAIAPI(prompt: prompt, source: .skimming)
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
    
    private func checkModelKnowledge(for book: Book, chapter: SkimmingChapterMetadata) async throws -> Bool {
        let normalizedBookTitle = normalizeTitle(book.displayTitle)
        let normalizedAuthor = normalizeTitle(book.displayAuthor)
        let normalizedChapterTitle = normalizeTitle(chapter.title)

        DebugLogger.info(
            """
            SkimmingModeService: 章节知识探测输入
            - bookTitle = \(normalizedBookTitle)
            - author = \(normalizedAuthor)
            - chapterTitle = \(normalizedChapterTitle)
            - chapterOrder = \(chapter.order)
            """
        )
        
        let prompt = """
        You are doing a binary knowledge check for a specific book chapter.
        
        Book title: \(normalizedBookTitle)
        Author: \(normalizedAuthor)
        Chapter title: \(normalizedChapterTitle)
        Chapter order: \(chapter.order)
        
        Reply with exactly one uppercase word:
        YES
        or
        NO
        
        Rules:
        - Reply YES only if your training knowledge is sufficient to produce a reliable structure-first skimming summary for this chapter without chapter text.
        - If uncertain, reply NO.
        - Do not output anything else.
        """

        DebugLogger.info("SkimmingModeService: === 章节知识探测提示词开始 ===")
        DebugLogger.info("\n\(prompt)")
        DebugLogger.info("SkimmingModeService: === 章节知识探测提示词结束 ===")
        DebugLogger.info("SkimmingModeService: 章节知识探测提示词长度 = \(prompt.count) 字符")
        
        let response = try await callAIAPI(
            prompt: prompt,
            source: .skimming,
            temperature: 0.0,
            maxTokens: 8
        )
        
        let normalized = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        DebugLogger.info(
            "SkimmingModeService: 章节知识探测响应 raw=\(response.trimmingCharacters(in: .whitespacesAndNewlines)), normalized=\(normalized)"
        )
        
        if normalized.hasPrefix("YES") {
            return true
        }
        
        if normalized.hasPrefix("NO") {
            return false
        }
        
        DebugLogger.warning("SkimmingModeService: 章节知识探测响应无法识别，按 NO 处理。原始响应 = \(response)")
        return false
    }

    private func buildPromptContext(for chapter: SkimmingChapterMetadata, modelKnowsChapter: Bool) -> SkimmingPromptContext {
        if modelKnowsChapter {
            return SkimmingPromptContext(
                strategy: .knownByModel,
                chapterContent: "",
                decisionReason: "knowledge_check=YES",
                originalChapterLength: chapter.content.count,
                cleanedChapterLength: 0
            )
        }

        let cleanedContent = cleanAndCompressText(chapter.content)
        
        return SkimmingPromptContext(
            strategy: .fullChapterFallback,
            chapterContent: cleanedContent,
            decisionReason: "knowledge_check=NO_or_error",
            originalChapterLength: chapter.content.count,
            cleanedChapterLength: cleanedContent.count
        )
    }

    private func buildPrompt(book: Book, chapter: SkimmingChapterMetadata, context: SkimmingPromptContext) -> String {
        let language = AppSettings.shared.language.aiOutputLanguageName()
        
        let contextPolicy: String
        switch context.strategy {
        case .knownByModel:
            contextPolicy = """
            Strategy: The model reported it already knows this chapter from training knowledge.
            Generate the skimming summary directly using prior knowledge and keep the current output JSON format.
            If uncertain, stay high-level and avoid fabricated details.
            """
        case .fullChapterFallback:
            contextPolicy = """
            Strategy: The model reported it does not know this chapter.
            Use the full chapter content provided below after local cleaning/compression.
            Do not invent details that are not grounded in the chapter content.
            """
        }
        
        let chapterContentSection: String
        if context.chapterContent.isEmpty {
            chapterContentSection = """
            CHAPTER CONTENT:
            Not provided (knowledge-first path).
            """
        } else {
            chapterContentSection = """
            CHAPTER CONTENT START
            \(context.chapterContent)
            CHAPTER CONTENT END
            """
        }
        
        return """
        You are IslaBooks' inspectional reading coach.
        Follow Mortimer J. Adler's "How to Read a Book" skimming method to help readers quickly grasp the structure, turning points, and key questions of a chapter without diving into full detail.
        
        TASK CONTEXT:
        - Book Title: \(book.title)
        - Chapter Title: \(chapter.title)
        - Chapter Order: \(chapter.order)
        - Reading Goal: expose architecture, thesis, transitions, and entry questions for deeper study.
        
        CONTEXT POLICY:
        \(contextPolicy)
        
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
        - Align tone with LanRead docs/reading_interaction_design.md guidance on "略读模式".
        - Respect How to Read a Book inspectional reading mindset: emphasize skeleton first, questions second, details last.
        
        \(chapterContentSection)
        """
    }
    
    private func cleanAndCompressText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
        
        normalized = normalized.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        
        let rawLines = normalized.components(separatedBy: .newlines)
        var lineFrequency: [String: Int] = [:]
        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lineFrequency[trimmed, default: 0] += 1
        }
        
        var cleanedLines: [String] = []
        var previousWasEmpty = false
        
        for rawLine in rawLines {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if line.isEmpty {
                if !previousWasEmpty {
                    cleanedLines.append("")
                    previousWasEmpty = true
                }
                continue
            }
            
            if shouldDropNoiseLine(line) || shouldDropRepeatedHeaderOrFooterLine(line, frequency: lineFrequency) {
                continue
            }
            
            line = line.replacingOccurrences(of: #"[-=*~_•·]{6,}"#, with: " ", options: .regularExpression)
            line = line.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !line.isEmpty else {
                continue
            }
            
            cleanedLines.append(line)
            previousWasEmpty = false
        }
        
        return cleanedLines
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func shouldDropNoiseLine(_ line: String) -> Bool {
        if line.range(of: #"^[-=*~_•·]{4,}$"#, options: .regularExpression) != nil {
            return true
        }
        
        if line.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil {
            return true
        }
        
        if line.range(of: #"^(?i:page)\s*\d+(\s*/\s*\d+)?$"#, options: .regularExpression) != nil {
            return true
        }
        
        if line.range(of: #"^(?i:p\.)\s*\d+$"#, options: .regularExpression) != nil {
            return true
        }
        
        if line.range(of: #"^第\s*\d+\s*页$"#, options: .regularExpression) != nil {
            return true
        }
        
        if line.range(of: #"^[^\p{L}\p{N}]{6,}$"#, options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    private func shouldDropRepeatedHeaderOrFooterLine(_ line: String, frequency: [String: Int]) -> Bool {
        guard let count = frequency[line], count >= 3 else {
            return false
        }
        
        guard line.count <= 80 else {
            return false
        }
        
        if line.range(of: #"[.!?。！？；;]"#, options: .regularExpression) != nil {
            return false
        }
        
        let words = line.split(whereSeparator: \.isWhitespace).count
        return words <= 12
    }
    
    private func normalizeTitle(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func callAIAPI(
        prompt: String,
        source: UsageMetricsSource = .skimming,
        temperature: Double = 0.4,
        maxTokens: Int = 1200
    ) async throws -> String {
        guard AIConsentManager.shared.hasExplicitPermission() else {
            DebugLogger.warning("SkimmingModeService: 用户未授权，已阻止 AI 请求")
            throw SkimmingModeError.permissionRequired
        }

        let config: AIConfiguration
        do {
            config = try await AIConfig.current()
        } catch {
            throw SkimmingModeError.apiError(error.localizedDescription)
        }
        
        guard let url = URL(string: "\(config.endpoint)/chat/completions") else {
            throw SkimmingModeError.apiError("Invalid API endpoint")
        }
        
        var body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        if AICompatibilityOptions.shouldExplicitlyDisableThinking(for: config.endpoint) {
            body["enable_thinking"] = false
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw SkimmingModeError.apiError("Unable to encode request body")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let startTime = Date()
        let requestBytes = jsonData.count
        var statusCode = 0
        var tokensUsed: Int?
        var errorReason: String?
        defer {
            let latency = Date().timeIntervalSince(startTime) * 1000
            UsageMetricsReporter.shared.record(
                interface: UsageMetricsInterface.chatCompletions,
                statusCode: statusCode,
                latencyMs: latency,
                requestBytes: requestBytes,
                tokens: tokensUsed,
                retryCount: 0,
                source: source,
                errorReason: errorReason
            )
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SkimmingModeError.networkError
            }
            statusCode = httpResponse.statusCode
            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                errorReason = message
                throw SkimmingModeError.apiError("HTTP \(httpResponse.statusCode): \(message)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SkimmingModeError.parseError
            }
            if let usage = json["usage"] as? [String: Any] {
                tokensUsed = usage["total_tokens"] as? Int ?? usage["completion_tokens"] as? Int
            }
            return content
        } catch let error as SkimmingModeError {
            errorReason = error.localizedDescription
            throw error
        } catch {
            errorReason = error.localizedDescription
            throw SkimmingModeError.networkError
        }
    }
    
    static func cacheKey(
        bookID: UUID,
        chapterOrder: Int,
        language: AppLanguage = AppSettings.shared.language,
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        localeIdentifier: String = Locale.current.identifier
    ) -> String {
        let cacheLanguage = language.cacheIdentifier(
            preferredLocalizations: preferredLocalizations,
            localeIdentifier: localeIdentifier
        )
        return "\(bookID.uuidString)-\(chapterOrder)-\(cacheLanguage)"
    }

    private func cacheKey(for book: Book, chapter: SkimmingChapterMetadata) -> String {
        Self.cacheKey(bookID: book.id, chapterOrder: chapter.order)
    }
    
    private func skimmingProgressKey(for book: Book) -> String {
        skimmingProgressKey(for: book.id)
    }
    
    private func skimmingProgressKey(for bookId: UUID) -> String {
        "\(skimmingProgressKeyPrefix)\(bookId.uuidString)"
    }

    private func skimmingAdProgressKey(for book: Book) -> String {
        skimmingAdProgressKey(for: book.id)
    }

    private func skimmingAdProgressKey(for bookId: UUID) -> String {
        "\(skimmingAdProgressKeyPrefix)\(bookId.uuidString)"
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
