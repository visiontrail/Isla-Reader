//
//  DataBackupService.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/2/18.
//

import Foundation
import CoreData

final class DataBackupService {
    static let shared = DataBackupService()
    
    private init() {}
    
    func exportReadingData(context: NSManagedObjectContext) async throws -> URL {
        try await context.perform { [self] in
            DebugLogger.info("DataBackupService: 开始导出阅读数据")
            
            let request: NSFetchRequest<Book> = Book.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Book.createdAt, ascending: true)]
            
            let books = try context.fetch(request)
            DebugLogger.info("DataBackupService: 读取到 \(books.count) 本书籍的阅读数据")
            
            let bookPayloads = books.map { book in
                BookReadingData(
                    checksum: book.checksum,
                    title: book.title,
                    author: book.author,
                    readingProgress: book.readingProgress.map { ReadingProgressSnapshot(from: $0) },
                    libraryItem: book.libraryItem.map { LibraryItemSnapshot(from: $0) },
                    bookmarks: (book.bookmarks as? Set<Bookmark> ?? [])
                        .sorted { $0.createdAt < $1.createdAt }
                        .map { BookmarkSnapshot(from: $0) }
                )
            }
            
            let payload = ReadingDataBackup(
                version: 1,
                exportedAt: Date(),
                books: bookPayloads
            )
            
            let url = try self.writeJSON(payload, prefix: "ReadingData")
            DebugLogger.success("DataBackupService: 阅读数据导出完成 - \(url.lastPathComponent)")
            return url
        }
    }
    
    func exportNotesAndHighlights(context: NSManagedObjectContext) async throws -> URL {
        try await context.perform { [self] in
            DebugLogger.info("DataBackupService: 开始导出笔记与高亮")
            
            let highlightRequest: NSFetchRequest<Highlight> = Highlight.fetchRequest()
            highlightRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Highlight.updatedAt, ascending: false)]
            let highlights = try context.fetch(highlightRequest)
            DebugLogger.info("DataBackupService: 读取到 \(highlights.count) 条高亮")
            
            let annotationRequest: NSFetchRequest<Annotation> = Annotation.fetchRequest()
            annotationRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Annotation.updatedAt, ascending: false)]
            let annotations = try context.fetch(annotationRequest)
            DebugLogger.info("DataBackupService: 读取到 \(annotations.count) 条批注")
            
            let highlightPayloads = highlights.compactMap { highlight -> HighlightSnapshot? in
                guard let book = highlight.book as Book? else { return nil }
                return HighlightSnapshot(from: highlight, book: book)
            }
            
            let annotationPayloads = annotations.compactMap { annotation -> AnnotationSnapshot? in
                guard let book = annotation.book as Book? else { return nil }
                return AnnotationSnapshot(from: annotation, book: book)
            }
            
            let payload = NotesBackup(
                version: 1,
                exportedAt: Date(),
                highlights: highlightPayloads,
                annotations: annotationPayloads
            )
            
            let url = try self.writeJSON(payload, prefix: "NotesHighlights")
            DebugLogger.success("DataBackupService: 笔记与高亮导出完成 - \(url.lastPathComponent)")
            return url
        }
    }
    
    func importReadingData(from url: URL, context: NSManagedObjectContext) async throws -> ReadingDataImportResult {
        DebugLogger.info("DataBackupService: 开始导入阅读数据 - \(url.lastPathComponent)")
        let data = try Data(contentsOf: url)
        let backup = try decoder.decode(ReadingDataBackup.self, from: data)
        
        return try await context.perform {
            let fetch: NSFetchRequest<Book> = Book.fetchRequest()
            let books = try context.fetch(fetch)
            let bookMap = Dictionary(uniqueKeysWithValues: books.map { ($0.checksum, $0) })
            
            var matchedBooks = 0
            var updatedProgress = 0
            var updatedBookmarks = 0
            
            for item in backup.books {
                guard let book = bookMap[item.checksum] else {
                    DebugLogger.warning("DataBackupService: 未找到匹配的书籍，checksum=\(item.checksum)")
                    continue
                }
                
                matchedBooks += 1
                
                if let snapshot = item.readingProgress {
                    let progress: ReadingProgress
                    if let existing = book.readingProgress {
                        progress = existing
                    } else {
                        progress = ReadingProgress(context: context)
                        book.readingProgress = progress
                    }
                    
                    progress.id = snapshot.id
                    progress.createdAt = snapshot.createdAt
                    progress.currentPage = snapshot.currentPage
                    progress.currentChapter = snapshot.currentChapter
                    progress.currentPosition = snapshot.currentPosition
                    progress.progressPercentage = snapshot.progressPercentage
                    progress.lastReadAt = snapshot.lastReadAt
                    progress.totalReadingTime = snapshot.totalReadingTime
                    progress.updatedAt = snapshot.updatedAt
                    progress.book = book
                    updatedProgress += 1
                }
                
                if let librarySnapshot = item.libraryItem {
                    let libraryItem: LibraryItem
                    if let existing = book.libraryItem {
                        libraryItem = existing
                    } else {
                        libraryItem = LibraryItem(context: context)
                        libraryItem.id = UUID()
                        libraryItem.book = book
                        book.libraryItem = libraryItem
                    }
                    libraryItem.statusRaw = librarySnapshot.statusRaw
                    libraryItem.isFavorite = librarySnapshot.isFavorite
                    libraryItem.rating = librarySnapshot.rating
                    libraryItem.tags = librarySnapshot.tags
                    libraryItem.addedAt = librarySnapshot.addedAt
                    libraryItem.lastAccessedAt = librarySnapshot.lastAccessedAt
                    libraryItem.sortOrder = librarySnapshot.sortOrder
                }
                
                if let existingBookmarks = book.bookmarks as? Set<Bookmark> {
                    existingBookmarks.forEach { context.delete($0) }
                }
                
                for bookmarkSnapshot in item.bookmarks {
                    let bookmark = Bookmark(context: context)
                    bookmark.id = bookmarkSnapshot.id
                    bookmark.chapterIndex = bookmarkSnapshot.chapterIndex
                    bookmark.pageIndex = bookmarkSnapshot.pageIndex
                    bookmark.chapterTitle = bookmarkSnapshot.chapterTitle
                    bookmark.createdAt = bookmarkSnapshot.createdAt
                    bookmark.book = book
                    updatedBookmarks += 1
                }
            }
            
            if context.hasChanges {
                try context.save()
            }
            
            let result = ReadingDataImportResult(
                totalBooks: backup.books.count,
                matchedBooks: matchedBooks,
                skippedBooks: backup.books.count - matchedBooks,
                updatedProgress: updatedProgress,
                updatedBookmarks: updatedBookmarks
            )
            DebugLogger.success("DataBackupService: 导入完成 - 匹配\(matchedBooks)/\(backup.books.count)本书")
            return result
        }
    }
    
    // MARK: - Helpers
    
    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
    
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    
    private func writeJSON<T: Encodable>(_ value: T, prefix: String) throws -> URL {
        let data = try encoder.encode(value)
        let fileName = "LanRead-\(prefix)-\(Self.timestampString()).json"
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }
    
    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

struct ReadingDataImportResult {
    let totalBooks: Int
    let matchedBooks: Int
    let skippedBooks: Int
    let updatedProgress: Int
    let updatedBookmarks: Int
}

// MARK: - Export payloads

private struct ReadingDataBackup: Codable {
    let version: Int
    let exportedAt: Date
    let books: [BookReadingData]
}

private struct BookReadingData: Codable {
    let checksum: String
    let title: String
    let author: String?
    let readingProgress: ReadingProgressSnapshot?
    let libraryItem: LibraryItemSnapshot?
    let bookmarks: [BookmarkSnapshot]
}

private struct ReadingProgressSnapshot: Codable {
    let id: UUID
    let currentPage: Int32
    let currentChapter: String?
    let currentPosition: String?
    let progressPercentage: Double
    let lastReadAt: Date
    let totalReadingTime: Int64
    let createdAt: Date
    let updatedAt: Date
    
    init(from progress: ReadingProgress) {
        id = progress.id
        currentPage = progress.currentPage
        currentChapter = progress.currentChapter
        currentPosition = progress.currentPosition
        progressPercentage = progress.progressPercentage
        lastReadAt = progress.lastReadAt
        totalReadingTime = progress.totalReadingTime
        createdAt = progress.createdAt
        updatedAt = progress.updatedAt
    }
}

private struct LibraryItemSnapshot: Codable {
    let statusRaw: String
    let isFavorite: Bool
    let rating: Int16
    let tags: String?
    let addedAt: Date
    let lastAccessedAt: Date?
    let sortOrder: Int32
    
    init(from item: LibraryItem) {
        statusRaw = item.statusRaw
        isFavorite = item.isFavorite
        rating = item.rating
        tags = item.tags
        addedAt = item.addedAt
        lastAccessedAt = item.lastAccessedAt
        sortOrder = item.sortOrder
    }
}

private struct BookmarkSnapshot: Codable {
    let id: UUID
    let chapterIndex: Int32
    let pageIndex: Int32
    let chapterTitle: String?
    let createdAt: Date
    
    init(from bookmark: Bookmark) {
        id = bookmark.id
        chapterIndex = bookmark.chapterIndex
        pageIndex = bookmark.pageIndex
        chapterTitle = bookmark.chapterTitle
        createdAt = bookmark.createdAt
    }
}

private struct NotesBackup: Codable {
    let version: Int
    let exportedAt: Date
    let highlights: [HighlightSnapshot]
    let annotations: [AnnotationSnapshot]
}

private struct HighlightSnapshot: Codable {
    let id: UUID
    let bookChecksum: String
    let bookTitle: String
    let selectedText: String
    let startPosition: String
    let endPosition: String
    let chapter: String?
    let pageNumber: Int32
    let colorHex: String
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    
    init?(from highlight: Highlight, book: Book) {
        guard !book.checksum.isEmpty else { return nil }
        id = highlight.id
        bookChecksum = book.checksum
        bookTitle = book.title
        selectedText = highlight.selectedText
        startPosition = highlight.startPosition
        endPosition = highlight.endPosition
        chapter = highlight.chapter
        pageNumber = highlight.pageNumber
        colorHex = highlight.colorHex
        note = highlight.note
        createdAt = highlight.createdAt
        updatedAt = highlight.updatedAt
    }
}

private struct AnnotationSnapshot: Codable {
    let id: UUID
    let bookChecksum: String
    let bookTitle: String
    let content: String
    let position: String
    let chapter: String?
    let pageNumber: Int32
    let associatedText: String?
    let createdAt: Date
    let updatedAt: Date
    
    init?(from annotation: Annotation, book: Book) {
        guard !book.checksum.isEmpty else { return nil }
        id = annotation.id
        bookChecksum = book.checksum
        bookTitle = book.title
        content = annotation.content
        position = annotation.position
        chapter = annotation.chapter
        pageNumber = annotation.pageNumber
        associatedText = annotation.associatedText
        createdAt = annotation.createdAt
        updatedAt = annotation.updatedAt
    }
}
