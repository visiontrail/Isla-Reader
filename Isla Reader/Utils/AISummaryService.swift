//
//  AISummaryService.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/1/20.
//

import Foundation
import CoreData

struct BookSummary {
    let id: UUID
    let bookId: UUID
    let summary: String
    let keyPoints: [String]
    let chapterMappings: [ChapterMapping]
    let createdAt: Date
}

struct ChapterMapping {
    let chapterTitle: String
    let chapterOrder: Int
    let summary: String
    let keyPoints: [String]
}

class AISummaryService: ObservableObject {
    static let shared = AISummaryService()
    
    @Published var isGenerating = false
    @Published var generationProgress: Double = 0.0
    @Published var currentSummary: String = ""
    @Published var error: String?
    
    // API配置 - 预留位置，后续可配置
    private let apiEndpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    private let apiKey = "sk-700b5dceea294f099b30f097718b854d" // 预留位置
    private let model = "qwen-plus"
    
    private init() {}
    
    func generateSummary(for book: Book) async throws -> BookSummary {
        await MainActor.run {
            isGenerating = true
            generationProgress = 0.0
            currentSummary = ""
            error = nil
        }
        
        defer {
            Task { @MainActor in
                isGenerating = false
                generationProgress = 0.0
            }
        }
        
        do {
            // 1. 检查是否已有缓存的摘要
            await updateProgress(0.1)
            if let cachedSummary = try getCachedSummary(for: book) {
                await MainActor.run {
                    currentSummary = cachedSummary.summary
                }
                return cachedSummary
            }
            
            // 2. 解析书籍内容
            await updateProgress(0.2)
            let chapters = try parseBookContent(book)
            
            // 3. 生成全书摘要
            await updateProgress(0.3)
            let bookSummary = try await generateBookSummary(book: book, chapters: chapters)
            
            // 4. 生成章节摘要
            await updateProgress(0.5)
            let chapterMappings = try await generateChapterSummaries(chapters: chapters)
            
            // 5. 创建完整摘要对象
            await updateProgress(0.8)
            let summary = BookSummary(
                id: UUID(),
                bookId: book.id,
                summary: bookSummary.summary,
                keyPoints: bookSummary.keyPoints,
                chapterMappings: chapterMappings,
                createdAt: Date()
            )
            
            // 6. 缓存摘要
            await updateProgress(0.9)
            try cacheSummary(summary, for: book)
            
            await updateProgress(1.0)
            await MainActor.run {
                currentSummary = summary.summary
            }
            
            return summary
            
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
            throw error
        }
    }
    
    func generateSummaryStream(for book: Book) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    await MainActor.run {
                        isGenerating = true
                        generationProgress = 0.0
                        currentSummary = ""
                        error = nil
                    }
                    
                    // 检查缓存
                    if let cachedSummary = try getCachedSummary(for: book) {
                        // 模拟流式输出缓存的摘要
                        await simulateStreamOutput(cachedSummary.summary, continuation: continuation)
                        continuation.finish()
                        return
                    }
                    
                    // 解析书籍内容
                    let chapters = try parseBookContent(book)
                    
                    // 生成摘要并流式输出
                    try await generateSummaryWithStream(book: book, chapters: chapters, continuation: continuation)
                    
                    continuation.finish()
                    
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        isGenerating = false
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func parseBookContent(_ book: Book) throws -> [Chapter] {
        guard let metadataString = book.metadata,
              let metadataData = metadataString.data(using: .utf8) else {
            throw AISummaryError.invalidBookContent
        }
        
        let chaptersData = try JSONDecoder().decode([[String: String]].self, from: metadataData)
        
        return chaptersData.compactMap { chapterDict in
            guard let title = chapterDict["title"],
                  let content = chapterDict["content"],
                  let orderString = chapterDict["order"],
                  let order = Int(orderString) else {
                return nil
            }
            return Chapter(title: title, content: content, order: order)
        }
    }
    
    private func generateBookSummary(book: Book, chapters: [Chapter]) async throws -> (summary: String, keyPoints: [String]) {
        // 构建提示词
        let prompt = buildSummaryPrompt(book: book, chapters: chapters)
        
        // 调用AI API（这里使用模拟实现）
        let response = try await callAIAPI(prompt: prompt)
        
        // 解析响应
        return parseSummaryResponse(response)
    }
    
    private func generateChapterSummaries(chapters: [Chapter]) async throws -> [ChapterMapping] {
        var mappings: [ChapterMapping] = []
        
        for chapter in chapters {
            let prompt = buildChapterSummaryPrompt(chapter: chapter)
            let response = try await callAIAPI(prompt: prompt)
            let (summary, keyPoints) = parseSummaryResponse(response)
            
            let mapping = ChapterMapping(
                chapterTitle: chapter.title,
                chapterOrder: chapter.order,
                summary: summary,
                keyPoints: keyPoints
            )
            mappings.append(mapping)
        }
        
        return mappings
    }
    
    private func generateSummaryWithStream(book: Book, chapters: [Chapter], continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        let prompt = buildSummaryPrompt(book: book, chapters: chapters)
        
        // 模拟流式API调用
        let fullSummary = try await callAIAPI(prompt: prompt)
        await simulateStreamOutput(fullSummary, continuation: continuation)
        
        // 缓存生成的摘要
        let (summary, keyPoints) = parseSummaryResponse(fullSummary)
        let chapterMappings = try await generateChapterSummaries(chapters: chapters)
        
        let bookSummary = BookSummary(
            id: UUID(),
            bookId: book.id,
            summary: summary,
            keyPoints: keyPoints,
            chapterMappings: chapterMappings,
            createdAt: Date()
        )
        
        try cacheSummary(bookSummary, for: book)
    }
    
    private func simulateStreamOutput(_ text: String, continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        let words = text.components(separatedBy: " ")
        var currentText = ""
        
        for (index, word) in words.enumerated() {
            currentText += word + " "
            continuation.yield(currentText)
            
            await MainActor.run {
                currentSummary = currentText
                generationProgress = Double(index + 1) / Double(words.count)
            }
            
            // 模拟网络延迟
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
    
    private func buildSummaryPrompt(book: Book, chapters: [Chapter]) -> String {
        let bookInfo = """
        书名：\(book.displayTitle)
        作者：\(book.displayAuthor)
        章节数：\(chapters.count)
        """
        
        let content = chapters.prefix(3).map { chapter in
            "【\(chapter.title)】\n\(String(chapter.content.prefix(500)))..."
        }.joined(separator: "\n\n")
        
        return """
        请为以下书籍生成一份导读摘要：
        
        \(bookInfo)
        
        书籍内容节选：
        \(content)
        
        请生成：
        1. 一份200-300字的全书导读摘要，包含主要内容、核心观点和阅读价值
        2. 3-5个关键要点
        3. 简洁明了，适合快速了解书籍内容
        
        格式要求：
        - 摘要部分用自然段落形式
        - 关键要点用"• "开头的列表形式
        """
    }
    
    private func buildChapterSummaryPrompt(chapter: Chapter) -> String {
        return """
        请为以下章节生成摘要：
        
        章节标题：\(chapter.title)
        章节内容：\(String(chapter.content.prefix(1000)))...
        
        请生成：
        1. 100-150字的章节摘要
        2. 2-3个关键要点
        
        格式要求简洁明了。
        """
    }
    
    private func callAIAPI(prompt: String) async throws -> String {
        // 这里是模拟实现，实际应该调用真实的API
        // 预留OpenAI API调用的位置
        
        /*
        // 真实API调用代码示例：
        let request = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: 0.7,
            maxTokens: 1000
        )
        
        let response = try await openAIClient.chat(request: request)
        return response.choices.first?.message.content ?? ""
        */
        
        // 模拟响应
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒延迟
        
        return """
        这是一本关于个人成长和自我发现的精彩作品。作者通过生动的故事情节，展现了主人公在人生旅途中的种种经历和感悟。书中深入探讨了人性的复杂性、成长的必要性以及面对挑战时的勇气与智慧。
        
        通过阅读这本书，读者可以获得关于人生意义、价值观塑造以及如何在困境中保持希望的深刻启发。作者的文笔优美，情节引人入胜，既有哲理思考又有情感共鸣，是一本值得反复品读的佳作。
        
        • 探索个人成长的心路历程
        • 面对人生挑战的智慧与勇气
        • 价值观的形成与人生意义的思考
        • 在困境中保持希望与坚持的重要性
        • 人际关系与自我认知的平衡
        """
    }
    
    private func parseSummaryResponse(_ response: String) -> (summary: String, keyPoints: [String]) {
        let lines = response.components(separatedBy: "\n")
        var summary = ""
        var keyPoints: [String] = []
        var isKeyPointsSection = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("•") {
                isKeyPointsSection = true
                let keyPoint = trimmedLine.replacingOccurrences(of: "• ", with: "")
                keyPoints.append(keyPoint)
            } else if !trimmedLine.isEmpty && !isKeyPointsSection {
                summary += trimmedLine + "\n"
            }
        }
        
        return (summary: summary.trimmingCharacters(in: .whitespacesAndNewlines), keyPoints: keyPoints)
    }
    
    private func getCachedSummary(for book: Book) throws -> BookSummary? {
        guard let aiSummary = book.aiSummary,
              let aiKeyPointsString = book.aiKeyPoints,
              let generatedAt = book.aiSummaryGeneratedAt else {
            return nil
        }
        
        // 检查摘要是否过期（7天）
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        if generatedAt < sevenDaysAgo {
            return nil
        }
        
        let keyPointsData = aiKeyPointsString.data(using: .utf8) ?? Data()
        let keyPoints = (try? JSONDecoder().decode([String].self, from: keyPointsData)) ?? []
        
        return BookSummary(
            id: UUID(),
            bookId: book.id,
            summary: aiSummary,
            keyPoints: keyPoints,
            chapterMappings: [], // 章节摘要暂时不缓存
            createdAt: generatedAt
        )
    }
    
    private func cacheSummary(_ summary: BookSummary, for book: Book) throws {
        let keyPointsData = try JSONEncoder().encode(summary.keyPoints)
        let keyPointsString = String(data: keyPointsData, encoding: .utf8)
        
        book.aiSummary = summary.summary
        book.aiKeyPoints = keyPointsString
        book.aiSummaryGeneratedAt = summary.createdAt
        book.updatedAt = Date()
        
        // 保存到Core Data
        if let context = book.managedObjectContext {
            try context.save()
        }
    }
    
    @MainActor
    private func updateProgress(_ progress: Double) {
        generationProgress = progress
    }
}

enum AISummaryError: Error {
    case invalidBookContent
    case apiError(String)
    case networkError
    case parseError
    
    var localizedDescription: String {
        switch self {
        case .invalidBookContent:
            return "书籍内容格式无效"
        case .apiError(let message):
            return "AI服务错误：\(message)"
        case .networkError:
            return "网络连接错误"
        case .parseError:
            return "响应解析错误"
        }
    }
}