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
        let appender = NotionPageBlockAppender(
            notionClient: api,
            highlightSortModeProvider: { .modifiedTime }
        )

        let snapshots = [
            NotionHighlightSnapshot(
                highlightText: "First highlight",
                noteText: "First note",
                chapter: "Chapter 1",
                createdAt: Date(timeIntervalSince1970: 1_698_500_000),
                updatedAt: Date(timeIntervalSince1970: 1_698_500_100),
                readingLocation: NotionHighlightReadingLocation(chapterIndex: 1, pageIndex: 0, textOffset: 10),
                highlightDate: Date(timeIntervalSince1970: 1_698_500_000),
                noteDate: Date(timeIntervalSince1970: 1_698_500_100)
            ),
            NotionHighlightSnapshot(
                highlightText: "Second highlight",
                noteText: nil,
                chapter: "Chapter 2",
                createdAt: Date(timeIntervalSince1970: 1_698_400_000),
                updatedAt: Date(timeIntervalSince1970: 1_698_400_000),
                readingLocation: NotionHighlightReadingLocation(chapterIndex: 2, pageIndex: 0, textOffset: 5),
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
        #expect(appendCalls.first?.children.count == 8)

        let types = appendCalls.first?.children.compactMap { $0["type"]?.stringValue } ?? []
        #expect(types == ["heading_1", "divider", "heading_2", "quote", "callout", "paragraph", "heading_2", "quote"])

        let dateHeadings = appendCalls.first?.children
            .filter { $0["type"]?.stringValue == "heading_2" }
            .compactMap { block in
                block["heading_2"]?.objectValue?["rich_text"]?.arrayValue?.first?.objectValue?["text"]?.objectValue?["content"]?.stringValue
            } ?? []
        #expect(dateHeadings.count == 2)
        #expect(dateHeadings.allSatisfy { !$0.isEmpty })

        let quoteBlocks = appendCalls.first?.children.filter { $0["type"]?.stringValue == "quote" } ?? []
        let quoteTexts = quoteBlocks.compactMap { block in
            block["quote"]?.objectValue?["rich_text"]?.arrayValue?.first?.objectValue?["text"]?.objectValue?["content"]?.stringValue
        }
        #expect(quoteTexts == ["First highlight", "Second highlight"])
    }

    @Test
    func replaceHighlightsAndNotesGroupsByModifiedDateWithHeading2WhenSortModeIsModifiedTime() async throws {
        let api = MockNotionPageBlockAppendAPI()
        let appender = NotionPageBlockAppender(
            notionClient: api,
            highlightSortModeProvider: { .modifiedTime }
        )

        let snapshots = [
            NotionHighlightSnapshot(
                highlightText: "Today highlight A",
                noteText: "Today note",
                chapter: "Chapter 3",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
                readingLocation: nil,
                highlightDate: Date(timeIntervalSince1970: 1_700_000_000),
                noteDate: Date(timeIntervalSince1970: 1_700_000_200)
            ),
            NotionHighlightSnapshot(
                highlightText: "Today highlight B",
                noteText: nil,
                chapter: "Chapter 4",
                createdAt: Date(timeIntervalSince1970: 1_700_000_300),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_350),
                readingLocation: nil,
                highlightDate: Date(timeIntervalSince1970: 1_700_000_300),
                noteDate: nil
            ),
            NotionHighlightSnapshot(
                highlightText: "Yesterday highlight",
                noteText: nil,
                chapter: "Chapter 2",
                createdAt: Date(timeIntervalSince1970: 1_699_880_000),
                updatedAt: Date(timeIntervalSince1970: 1_699_880_100),
                readingLocation: nil,
                highlightDate: Date(timeIntervalSince1970: 1_699_880_000),
                noteDate: nil
            )
        ]

        try await appender.replaceHighlightsAndNotes(snapshots, to: "page_modified_grouped")

        let appendCalls = await api.recordedAppendCalls()
        #expect(appendCalls.count == 1)

        let children = appendCalls.first?.children ?? []
        let types = children.compactMap { $0["type"]?.stringValue }
        #expect(types == ["heading_1", "divider", "heading_2", "quote", "callout", "paragraph", "quote", "paragraph", "heading_2", "quote"])

        let headings = children
            .filter { $0["type"]?.stringValue == "heading_2" }
            .compactMap { block in
                block["heading_2"]?.objectValue?["rich_text"]?.arrayValue?.first?.objectValue?["text"]?.objectValue?["content"]?.stringValue
            }
        #expect(headings.count == 2)
        #expect(headings[0] != headings[1])

        let quoteTexts = children
            .filter { $0["type"]?.stringValue == "quote" }
            .compactMap { block in
                block["quote"]?.objectValue?["rich_text"]?.arrayValue?.first?.objectValue?["text"]?.objectValue?["content"]?.stringValue
            }
        #expect(quoteTexts == ["Today highlight A", "Today highlight B", "Yesterday highlight"])
    }

    @Test
    func replaceHighlightsAndNotesGroupsByChapterWithHeading2WhenSortModeIsChapter() async throws {
        let api = MockNotionPageBlockAppendAPI()
        let appender = NotionPageBlockAppender(
            notionClient: api,
            highlightSortModeProvider: { .chapter }
        )

        let snapshots = [
            NotionHighlightSnapshot(
                highlightText: "Chapter one highlight A",
                noteText: "Chapter one note",
                chapter: "Chapter 1",
                createdAt: Date(timeIntervalSince1970: 1_698_500_000),
                updatedAt: Date(timeIntervalSince1970: 1_698_500_050),
                readingLocation: NotionHighlightReadingLocation(chapterIndex: 1, pageIndex: 0, textOffset: 10),
                highlightDate: Date(timeIntervalSince1970: 1_698_500_000),
                noteDate: Date(timeIntervalSince1970: 1_698_500_050)
            ),
            NotionHighlightSnapshot(
                highlightText: "Chapter one highlight B",
                noteText: nil,
                chapter: "Chapter 1",
                createdAt: Date(timeIntervalSince1970: 1_698_500_100),
                updatedAt: Date(timeIntervalSince1970: 1_698_500_100),
                readingLocation: NotionHighlightReadingLocation(chapterIndex: 1, pageIndex: 1, textOffset: 0),
                highlightDate: Date(timeIntervalSince1970: 1_698_500_100),
                noteDate: nil
            ),
            NotionHighlightSnapshot(
                highlightText: "Chapter two highlight",
                noteText: "Chapter two note",
                chapter: "Chapter 2",
                createdAt: Date(timeIntervalSince1970: 1_698_600_000),
                updatedAt: Date(timeIntervalSince1970: 1_698_600_050),
                readingLocation: NotionHighlightReadingLocation(chapterIndex: 2, pageIndex: 0, textOffset: 3),
                highlightDate: Date(timeIntervalSince1970: 1_698_600_000),
                noteDate: Date(timeIntervalSince1970: 1_698_600_050)
            )
        ]

        try await appender.replaceHighlightsAndNotes(snapshots, to: "page_grouped")

        let appendCalls = await api.recordedAppendCalls()
        #expect(appendCalls.count == 1)

        let children = appendCalls.first?.children ?? []
        let types = children.compactMap { $0["type"]?.stringValue }
        #expect(types == ["heading_1", "divider", "heading_2", "quote", "callout", "paragraph", "quote", "paragraph", "heading_2", "quote", "callout"])

        let chapterHeadings = children
            .filter { $0["type"]?.stringValue == "heading_2" }
            .compactMap { block in
                block["heading_2"]?.objectValue?["rich_text"]?.arrayValue?.first?.objectValue?["text"]?.objectValue?["content"]?.stringValue
            }
        #expect(chapterHeadings == ["Chapter 1", "Chapter 2"])

        let quoteTexts = children
            .filter { $0["type"]?.stringValue == "quote" }
            .compactMap { block in
                block["quote"]?.objectValue?["rich_text"]?.arrayValue?.first?.objectValue?["text"]?.objectValue?["content"]?.stringValue
            }
        #expect(quoteTexts == ["Chapter one highlight A", "Chapter one highlight B", "Chapter two highlight"])
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
