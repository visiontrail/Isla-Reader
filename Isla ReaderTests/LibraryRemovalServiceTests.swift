//
//  LibraryRemovalServiceTests.swift
//  LanReadTests
//

import CoreData
import Foundation
import Testing
@testable import LanRead

struct LibraryRemovalServiceTests {
    @Test
    @MainActor
    func removesBookAndRelatedDataAndFile() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let notionMappingStore = InMemoryNotionMappingStore()
        let skimmingCleaner = MockSkimmingProgressCleaner()
        let service = LibraryRemovalService(
            fileManager: .default,
            notionMappingStore: notionMappingStore,
            skimmingProgressCleaner: skimmingCleaner
        )

        let targetBookID = UUID()
        let otherBookID = UUID()
        let fileURL = try makeTemporaryBookFile()

        let libraryItem = makeLibraryItem(
            bookID: targetBookID,
            title: "Target Book",
            filePath: fileURL.path,
            context: context
        )
        seedRelatedObjects(for: targetBookID, context: context)
        seedRelatedObjects(for: otherBookID, context: context)

        notionMappingStore.setPageId("page-target", for: targetBookID)
        notionMappingStore.setPageId("page-other", for: otherBookID)

        try context.save()

        let result = try service.remove(libraryItemID: libraryItem.objectID, in: context)

        #expect(result.bookID == targetBookID)
        #expect(result.didRemoveBookFile)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        #expect(try fetchCount(Book.self, predicate: NSPredicate(format: "id == %@", targetBookID as CVarArg), context: context) == 0)
        #expect(try fetchCount(LibraryItem.self, predicate: NSPredicate(format: "book.id == %@", targetBookID as CVarArg), context: context) == 0)
        #expect(try fetchCount(ReadingProgress.self, predicate: NSPredicate(format: "book.id == %@", targetBookID as CVarArg), context: context) == 0)
        #expect(try fetchCount(Bookmark.self, predicate: NSPredicate(format: "book.id == %@", targetBookID as CVarArg), context: context) == 0)
        #expect(try fetchCount(Highlight.self, predicate: NSPredicate(format: "book.id == %@", targetBookID as CVarArg), context: context) == 0)
        #expect(try fetchCount(Annotation.self, predicate: NSPredicate(format: "book.id == %@", targetBookID as CVarArg), context: context) == 0)

        #expect(try fetchCount(SyncQueueItem.self, predicate: NSPredicate(format: "targetBookId == %@", targetBookID.uuidString), context: context) == 0)
        #expect(try fetchCount(SyncQueueItem.self, predicate: NSPredicate(format: "targetBookId == %@", otherBookID.uuidString), context: context) == 1)

        #expect(try fetchCount(BookMapping.self, predicate: NSPredicate(format: "bookID == %@", targetBookID.uuidString), context: context) == 0)
        #expect(try fetchCount(BookMapping.self, predicate: NSPredicate(format: "bookID == %@", otherBookID.uuidString), context: context) == 1)

        #expect(notionMappingStore.pageId(for: targetBookID) == nil)
        #expect(notionMappingStore.pageId(for: otherBookID) == "page-other")
        #expect(skimmingCleaner.clearedBookIDs == [targetBookID])
    }

    @Test
    @MainActor
    func removesBookEvenWhenFileIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let service = LibraryRemovalService(
            fileManager: .default,
            notionMappingStore: InMemoryNotionMappingStore(),
            skimmingProgressCleaner: MockSkimmingProgressCleaner()
        )

        let targetBookID = UUID()
        let missingFilePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
            .path

        let libraryItem = makeLibraryItem(
            bookID: targetBookID,
            title: "Missing File Book",
            filePath: missingFilePath,
            context: context
        )
        try context.save()

        let result = try service.remove(libraryItemID: libraryItem.objectID, in: context)

        #expect(result.bookID == targetBookID)
        #expect(!result.didRemoveBookFile)
        #expect(try fetchCount(Book.self, predicate: NSPredicate(format: "id == %@", targetBookID as CVarArg), context: context) == 0)
    }

    @Test
    @MainActor
    func removesLibraryItemWhenBookInverseIsBroken() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let service = LibraryRemovalService(
            fileManager: .default,
            notionMappingStore: InMemoryNotionMappingStore(),
            skimmingProgressCleaner: MockSkimmingProgressCleaner()
        )

        let targetBookID = UUID()
        let fileURL = try makeTemporaryBookFile()
        let libraryItem = makeLibraryItem(
            bookID: targetBookID,
            title: "Broken Inverse Book",
            filePath: fileURL.path,
            context: context
        )

        let book = libraryItem.book
        book.setPrimitiveValue(nil, forKey: #keyPath(Book.libraryItem))

        try context.save()

        let result = try service.remove(libraryItemID: libraryItem.objectID, in: context)

        #expect(result.bookID == targetBookID)
        #expect(try fetchCount(Book.self, predicate: NSPredicate(format: "id == %@", targetBookID as CVarArg), context: context) == 0)
        #expect(try fetchCount(LibraryItem.self, predicate: NSPredicate(format: "id == %@", libraryItem.id as CVarArg), context: context) == 0)
    }

    @Test
    @MainActor
    func removesReadingProgressWhenBookProgressInverseIsBroken() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let service = LibraryRemovalService(
            fileManager: .default,
            notionMappingStore: InMemoryNotionMappingStore(),
            skimmingProgressCleaner: MockSkimmingProgressCleaner()
        )

        let targetBookID = UUID()
        let fileURL = try makeTemporaryBookFile()
        let libraryItem = makeLibraryItem(
            bookID: targetBookID,
            title: "Broken Progress Inverse Book",
            filePath: fileURL.path,
            context: context
        )

        let book = libraryItem.book
        #expect(book.readingProgress != nil)
        book.setPrimitiveValue(nil, forKey: #keyPath(Book.readingProgress))
        try context.save()

        _ = try service.remove(libraryItemID: libraryItem.objectID, in: context)

        #expect(try fetchCount(ReadingProgress.self, context: context) == 0)
    }
}

private extension LibraryRemovalServiceTests {
    func makeTemporaryBookFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try Data("fixture".utf8).write(to: url, options: .atomic)
        return url
    }

    func makeLibraryItem(bookID: UUID, title: String, filePath: String, context: NSManagedObjectContext) -> LibraryItem {
        let now = Date()

        let book = Book(context: context)
        book.id = bookID
        book.title = title
        book.author = "Author"
        book.language = "en"
        book.filePath = filePath
        book.fileFormat = "epub"
        book.fileSize = 123
        book.checksum = UUID().uuidString
        book.totalPages = 100
        book.createdAt = now
        book.updatedAt = now

        let libraryItem = LibraryItem(context: context)
        libraryItem.id = UUID()
        libraryItem.status = .reading
        libraryItem.isFavorite = false
        libraryItem.rating = 0
        libraryItem.addedAt = now
        libraryItem.lastAccessedAt = now
        libraryItem.sortOrder = Int32(now.timeIntervalSince1970)
        libraryItem.book = book

        let progress = ReadingProgress(context: context)
        progress.id = UUID()
        progress.currentPage = 1
        progress.progressPercentage = 0.1
        progress.lastReadAt = now
        progress.totalReadingTime = 60
        progress.createdAt = now
        progress.updatedAt = now
        progress.book = book
        book.readingProgress = progress

        let bookmark = Bookmark(context: context)
        bookmark.id = UUID()
        bookmark.chapterIndex = 0
        bookmark.pageIndex = 0
        bookmark.chapterTitle = "Chapter 1"
        bookmark.createdAt = now
        bookmark.book = book

        let highlight = Highlight(context: context)
        highlight.id = UUID()
        highlight.selectedText = "highlight text"
        highlight.startPosition = "{\"chapterIndex\":0,\"pageIndex\":0}"
        highlight.endPosition = "{\"chapterIndex\":0,\"pageIndex\":0}"
        highlight.chapter = "Chapter 1"
        highlight.pageNumber = 0
        highlight.colorHex = "FFFF00"
        highlight.note = "note"
        highlight.createdAt = now
        highlight.updatedAt = now
        highlight.book = book

        let annotation = Annotation(context: context)
        annotation.id = UUID()
        annotation.content = "annotation"
        annotation.position = "{\"chapterIndex\":0,\"pageIndex\":0}"
        annotation.chapter = "Chapter 1"
        annotation.pageNumber = 0
        annotation.associatedText = "associated"
        annotation.createdAt = now
        annotation.updatedAt = now
        annotation.book = book

        return libraryItem
    }

    func seedRelatedObjects(for bookID: UUID, context: NSManagedObjectContext) {
        let queueItem = SyncQueueItem(context: context)
        queueItem.id = UUID()
        queueItem.targetBookId = bookID.uuidString
        queueItem.type = SyncQueueItemType.highlight.rawValue
        queueItem.payload = Data("{}".utf8)
        queueItem.status = SyncQueueItemStatus.pending.rawValue
        queueItem.retryCount = 0
        queueItem.createdAt = Date()

        let mapping = BookMapping(context: context)
        mapping.bookID = bookID.uuidString
        mapping.notionPageID = "page-\(bookID.uuidString)"
        mapping.updatedAt = Date()
    }

    func fetchCount<T: NSManagedObject>(
        _ type: T.Type,
        predicate: NSPredicate? = nil,
        context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: type))
        request.predicate = predicate
        return try context.count(for: request)
    }
}

private final class InMemoryNotionMappingStore: NotionDatabaseMappingStoring {
    private var mappings: [UUID: String] = [:]

    func pageId(for bookId: UUID) -> String? {
        mappings[bookId]
    }

    func setPageId(_ pageId: String, for bookId: UUID) {
        mappings[bookId] = pageId
    }

    func removePageId(for bookId: UUID) {
        mappings.removeValue(forKey: bookId)
    }

    @discardableResult
    func clearAllMappings() -> Int {
        let count = mappings.count
        mappings.removeAll()
        return count
    }
}

private final class MockSkimmingProgressCleaner: SkimmingProgressCleaning {
    private(set) var clearedBookIDs: [UUID] = []

    func clearStoredProgress(for bookIds: [UUID]) {
        clearedBookIDs.append(contentsOf: bookIds)
    }
}
