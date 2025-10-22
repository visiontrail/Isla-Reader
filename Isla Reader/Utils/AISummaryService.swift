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
        
        // Get localized strings based on user's language setting
        let bookName = NSLocalizedString("ai.summary.book_name", comment: "")
        let author = NSLocalizedString("ai.summary.author", comment: "")
        let chapterCount = NSLocalizedString("ai.summary.chapter_count", comment: "")
        
        let bookInfo = """
        \(bookName) \(book.displayTitle)
        \(author) \(book.displayAuthor)
        \(chapterCount) \(chapters.count)
        """
        
        // Include more chapters and more content per chapter for better summary
        // Use up to 10 chapters with 2000 chars each to provide comprehensive context
        let chaptersToInclude = min(chapters.count, 10)
        let content = chapters.prefix(chaptersToInclude).map { chapter in
            let contentPreview = String(chapter.content.prefix(2000))
            return "【\(chapter.title)】\n\(contentPreview)\(chapter.content.count > 2000 ? "..." : "")"
        }.joined(separator: "\n\n")
        
        // Get localized prompt strings
        let promptTitle = NSLocalizedString("ai.summary.book.prompt.title", comment: "")
        let bookInfoLabel = NSLocalizedString("ai.summary.book.prompt.book_info", comment: "")
        let contentExcerpt = NSLocalizedString("ai.summary.book.prompt.content_excerpt", comment: "")
        let requirements = NSLocalizedString("ai.summary.book.prompt.requirements", comment: "")
        let requirement1 = NSLocalizedString("ai.summary.book.prompt.requirement1", comment: "")
        let requirement2 = NSLocalizedString("ai.summary.book.prompt.requirement2", comment: "")
        let requirement3 = NSLocalizedString("ai.summary.book.prompt.requirement3", comment: "")
        let format = NSLocalizedString("ai.summary.book.prompt.format", comment: "")
        let format1 = NSLocalizedString("ai.summary.book.prompt.format1", comment: "")
        let format2 = NSLocalizedString("ai.summary.book.prompt.format2", comment: "")
        let language = NSLocalizedString("ai.summary.book.prompt.language", comment: "")
        
        let prompt = """
        \(promptTitle)
        
        \(bookInfoLabel)
        \(bookInfo)
        
        \(contentExcerpt)
        \(content)
        
        \(requirements)
        \(requirement1)
        \(requirement2)
        \(requirement3)
        
        \(format)
        \(format1)
        \(format2)
        \(language)
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
        
        // Get localized strings based on user's language setting
        let promptTitle = NSLocalizedString("ai.summary.chapter.prompt.title", comment: "")
        let chapterTitle = NSLocalizedString("ai.summary.chapter.prompt.chapter_title", comment: "")
        let chapterContent = NSLocalizedString("ai.summary.chapter.prompt.chapter_content", comment: "")
        let requirements = NSLocalizedString("ai.summary.chapter.prompt.requirements", comment: "")
        let requirement1 = NSLocalizedString("ai.summary.chapter.prompt.requirement1", comment: "")
        let requirement2 = NSLocalizedString("ai.summary.chapter.prompt.requirement2", comment: "")
        let format = NSLocalizedString("ai.summary.chapter.prompt.format", comment: "")
        let language = NSLocalizedString("ai.summary.chapter.prompt.language", comment: "")
        
        // Include full chapter content or more substantial portion for accurate summary
        // Use up to 5000 characters or full content if shorter
        let maxContentLength = 5000
        let contentToUse = chapter.content.count > maxContentLength ? 
            String(chapter.content.prefix(maxContentLength)) + "..." : 
            chapter.content
        
        let prompt = """
        \(promptTitle)
        
        \(chapterTitle) \(chapter.title)
        \(chapterContent) \(contentToUse)
        
        \(requirements)
        \(requirement1)
        \(requirement2)
        
        \(format)
        \(language)
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
        
        // Construct the API request URL
        guard let url = URL(string: "\(apiEndpoint)/chat/completions") else {
            DebugLogger.error("AISummaryService: 无效的API端点URL")
            throw AISummaryError.apiError("Invalid API endpoint URL")
        }
        
        // Prepare the request body
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        
        DebugLogger.info("AISummaryService: 准备API请求体")
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            DebugLogger.error("AISummaryService: 请求体序列化失败")
            throw AISummaryError.apiError("Failed to serialize request body")
        }
        
        // Create the URL request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 60.0
        
        DebugLogger.info("AISummaryService: 发送API请求...")
        
        // Make the API call
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DebugLogger.error("AISummaryService: 响应类型无效")
                throw AISummaryError.networkError
            }
            
            DebugLogger.info("AISummaryService: HTTP状态码 = \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                DebugLogger.error("AISummaryService: API返回错误 - \(errorMessage)")
                throw AISummaryError.apiError("API returned status code \(httpResponse.statusCode): \(errorMessage)")
            }
            
            // Parse the response
            guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                DebugLogger.error("AISummaryService: 响应解析失败")
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
                DebugLogger.error("AISummaryService: 原始响应 = \(responseString)")
                throw AISummaryError.parseError
            }
            
            DebugLogger.success("AISummaryService: API请求成功")
            DebugLogger.info("AISummaryService: === AI响应 (Response) 开始 ===")
            DebugLogger.info("\n\(content)")
            DebugLogger.info("AISummaryService: === AI响应 (Response) 结束 ===")
            DebugLogger.info("AISummaryService: 响应内容长度 = \(content.count) 字符")
            DebugLogger.success("AISummaryService: ===== AI API调用完成 =====")
            
            return content
            
        } catch let error as AISummaryError {
            throw error
        } catch {
            DebugLogger.error("AISummaryService: 网络请求失败 - \(error.localizedDescription)")
            throw AISummaryError.networkError
        }
    }
    
    private func generateLocalizedMockResponse() -> String {
        // Get current language from user's locale
        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        
        switch currentLanguage {
        case "zh":
            return """
            这是一本关于个人成长和自我发现的精彩作品。作者通过生动的故事情节，展现了主人公在人生旅途中的种种经历和感悟。书中深入探讨了人性的复杂性、成长的必要性以及面对挑战时的勇气与智慧。
            
            通过阅读这本书，读者可以获得关于人生意义、价值观塑造以及如何在困境中保持希望的深刻启发。作者的文笔优美，情节引人入胜，既有哲理思考又有情感共鸣，是一本值得反复品读的佳作。
            
            • 探索个人成长的心路历程
            • 面对人生挑战的智慧与勇气
            • 价值观的形成与人生意义的思考
            • 在困境中保持希望与坚持的重要性
            • 人际关系与自我认知的平衡
            """
            
        case "ja":
            return """
            これは個人の成長と自己発見に関する素晴らしい作品です。著者は生き生きとした物語を通じて、主人公の人生における様々な経験と気づきを描いています。本書は人間性の複雑さ、成長の必要性、そして困難に直面する際の勇気と知恵を深く探求しています。
            
            本書を読むことで、読者は人生の意味、価値観の形成、そして困難な状況で希望を持ち続ける方法について深い洞察を得ることができます。著者の文章は美しく、物語は魅力的で、哲学的思考と感情的共鳴の両方を備えた、何度も読み返す価値のある名作です。
            
            • 個人の成長の道のりを探求
            • 人生の課題に対する知恵と勇気
            • 価値観の形成と人生の意味の考察
            • 困難な状況で希望と忍耐を保つ重要性
            • 人間関係と自己認識のバランス
            """
            
        case "ko":
            return """
            이것은 개인의 성장과 자기 발견에 관한 훌륭한 작품입니다. 저자는 생생한 스토리를 통해 주인공이 인생 여정에서 겪는 다양한 경험과 깨달음을 보여줍니다. 책은 인간성의 복잡성, 성장의 필요성, 그리고 도전에 직면했을 때의 용기와 지혜를 깊이 탐구합니다.
            
            이 책을 읽으면서 독자는 인생의 의미, 가치관 형성, 그리고 역경 속에서 희망을 유지하는 방법에 대한 깊은 통찰을 얻을 수 있습니다. 저자의 문체는 아름답고 줄거리는 매력적이며, 철학적 사고와 감정적 공명을 모두 갖춘 반복해서 읽을 가치가 있는 걸작입니다.
            
            • 개인 성장의 여정 탐구
            • 인생의 도전에 대한 지혜와 용기
            • 가치관 형성과 인생의 의미에 대한 고찰
            • 역경 속에서 희망과 인내를 유지하는 중요성
            • 인간관계와 자기 인식의 균형
            """
            
        default: // English
            return """
            This is an excellent work about personal growth and self-discovery. Through vivid storytelling, the author presents the protagonist's various experiences and insights throughout their life journey. The book deeply explores the complexity of human nature, the necessity of growth, and the courage and wisdom needed when facing challenges.
            
            By reading this book, readers can gain profound insights into the meaning of life, the formation of values, and how to maintain hope in difficult circumstances. The author's writing is beautiful, the plot is engaging, and it offers both philosophical reflection and emotional resonance, making it a masterpiece worth reading repeatedly.
            
            • Exploring the journey of personal growth
            • Wisdom and courage in facing life's challenges
            • Formation of values and reflection on life's meaning
            • The importance of maintaining hope and perseverance in adversity
            • Balance between interpersonal relationships and self-awareness
            """
        }
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