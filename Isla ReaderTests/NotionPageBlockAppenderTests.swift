//
//  NotionPageBlockAppenderTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct NotionPageBlockAppenderTests {
    @Test
    func appendHighlightUsesAppendBlockChildren() async throws {
        let api = MockNotionPageBlockAppendAPI()
        let appender = NotionPageBlockAppender(notionClient: api)

        let highlight = BlockBuilder.HighlightInput(
            text: "Highlighted source text",
            chapter: "Chapter 1",
            date: Date(timeIntervalSince1970: 1_698_369_600)
        )

        try await appender.appendHighlight(highlight, to: "page_123")

        let calls = await api.recordedAppendCalls()
        #expect(calls.count == 1)
        #expect(calls.first?.blockID == "page_123")
        #expect(calls.first?.children.count == 1)
        #expect(calls.first?.children.first?["type"] == .string("quote"))
    }

    @Test
    func replaceHighlightsAndNotesArchivesExistingBlocksAndRebuildsPage() async throws {
        let api = MockNotionPageBlockAppendAPI(existingBlockIDs: ["old_1", "old_2"])
        let appender = NotionPageBlockAppender(notionClient: api)

        let snapshots = [
            NotionHighlightSnapshot(
                highlightText: "First highlight",
                noteText: "First note",
                chapter: "Chapter 1",
                highlightDate: Date(timeIntervalSince1970: 1_698_369_600),
                noteDate: Date(timeIntervalSince1970: 1_698_370_000)
            ),
            NotionHighlightSnapshot(
                highlightText: "Second highlight",
                noteText: nil,
                chapter: "Chapter 2",
                highlightDate: Date(timeIntervalSince1970: 1_698_400_000),
                noteDate: nil
            )
        ]

        try await appender.replaceHighlightsAndNotes(snapshots, to: "page_abc")

        let listCalls = await api.recordedListCalls()
        #expect(listCalls.count == 1)
        #expect(listCalls.first?.blockID == "page_abc")

        let archivedBlockIDs = await api.recordedArchivedBlockIDs()
        #expect(archivedBlockIDs == ["old_1", "old_2"])

        let appendCalls = await api.recordedAppendCalls()
        #expect(appendCalls.count == 1)
        #expect(appendCalls.first?.blockID == "page_abc")
        #expect(appendCalls.first?.children.count == 6)

        let types = appendCalls.first?.children.compactMap { $0["type"]?.stringValue } ?? []
        #expect(types == ["heading_1", "divider", "quote", "callout", "paragraph", "quote"])
    }

    @Test
    func appendRejectsEmptyPageID() async throws {
        let api = MockNotionPageBlockAppendAPI()
        let appender = NotionPageBlockAppender(notionClient: api)

        let highlight = BlockBuilder.HighlightInput(text: "text", chapter: nil, date: Date())

        do {
            try await appender.appendHighlight(highlight, to: "   ")
            Issue.record("Expected NotionPageBlockAppendError.invalidPageID")
        } catch let error as NotionPageBlockAppendError {
            #expect(error == .invalidPageID)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let calls = await api.recordedAppendCalls()
        #expect(calls.isEmpty)
    }
}

private actor MockNotionPageBlockAppendAPI: NotionPageBlockAppendAPI {
    struct Call {
        let blockID: String
        let children: [Block]
    }

    struct ListCall {
        let blockID: String
        let startCursor: String?
        let pageSize: Int
    }

    private let existingBlockIDs: [String]
    private var appendCalls: [Call] = []
    private var listCalls: [ListCall] = []
    private var archivedBlockIDs: [String] = []

    init(existingBlockIDs: [String] = []) {
        self.existingBlockIDs = existingBlockIDs
    }

    func appendBlockChildren(blockId: String, children: [Block]) async throws -> NotionObject {
        appendCalls.append(Call(blockID: blockId, children: children))
        return ["object": .string("list")]
    }

    func listBlockChildren(blockId: String, startCursor: String?, pageSize: Int) async throws -> NotionObject {
        listCalls.append(ListCall(blockID: blockId, startCursor: startCursor, pageSize: pageSize))

        let results: [JSONValue] = existingBlockIDs.map { blockID in
            .object([
                "id": .string(blockID)
            ])
        }

        return [
            "object": .string("list"),
            "results": .array(results),
            "has_more": .bool(false),
            "next_cursor": .null
        ]
    }

    func archiveBlock(blockId: String) async throws -> NotionObject {
        archivedBlockIDs.append(blockId)
        return [
            "id": .string(blockId),
            "archived": .bool(true)
        ]
    }

    func recordedAppendCalls() -> [Call] {
        appendCalls
    }

    func recordedListCalls() -> [ListCall] {
        listCalls
    }

    func recordedArchivedBlockIDs() -> [String] {
        archivedBlockIDs
    }
}
