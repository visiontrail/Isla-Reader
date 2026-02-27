//
//  NotionBookSyncerTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct NotionBookSyncerTests {
    @Test
    func syncingSameBookFiveTimesCreatesSinglePage() async throws {
        let mockClient = MockNotionBookSyncAPI(
            createdPageID: "page_created_1",
            createDelayNanoseconds: 200_000_000
        )
        let mappingStore = InMemoryBookMappingStore()
        let syncer = NotionBookSyncer(
            notionClient: mockClient,
            mappingStore: mappingStore,
            databaseIDProvider: { "db_test_1" }
        )

        let book = BookInfo(id: "book_1", title: "Atomic Habits", author: "James Clear")

        let pageIDs = try await withThrowingTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await syncer.sync(book: book)
                }
            }

            var results: [String] = []
            for try await pageID in group {
                results.append(pageID)
            }
            return results
        }

        #expect(Set(pageIDs) == ["page_created_1"])
        #expect(try mappingStore.notionPageID(for: "book_1") == "page_created_1")

        let callStats = await mockClient.callStats()
        #expect(callStats.updateDatabaseCount == 1)
        #expect(callStats.createCount == 1)
    }

    @Test
    func syncUsesLocalMappingCacheWithoutCreatingPage() async throws {
        let mockClient = MockNotionBookSyncAPI(
            createdPageID: "page_should_not_be_created"
        )
        let mappingStore = InMemoryBookMappingStore()
        let syncer = NotionBookSyncer(
            notionClient: mockClient,
            mappingStore: mappingStore,
            databaseIDProvider: { "db_test_2" }
        )

        let book = BookInfo(id: "book_2", title: "Deep Work", author: "Cal Newport")
        try mappingStore.saveMapping(bookID: "book_2", notionPageID: "page_existing_1")

        let first = try await syncer.sync(book: book)
        let second = try await syncer.sync(book: book)

        #expect(first == "page_existing_1")
        #expect(second == "page_existing_1")
        #expect(try mappingStore.notionPageID(for: "book_2") == "page_existing_1")

        let callStats = await mockClient.callStats()
        #expect(callStats.updateDatabaseCount == 1)
        #expect(callStats.createCount == 0)
    }

    @Test
    func createPageInitialChildrenOnlyContainNotesSection() async throws {
        let mockClient = MockNotionBookSyncAPI(
            createdPageID: "page_created_2"
        )
        let mappingStore = InMemoryBookMappingStore()
        let syncer = NotionBookSyncer(
            notionClient: mockClient,
            mappingStore: mappingStore,
            databaseIDProvider: { "db_test_3" }
        )

        let book = BookInfo(
            id: "book_3",
            title: "The Pragmatic Programmer",
            author: "Andrew Hunt",
            readingStatusRaw: ReadingStatus.reading.rawValue,
            readingProgressPercentage: 0.42
        )
        _ = try await syncer.sync(book: book)

        let createdChildren = await mockClient.lastCreatedChildren()
        #expect(createdChildren.count == 2)
        #expect(createdChildren[0]["type"] == .string("heading_1"))
        #expect(createdChildren[1]["type"] == .string("divider"))

        let heading = try #require(createdChildren[0]["heading_1"]?.objectValue)
        let richText = try #require(heading["rich_text"]?.arrayValue)
        let first = try #require(richText.first?.objectValue)
        let text = try #require(first["text"]?.objectValue)
        let content = try #require(text["content"]?.stringValue)
        #expect(content == "📝 Notes")

        let createdProperties = await mockClient.lastCreatedProperties()
        let progress = try #require(createdProperties[NotionLibrarySchema.readingProgressProperty]?.objectValue)
        #expect(progress["number"] == .number(0.42))

        let status = try #require(createdProperties[NotionLibrarySchema.readingStatusProperty]?.objectValue)
        let statusSelect = try #require(status["select"]?.objectValue)
        #expect(statusSelect["name"] == .string("Reading"))
        #expect(createdProperties[NotionLibrarySchema.nameProperty] != nil)
        #expect(createdProperties[NotionLibrarySchema.authorProperty] != nil)
    }
}

private final class InMemoryBookMappingStore: BookMappingStoring {
    private let queue = DispatchQueue(label: "NotionBookSyncerTests.InMemoryBookMappingStore")
    private var mappings: [String: String] = [:]

    func notionPageID(for bookID: String) throws -> String? {
        queue.sync { mappings[bookID] }
    }

    func saveMapping(bookID: String, notionPageID: String) throws {
        queue.sync {
            mappings[bookID] = notionPageID
        }
    }
}

private actor MockNotionBookSyncAPI: NotionBookSyncAPI {
    private(set) var updateDatabaseCount = 0
    private(set) var createCount = 0
    private var capturedChildren: [Block] = []
    private var capturedProperties: Object = [:]

    private let createdPageID: String
    private let createDelayNanoseconds: UInt64

    init(
        createdPageID: String,
        createDelayNanoseconds: UInt64 = 0
    ) {
        self.createdPageID = createdPageID
        self.createDelayNanoseconds = createDelayNanoseconds
    }

    func updateDatabase(databaseId: String, properties: Object) async throws -> NotionObject {
        updateDatabaseCount += 1
        return ["id": .string(databaseId)]
    }

    func createPage(databaseId: String, properties: Object, children: [Block]) async throws -> NotionObject {
        createCount += 1
        capturedChildren = children
        capturedProperties = properties

        if createDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: createDelayNanoseconds)
        }

        return ["id": .string(createdPageID)]
    }

    func callStats() -> (updateDatabaseCount: Int, createCount: Int) {
        (updateDatabaseCount, createCount)
    }

    func lastCreatedChildren() -> [Block] {
        capturedChildren
    }

    func lastCreatedProperties() -> Object {
        capturedProperties
    }
}
