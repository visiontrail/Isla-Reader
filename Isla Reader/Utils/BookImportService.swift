//
//  BookImportService.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/1/20.
//

import Foundation
import CoreData
import CryptoKit

class BookImportService: ObservableObject {
    static let shared = BookImportService()
    
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    @Published var importError: String?
    
    private init() {}
    
    func importBook(from url: URL, context: NSManagedObjectContext) async throws -> Book {
        DebugLogger.info("BookImportService: 开始导入书籍")
        DebugLogger.info("BookImportService: 文件URL: \(url.absoluteString)")
        
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
            importError = nil
        }
        
        defer {
            Task { @MainActor in
                isImporting = false
                importProgress = 0.0
            }
        }
        
        do {
            // 1. 检查文件格式
            DebugLogger.info("BookImportService: 步骤1 - 检查文件格式")
            await updateProgress(0.1)
            let fileExtension = url.pathExtension.lowercased()
            DebugLogger.info("BookImportService: 文件扩展名: \(fileExtension)")
            guard fileExtension == "epub" else {
                DebugLogger.error("BookImportService: 不支持的文件格式: \(fileExtension)")
                throw BookImportError.unsupportedFormat
            }
            
            // 2. 计算文件校验和
            DebugLogger.info("BookImportService: 步骤2 - 计算文件校验和")
            await updateProgress(0.2)
            let fileData = try Data(contentsOf: url)
            DebugLogger.info("BookImportService: 文件大小: \(fileData.count) bytes")
            let checksum = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
            DebugLogger.info("BookImportService: 文件校验和: \(checksum)")
            
            // 3. 检查是否已导入
            DebugLogger.info("BookImportService: 步骤3 - 检查是否已导入")
            await updateProgress(0.3)
            if let existingBook = try findExistingBook(with: checksum, context: context) {
                DebugLogger.warning("BookImportService: 书籍已存在: \(existingBook.displayTitle)")
                throw BookImportError.bookAlreadyExists(existingBook.displayTitle)
            }
            DebugLogger.info("BookImportService: 书籍未重复，可以导入")
            
            // 4. 解析ePub文件
            DebugLogger.info("BookImportService: 步骤4 - 解析ePub文件")
            await updateProgress(0.4)
            let metadata = try EPubParser.parseEPub(from: url)
            DebugLogger.info("BookImportService: 解析成功 - 标题: \(metadata.title), 作者: \(metadata.author ?? "未知")")
            DebugLogger.info("BookImportService: 章节数量: \(metadata.chapters.count), 总页数: \(metadata.totalPages)")
            
            // 5. 创建应用文档目录中的存储路径
            DebugLogger.info("BookImportService: 步骤5 - 创建存储路径")
            await updateProgress(0.6)
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let booksDirectory = documentsPath.appendingPathComponent("Books")
            DebugLogger.info("BookImportService: 书籍目录: \(booksDirectory.path)")
            try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
            
            let bookFileName = "\(UUID().uuidString).epub"
            let destinationURL = booksDirectory.appendingPathComponent(bookFileName)
            DebugLogger.info("BookImportService: 目标文件路径: \(destinationURL.path)")
            try FileManager.default.copyItem(at: url, to: destinationURL)
            DebugLogger.success("BookImportService: 文件复制成功")
            
            // 6. 创建Book实体
            DebugLogger.info("BookImportService: 步骤6 - 创建Book实体")
            await updateProgress(0.8)
            let book = Book(context: context)
            book.id = UUID()
            book.title = metadata.title
            book.author = metadata.author
            book.language = metadata.language
            book.coverImageData = metadata.coverImageData
            book.filePath = destinationURL.path
            book.fileFormat = "epub"
            book.fileSize = Int64(fileData.count)
            book.checksum = checksum
            book.totalPages = Int32(metadata.totalPages)
            book.createdAt = Date()
            book.updatedAt = Date()
            DebugLogger.info("BookImportService: Book实体创建完成")
            
            // 7. 创建LibraryItem
            DebugLogger.info("BookImportService: 步骤7 - 创建LibraryItem")
            let libraryItem = LibraryItem(context: context)
            libraryItem.id = UUID()
            libraryItem.book = book
            libraryItem.status = .wantToRead
            libraryItem.addedAt = Date()
            libraryItem.lastAccessedAt = Date()
            // 设置必需字段的默认值
            libraryItem.isFavorite = false
            libraryItem.rating = 0
            libraryItem.sortOrder = Int32(Date().timeIntervalSince1970) // 使用时间戳作为排序顺序
            DebugLogger.info("BookImportService: LibraryItem创建完成")
            
            // 8. 创建ReadingProgress
            DebugLogger.info("BookImportService: 步骤8 - 创建ReadingProgress")
            let readingProgress = ReadingProgress(context: context)
            readingProgress.id = UUID()
            readingProgress.book = book
            readingProgress.currentPage = 1
            readingProgress.progressPercentage = 0.0
            readingProgress.lastReadAt = Date()
            readingProgress.totalReadingTime = 0
            readingProgress.createdAt = Date()
            readingProgress.updatedAt = Date()
            // 显式设置反向关系
            book.readingProgress = readingProgress
            DebugLogger.info("BookImportService: ReadingProgress创建完成，进度=\(readingProgress.progressPercentage)")
            
            // 9. 保存章节信息到metadata
            DebugLogger.info("BookImportService: 步骤9 - 保存章节信息")
            let chaptersData = try JSONEncoder().encode(metadata.chapters.map { chapter in
                [
                    "title": chapter.title,
                    "content": chapter.content,
                    "order": String(chapter.order)
                ]
            })
            book.metadata = String(data: chaptersData, encoding: .utf8)
            DebugLogger.info("BookImportService: 章节信息保存完成")
            
            // 10. 保存到Core Data
            DebugLogger.info("BookImportService: 步骤10 - 保存到Core Data")
            await updateProgress(0.9)
            try context.save()
            DebugLogger.success("BookImportService: Core Data保存成功")
            
            await updateProgress(1.0)
            DebugLogger.success("BookImportService: 书籍导入完成: \(book.displayTitle)")
            return book
            
        } catch {
            DebugLogger.error("BookImportService: 导入失败: \(error.localizedDescription)")
            DebugLogger.error("BookImportService: 错误详情: \(error)")
            await MainActor.run {
                importError = error.localizedDescription
            }
            throw error
        }
    }
    
    private func findExistingBook(with checksum: String, context: NSManagedObjectContext) throws -> Book? {
        let request: NSFetchRequest<Book> = Book.fetchRequest()
        request.predicate = NSPredicate(format: "checksum == %@", checksum)
        request.fetchLimit = 1
        
        let results = try context.fetch(request)
        return results.first
    }
    
    @MainActor
    private func updateProgress(_ progress: Double) {
        importProgress = progress
    }
}

enum BookImportError: Error {
    case unsupportedFormat
    case bookAlreadyExists(String)
    case fileNotAccessible
    case parseError(String)
    case saveError(String)
    
    var localizedDescription: String {
        switch self {
        case .unsupportedFormat:
            return "不支持的文件格式，请选择ePub文件"
        case .bookAlreadyExists(let title):
            return "书籍《\(title)》已存在于书架中"
        case .fileNotAccessible:
            return "无法访问选择的文件"
        case .parseError(let message):
            return "解析文件时出错：\(message)"
        case .saveError(let message):
            return "保存书籍时出错：\(message)"
        }
    }
}