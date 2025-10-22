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
        DebugLogger.info("AISummaryService: generateSummaryStream 调用")
        DebugLogger.info("AISummaryService: 书籍 = \(book.displayTitle)")
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    DebugLogger.info("AISummaryService: 开始流式生成流程")
                    
                    await MainActor.run {
                        isGenerating = true
                        generationProgress = 0.0
                        currentSummary = ""
                        error = nil
                        DebugLogger.info("AISummaryService: 状态已重置")
                    }
                    
                    // 检查缓存
                    DebugLogger.info("AISummaryService: 检查是否有缓存的摘要")
                    if let cachedSummary = try getCachedSummary(for: book) {
                        DebugLogger.success("AISummaryService: 找到缓存的摘要，使用缓存")
                        // 模拟流式输出缓存的摘要
                        await simulateStreamOutput(cachedSummary.summary, continuation: continuation)
                        continuation.finish()
                        
                        await MainActor.run {
                            isGenerating = false
                        }
                        return
                    }
                    
                    DebugLogger.info("AISummaryService: 没有缓存，需要生成新摘要")
                    
                    // 解析书籍内容
                    DebugLogger.info("AISummaryService: 开始解析书籍内容")
                    let chapters = try parseBookContent(book)
                    DebugLogger.success("AISummaryService: 书籍内容解析完成，共 \(chapters.count) 个章节")
                    
                    // 生成摘要并流式输出
                    try await generateSummaryWithStream(book: book, chapters: chapters, continuation: continuation)
                    
                    continuation.finish()
                    
                    await MainActor.run {
                        isGenerating = false
                        DebugLogger.success("AISummaryService: 流式生成完成，状态已更新")
                    }
                    
                } catch {
                    DebugLogger.error("AISummaryService: 流式生成出错 - \(error.localizedDescription)")
                    DebugLogger.error("AISummaryService: 错误详情 - \(error)")
                    
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
        DebugLogger.info("AISummaryService: 开始解析书籍内容")
        DebugLogger.info("AISummaryService: 书籍 = \(book.displayTitle)")
        
        guard let metadataString = book.metadata,
              let metadataData = metadataString.data(using: .utf8) else {
            DebugLogger.error("AISummaryService: 书籍metadata无效或为空")
            throw AISummaryError.invalidBookContent
        }
        
        DebugLogger.info("AISummaryService: metadata长度 = \(metadataString.count) 字符")
        
        let chaptersData = try JSONDecoder().decode([[String: String]].self, from: metadataData)
        DebugLogger.info("AISummaryService: 成功解码章节数据，原始章节数 = \(chaptersData.count)")
        
        let chapters = chaptersData.compactMap { chapterDict -> Chapter? in
            guard let title = chapterDict["title"],
                  let content = chapterDict["content"],
                  let orderString = chapterDict["order"],
                  let order = Int(orderString) else {
                DebugLogger.warning("AISummaryService: 跳过无效章节数据")
                return nil
            }
            return Chapter(title: title, content: content, order: order)
        }
        
        DebugLogger.success("AISummaryService: 书籍内容解析完成，有效章节数 = \(chapters.count)")
        
        // 输出前几个章节的信息
        for (index, chapter) in chapters.prefix(3).enumerated() {
            DebugLogger.info("AISummaryService: 章节[\(index+1)] - 标题=\(chapter.title), 内容长度=\(chapter.content.count)字符")
        }
        
        return chapters
    }
    
    private func generateBookSummary(book: Book, chapters: [Chapter]) async throws -> (summary: String, keyPoints: [String]) {
        DebugLogger.info("AISummaryService: 开始生成书籍摘要")
        DebugLogger.info("AISummaryService: 书籍 = \(book.displayTitle)")
        DebugLogger.info("AISummaryService: 章节数 = \(chapters.count)")
        
        // 构建提示词
        let prompt = buildSummaryPrompt(book: book, chapters: chapters)
        DebugLogger.info("AISummaryService: 已构建提示词")
        
        // 调用AI API（这里使用模拟实现）
        let response = try await callAIAPI(prompt: prompt)
        DebugLogger.success("AISummaryService: AI API调用成功")
        
        // 解析响应
        let result = parseSummaryResponse(response)
        DebugLogger.info("AISummaryService: 摘要长度 = \(result.summary.count)")
        DebugLogger.info("AISummaryService: 关键要点数 = \(result.keyPoints.count)")
        
        return result
    }
    
    private func generateChapterSummaries(chapters: [Chapter]) async throws -> [ChapterMapping] {
        DebugLogger.info("AISummaryService: 开始生成章节摘要")
        DebugLogger.info("AISummaryService: 总章节数 = \(chapters.count)")
        
        var mappings: [ChapterMapping] = []
        
        for (index, chapter) in chapters.enumerated() {
            DebugLogger.info("AISummaryService: 处理章节 [\(index+1)/\(chapters.count)] - \(chapter.title)")
            
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
            
            DebugLogger.success("AISummaryService: 章节[\(index+1)]摘要生成完成")
        }
        
        DebugLogger.success("AISummaryService: 所有章节摘要生成完成，共\(mappings.count)个")
        
        return mappings
    }
    
    private func generateSummaryWithStream(book: Book, chapters: [Chapter], continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        DebugLogger.info("AISummaryService: 开始流式生成摘要")
        DebugLogger.info("AISummaryService: 书籍 = \(book.displayTitle)")
        
        let prompt = buildSummaryPrompt(book: book, chapters: chapters)
        DebugLogger.info("AISummaryService: 流式生成提示词已构建")
        
        // 模拟流式API调用
        let fullSummary = try await callAIAPI(prompt: prompt)
        DebugLogger.success("AISummaryService: 流式API调用完成")
        DebugLogger.info("AISummaryService: 完整摘要长度 = \(fullSummary.count)")
        
        await simulateStreamOutput(fullSummary, continuation: continuation)
        DebugLogger.success("AISummaryService: 流式输出完成")
        
        // 缓存生成的摘要
        let (summary, keyPoints) = parseSummaryResponse(fullSummary)
        DebugLogger.info("AISummaryService: 开始生成章节摘要")
        let chapterMappings = try await generateChapterSummaries(chapters: chapters)
        DebugLogger.success("AISummaryService: 章节摘要生成完成，共 \(chapterMappings.count) 个章节")
        
        let bookSummary = BookSummary(
            id: UUID(),
            bookId: book.id,
            summary: summary,
            keyPoints: keyPoints,
            chapterMappings: chapterMappings,
            createdAt: Date()
        )
        
        DebugLogger.info("AISummaryService: 开始缓存摘要")
        try cacheSummary(bookSummary, for: book)
        DebugLogger.success("AISummaryService: 摘要已缓存到Core Data")
    }
    
    private func simulateStreamOutput(_ text: String, continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        DebugLogger.info("AISummaryService: 开始模拟流式输出")
        DebugLogger.info("AISummaryService: 文本总长度 = \(text.count) 字符")
        
        let words = text.components(separatedBy: " ")
        DebugLogger.info("AISummaryService: 分词数量 = \(words.count)")
        
        var currentText = ""
        
        for (index, word) in words.enumerated() {
            currentText += word + " "
            let textSnapshot = currentText
            continuation.yield(textSnapshot)
            
            await MainActor.run {
                currentSummary = textSnapshot
                generationProgress = Double(index + 1) / Double(words.count)
            }
            
            // 每10个词输出一次进度日志
            if (index + 1) % 10 == 0 {
                DebugLogger.info("AISummaryService: 流式输出进度 = \(Int(Double(index + 1) / Double(words.count) * 100))%")
            }
            
            // 模拟网络延迟
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        DebugLogger.success("AISummaryService: 流式输出完成")
    }
    
    private func buildSummaryPrompt(book: Book, chapters: [Chapter]) -> String {
        DebugLogger.info("AISummaryService: 开始构建摘要提示词")
        
        let bookInfo = """
        书名：\(book.displayTitle)
        作者：\(book.displayAuthor)
        章节数：\(chapters.count)
        """
        
        let content = chapters.prefix(3).map { chapter in
            "【\(chapter.title)】\n\(String(chapter.content.prefix(500)))..."
        }.joined(separator: "\n\n")
        
        let prompt = """
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
        
        DebugLogger.info("AISummaryService: === 提示词 (Prompt) 开始 ===")
        DebugLogger.info("\n\(prompt)")
        DebugLogger.info("AISummaryService: === 提示词 (Prompt) 结束 ===")
        DebugLogger.info("AISummaryService: 提示词总长度 = \(prompt.count) 字符")
        
        return prompt
    }
    
    private func buildChapterSummaryPrompt(chapter: Chapter) -> String {
        DebugLogger.info("AISummaryService: 开始构建章节摘要提示词")
        DebugLogger.info("AISummaryService: 章节标题 = \(chapter.title)")
        
        let prompt = """
        请为以下章节生成摘要：
        
        章节标题：\(chapter.title)
        章节内容：\(String(chapter.content.prefix(1000)))...
        
        请生成：
        1. 100-150字的章节摘要
        2. 2-3个关键要点
        
        格式要求简洁明了。
        """
        
        DebugLogger.info("AISummaryService: === 章节提示词开始 ===")
        DebugLogger.info("\n\(prompt)")
        DebugLogger.info("AISummaryService: === 章节提示词结束 ===")
        
        return prompt
    }
    
    private func callAIAPI(prompt: String) async throws -> String {
        DebugLogger.info("AISummaryService: ===== 开始调用AI API =====")
        DebugLogger.info("AISummaryService: API端点 = \(apiEndpoint)")
        DebugLogger.info("AISummaryService: 模型 = \(model)")
        DebugLogger.info("AISummaryService: API Key前缀 = \(String(apiKey.prefix(10)))...")
        DebugLogger.info("AISummaryService: 提示词长度 = \(prompt.count) 字符")
        
        // 这里是模拟实现，实际应该调用真实的API
        // 预留OpenAI API调用的位置
        
        /*
        // 真实API调用代码示例：
        DebugLogger.info("AISummaryService: 准备API请求体")
        let request = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: 0.7,
            maxTokens: 1000
        )
        
        DebugLogger.info("AISummaryService: 发送API请求...")
        let response = try await openAIClient.chat(request: request)
        DebugLogger.success("AISummaryService: API请求成功")
        DebugLogger.info("AISummaryService: 响应内容长度 = \(response.choices.first?.message.content.count ?? 0)")
        return response.choices.first?.message.content ?? ""
        */
        
        DebugLogger.warning("AISummaryService: 当前使用模拟响应（非真实API）")
        
        // 模拟响应
        DebugLogger.info("AISummaryService: 模拟网络延迟 1秒...")
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒延迟
        
        let mockResponse = """
        这是一本关于个人成长和自我发现的精彩作品。作者通过生动的故事情节，展现了主人公在人生旅途中的种种经历和感悟。书中深入探讨了人性的复杂性、成长的必要性以及面对挑战时的勇气与智慧。
        
        通过阅读这本书，读者可以获得关于人生意义、价值观塑造以及如何在困境中保持希望的深刻启发。作者的文笔优美，情节引人入胜，既有哲理思考又有情感共鸣，是一本值得反复品读的佳作。
        
        • 探索个人成长的心路历程
        • 面对人生挑战的智慧与勇气
        • 价值观的形成与人生意义的思考
        • 在困境中保持希望与坚持的重要性
        • 人际关系与自我认知的平衡
        """
        
        DebugLogger.info("AISummaryService: === AI响应 (Response) 开始 ===")
        DebugLogger.info("\n\(mockResponse)")
        DebugLogger.info("AISummaryService: === AI响应 (Response) 结束 ===")
        DebugLogger.info("AISummaryService: 响应内容长度 = \(mockResponse.count) 字符")
        DebugLogger.success("AISummaryService: ===== AI API调用完成 =====")
        
        return mockResponse
    }
    
    private func parseSummaryResponse(_ response: String) -> (summary: String, keyPoints: [String]) {
        DebugLogger.info("AISummaryService: 开始解析AI响应")
        DebugLogger.info("AISummaryService: 响应总长度 = \(response.count) 字符")
        
        let lines = response.components(separatedBy: "\n")
        DebugLogger.info("AISummaryService: 响应总行数 = \(lines.count)")
        
        var summary = ""
        var keyPoints: [String] = []
        var isKeyPointsSection = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("•") {
                isKeyPointsSection = true
                let keyPoint = trimmedLine.replacingOccurrences(of: "• ", with: "")
                keyPoints.append(keyPoint)
                DebugLogger.info("AISummaryService: 解析到关键要点 [\(keyPoints.count)]: \(keyPoint)")
            } else if !trimmedLine.isEmpty && !isKeyPointsSection {
                summary += trimmedLine + "\n"
            }
        }
        
        let finalSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        
        DebugLogger.success("AISummaryService: 响应解析完成")
        DebugLogger.info("AISummaryService: 摘要长度 = \(finalSummary.count) 字符")
        DebugLogger.info("AISummaryService: 关键要点数量 = \(keyPoints.count)")
        
        return (summary: finalSummary, keyPoints: keyPoints)
    }
    
    private func getCachedSummary(for book: Book) throws -> BookSummary? {
        DebugLogger.info("AISummaryService: 检查缓存摘要")
        
        guard let aiSummary = book.aiSummary,
              let aiKeyPointsString = book.aiKeyPoints,
              let generatedAt = book.aiSummaryGeneratedAt else {
            DebugLogger.info("AISummaryService: 没有找到缓存的摘要数据")
            return nil
        }
        
        DebugLogger.info("AISummaryService: 找到缓存摘要，生成时间 = \(generatedAt)")
        
        // 检查摘要是否过期（7天）
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        if generatedAt < sevenDaysAgo {
            DebugLogger.warning("AISummaryService: 缓存摘要已过期（超过7天）")
            return nil
        }
        
        DebugLogger.success("AISummaryService: 缓存摘要有效，将使用缓存")
        
        let keyPointsData = aiKeyPointsString.data(using: .utf8) ?? Data()
        let keyPoints = (try? JSONDecoder().decode([String].self, from: keyPointsData)) ?? []
        
        DebugLogger.info("AISummaryService: 缓存摘要长度 = \(aiSummary.count)")
        DebugLogger.info("AISummaryService: 缓存关键要点数 = \(keyPoints.count)")
        
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
        DebugLogger.info("AISummaryService: 开始缓存摘要")
        DebugLogger.info("AISummaryService: 书籍 = \(book.displayTitle)")
        DebugLogger.info("AISummaryService: 摘要长度 = \(summary.summary.count)")
        DebugLogger.info("AISummaryService: 关键要点数 = \(summary.keyPoints.count)")
        
        let keyPointsData = try JSONEncoder().encode(summary.keyPoints)
        let keyPointsString = String(data: keyPointsData, encoding: .utf8)
        
        DebugLogger.info("AISummaryService: 关键要点已序列化为JSON")
        
        book.aiSummary = summary.summary
        book.aiKeyPoints = keyPointsString
        book.aiSummaryGeneratedAt = summary.createdAt
        book.updatedAt = Date()
        
        DebugLogger.info("AISummaryService: Book对象属性已更新")
        
        // 保存到Core Data
        if let context = book.managedObjectContext {
            DebugLogger.info("AISummaryService: 准备保存到Core Data")
            try context.save()
            DebugLogger.success("AISummaryService: 摘要已成功保存到Core Data")
        } else {
            DebugLogger.warning("AISummaryService: Book对象没有关联的managedObjectContext")
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