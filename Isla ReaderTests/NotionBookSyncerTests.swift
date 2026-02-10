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
            queryResultPageIDs: [],
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
        #expect(callStats.queryCount == 1)
        #expect(callStats.createCount == 1)
    }

    @Test
    func syncUsesRemoteExistingPageThenCachesLocally() async throws {
        let mockClient = MockNotionBookSyncAPI(
            queryResultPageIDs: ["page_existing_1"],
            createdPageID: "page_should_not_be_created"
        )
        let mappingStore = InMemoryBookMappingStore()
        let syncer = NotionBookSyncer(
            notionClient: mockClient,
            mappingStore: mappingStore,
            databaseIDProvider: { "db_test_2" }
        )

        let book = BookInfo(id: "book_2", title: "Deep Work", author: "Cal Newport")

        let first = try await syncer.sync(book: book)
        let second = try await syncer.sync(book: book)

        #expect(first == "page_existing_1")
        #expect(second == "page_existing_1")
        #expect(try mappingStore.notionPageID(for: "book_2") == "page_existing_1")

        let callStats = await mockClient.callStats()
        #expect(callStats.queryCount == 1)
        #expect(callStats.createCount == 0)
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
    private(set) var queryCount = 0
    private(set) var createCount = 0

    private let queryResultPageIDs: [String]
    private let createdPageID: String
    private let createDelayNanoseconds: UInt64

    init(
        queryResultPageIDs: [String],
        createdPageID: String,
        createDelayNanoseconds: UInt64 = 0
    ) {
        self.queryResultPageIDs = queryResultPageIDs
        self.createdPageID = createdPageID
        self.createDelayNanoseconds = createDelayNanoseconds
    }

    func queryDatabase(databaseId: String, filter: Object) async throws -> NotionObject {
        queryCount += 1
        return [
            "results": .array(queryResultPageIDs.map { pageID in
                .object([
                    "id": .string(pageID)
                ])
            })
        ]
    }

    func createPage(databaseId: String, properties: Object, children: [Block]) async throws -> NotionObject {
        createCount += 1

        if createDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: createDelayNanoseconds)
        }

        return ["id": .string(createdPageID)]
    }

    func callStats() -> (queryCount: Int, createCount: Int) {
        (queryCount, createCount)
    }
}
