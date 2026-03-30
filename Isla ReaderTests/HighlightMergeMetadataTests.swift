import CoreData
import Foundation
import Testing
@testable import LanRead

struct HighlightMergeMetadataTests {
    @Test
    @MainActor
    func detectsMergedFlagFromStartPosition() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let book = makeBook(context: context)

        let highlight = Highlight(context: context)
        highlight.id = UUID()
        highlight.selectedText = "Merged text"
        highlight.startPosition = #"{"chapterIndex":1,"pageIndex":3,"offset":12,"mergedFromHighlights":true}"#
        highlight.endPosition = #"{"chapterIndex":1,"pageIndex":3,"offset":20}"#
        highlight.pageNumber = 3
        highlight.colorHex = "FFFF00"
        highlight.createdAt = Date()
        highlight.updatedAt = Date()
        highlight.book = book

        #expect(highlight.isMergedFromHighlights)
        #expect(highlight.readingLocation?.chapterIndex == 1)
        #expect(highlight.readingLocation?.pageIndex == 3)
        #expect(highlight.readingLocation?.textOffset == 12)
    }

    @Test
    func marksExistingAnchorAsMerged() throws {
        let marked = Highlight.markStartPositionAsMerged(
            #"{"chapterIndex":4,"pageIndex":9,"offset":18}"#
        )

        let payload = try decodeJSON(marked)
        #expect(intValue(payload["chapterIndex"]) == 4)
        #expect(intValue(payload["pageIndex"]) == 9)
        #expect(intValue(payload["offset"]) == 18)
        #expect(boolValue(payload["mergedFromHighlights"]) == true)
    }

    @Test
    func marksFallbackAnchorAsMergedWhenInputIsInvalidJSON() throws {
        let marked = Highlight.markStartPositionAsMerged(
            "invalid-start-position",
            fallbackChapterIndex: 2,
            fallbackPageIndex: 7,
            fallbackOffset: 33
        )

        let payload = try decodeJSON(marked)
        #expect(intValue(payload["chapterIndex"]) == 2)
        #expect(intValue(payload["pageIndex"]) == 7)
        #expect(intValue(payload["offset"]) == 33)
        #expect(boolValue(payload["mergedFromHighlights"]) == true)
    }
}

private extension HighlightMergeMetadataTests {
    func makeBook(context: NSManagedObjectContext) -> Book {
        let book = Book(context: context)
        book.id = UUID()
        book.title = "Merge Flag"
        book.author = "LanRead"
        book.language = "en"
        book.filePath = UUID().uuidString + ".epub"
        book.fileFormat = "epub"
        book.fileSize = 1
        book.checksum = UUID().uuidString
        book.totalPages = 10
        book.createdAt = Date()
        book.updatedAt = Date()
        return book
    }

    func decodeJSON(_ text: String) throws -> [String: Any] {
        let data = try #require(text.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
}
