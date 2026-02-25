//
//  LibraryRemovalService.swift
//  LanRead
//
//  Created by AI Assistant on 2026/2/25.
//

import CoreData
import Foundation

struct LibraryRemovalResult {
    let bookID: UUID
    let bookTitle: String
    let removedFileBytes: Int64
    let didRemoveBookFile: Bool
}

enum LibraryRemovalError: LocalizedError {
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return NSLocalizedString("library.remove.failure.not_found", comment: "")
        }
    }
}

protocol SkimmingProgressCleaning {
    func clearStoredProgress(for bookIds: [UUID])
}

extension SkimmingModeService: SkimmingProgressCleaning {}

final class LibraryRemovalService {
    static let shared = LibraryRemovalService()

    private let fileManager: FileManager
    private let notionMappingStore: NotionDatabaseMappingStoring
    private let skimmingProgressCleaner: SkimmingProgressCleaning

    init(
        fileManager: FileManager = .default,
        notionMappingStore: NotionDatabaseMappingStoring = NotionDatabaseMappingStore.shared,
        skimmingProgressCleaner: SkimmingProgressCleaning = SkimmingModeService.shared
    ) {
        self.fileManager = fileManager
        self.notionMappingStore = notionMappingStore
        self.skimmingProgressCleaner = skimmingProgressCleaner
    }

    func remove(libraryItemID: NSManagedObjectID, in context: NSManagedObjectContext) throws -> LibraryRemovalResult {
        let plan = try makeDeletionPlan(libraryItemID: libraryItemID, in: context)

        notionMappingStore.removePageId(for: plan.bookID)
        skimmingProgressCleaner.clearStoredProgress(for: [plan.bookID])

        let fileCleanup = removeBookFileIfNeeded(url: plan.bookFileURL)

        DebugLogger.success(
            "LibraryRemovalService: 已移除书籍 \(plan.bookTitle), 文件删除=\(fileCleanup.didRemove), 释放=\(fileCleanup.freedBytes) bytes"
        )

        return LibraryRemovalResult(
            bookID: plan.bookID,
            bookTitle: plan.bookTitle,
            removedFileBytes: fileCleanup.freedBytes,
            didRemoveBookFile: fileCleanup.didRemove
        )
    }

    private func makeDeletionPlan(libraryItemID: NSManagedObjectID, in context: NSManagedObjectContext) throws -> DeletionPlan {
        var operationResult: Result<DeletionPlan, Error>!

        context.performAndWait {
            do {
                guard let libraryItem = try context.existingObject(with: libraryItemID) as? LibraryItem else {
                    throw LibraryRemovalError.itemNotFound
                }

                let book = libraryItem.book
                let bookID = book.id
                let bookTitle = book.displayTitle
                let fileURL = BookFileLocator.resolveFileURL(from: book.filePath, fileManager: fileManager)?.url

                try removeNotionSyncArtifacts(for: bookID, in: context)
                try removeBookScopedArtifacts(for: book, in: context)

                // 显式删除书架条目，避免依赖反向关系级联导致残留空壳 LibraryItem。
                context.delete(libraryItem)
                context.delete(book)
                try context.save()

                operationResult = .success(
                    DeletionPlan(
                        bookID: bookID,
                        bookTitle: bookTitle,
                        bookFileURL: fileURL
                    )
                )
            } catch {
                context.rollback()
                operationResult = .failure(error)
            }
        }

        return try operationResult.get()
    }

    private func removeNotionSyncArtifacts(for bookID: UUID, in context: NSManagedObjectContext) throws {
        let bookIDString = bookID.uuidString

        let queueRequest = SyncQueueItem.fetchRequest()
        queueRequest.predicate = NSPredicate(format: "targetBookId == %@", bookIDString)
        let queueItems = try context.fetch(queueRequest)
        queueItems.forEach(context.delete)

        let legacyMappingRequest = BookMapping.fetchRequest()
        legacyMappingRequest.predicate = NSPredicate(format: "bookID == %@", bookIDString)
        let legacyMappings = try context.fetch(legacyMappingRequest)
        legacyMappings.forEach(context.delete)
    }

    private func removeBookScopedArtifacts(for book: Book, in context: NSManagedObjectContext) throws {
        let bookPredicate = NSPredicate(format: "book == %@", book)

        let progressRequest = ReadingProgress.fetchRequest()
        progressRequest.predicate = bookPredicate
        let progresses = try context.fetch(progressRequest)
        progresses.forEach(context.delete)

        let bookmarkRequest = Bookmark.fetchRequest()
        bookmarkRequest.predicate = bookPredicate
        let bookmarks = try context.fetch(bookmarkRequest)
        bookmarks.forEach(context.delete)

        let highlightRequest = Highlight.fetchRequest()
        highlightRequest.predicate = bookPredicate
        let highlights = try context.fetch(highlightRequest)
        highlights.forEach(context.delete)

        let annotationRequest = Annotation.fetchRequest()
        annotationRequest.predicate = bookPredicate
        let annotations = try context.fetch(annotationRequest)
        annotations.forEach(context.delete)
    }

    private func removeBookFileIfNeeded(url: URL?) -> (freedBytes: Int64, didRemove: Bool) {
        guard let url else {
            return (0, false)
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return (0, false)
        }

        let fileBytes = fileSize(at: url)

        do {
            try fileManager.removeItem(at: url)
            return (fileBytes, true)
        } catch {
            DebugLogger.warning("LibraryRemovalService: 删除书籍文件失败 \(url.lastPathComponent) - \(error.localizedDescription)")
            return (0, false)
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
            if let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                return Int64(size)
            }
        }

        return 0
    }
}

private struct DeletionPlan {
    let bookID: UUID
    let bookTitle: String
    let bookFileURL: URL?
}
