//
//  NotionSyncEngineObservationTests.swift
//  LanReadTests
//

import CoreData
import Foundation
import Testing
@testable import LanRead

struct NotionSyncEngineObservationTests {
    @Test
    @MainActor
    func deletingSingleHighlightKeepsBookMetadataAvailable() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let engine = makeEngine(container: persistence.container)

        let fixture = makeBookFixture(context: context, title: "Keep Book")
        try context.save()

        context.delete(fixture.highlight)

        let touchedBooks = engine.collectTouchedBookInfo(in: context)

        #expect(touchedBooks.count == 1)
        #expect(touchedBooks[fixture.book.id.uuidString] == NotionSyncBookMetadata(
            id: fixture.book.id.uuidString,
            title: "Keep Book",
            author: "Author",
            statusRaw: ReadingStatus.reading.rawValue,
            progressPercentage: 0.42
        ))
    }

    @Test
    @MainActor
    func deletingBookSkipsDeletedHighlightSyncMetadata() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let engine = makeEngine(container: persistence.container)

        let fixture = makeBookFixture(context: context, title: "Remove Book")
        try context.save()

        context.delete(fixture.highlight)
        context.delete(fixture.libraryItem)
        context.delete(fixture.book)

        let touchedBooks = engine.collectTouchedBookInfo(in: context)

        #expect(touchedBooks.isEmpty)
    }
}

private extension NotionSyncEngineObservationTests {
    struct BookFixture {
        let book: Book
        let libraryItem: LibraryItem
        let highlight: Highlight
    }

    func makeEngine(container: NSPersistentContainer) -> NotionSyncEngine {
        NotionSyncEngine(
            container: container,
            queueStore: CoreDataSyncQueueStore(container: container),
            networkMonitor: NetworkMonitor(),
            notificationCenter: NotificationCenter()
        )
    }

    func makeBookFixture(context: NSManagedObjectContext, title: String) -> BookFixture {
        let now = Date()

        let book = Book(context: context)
        book.id = UUID()
        book.title = title
        book.author = "Author"
        book.language = "en"
        book.filePath = UUID().uuidString + ".epub"
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
        libraryItem.sortOrder = 1
        libraryItem.book = book

        let readingProgress = ReadingProgress(context: context)
        readingProgress.id = UUID()
        readingProgress.currentPage = 1
        readingProgress.currentChapter = "Chapter 1"
        readingProgress.currentPosition = "{\"chapterIndex\":0,\"pageIndex\":0}"
        readingProgress.progressPercentage = 0.42
        readingProgress.lastReadAt = now
        readingProgress.totalReadingTime = 60
        readingProgress.createdAt = now
        readingProgress.updatedAt = now
        readingProgress.book = book

        let highlight = Highlight(context: context)
        highlight.id = UUID()
        highlight.selectedText = "Highlight"
        highlight.startPosition = "{\"chapterIndex\":0,\"pageIndex\":0}"
        highlight.endPosition = "{\"chapterIndex\":0,\"pageIndex\":1}"
        highlight.chapter = "Chapter 1"
        highlight.pageNumber = 0
        highlight.colorHex = "FFFF00"
        highlight.note = "Note"
        highlight.createdAt = now
        highlight.updatedAt = now
        highlight.book = book

        return BookFixture(book: book, libraryItem: libraryItem, highlight: highlight)
    }
}
