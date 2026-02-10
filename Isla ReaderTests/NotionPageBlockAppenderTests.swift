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

        let calls = await api.recordedCalls()
        #expect(calls.count == 1)
        #expect(calls.first?.blockID == "page_123")
        #expect(calls.first?.children.count == 2)
        #expect(calls.first?.children.first?["type"] == .string("quote"))
    }

    @Test
    func appendNoteUsesAppendBlockChildren() async throws {
        let api = MockNotionPageBlockAppendAPI()
        let appender = NotionPageBlockAppender(notionClient: api)

        let note = BlockBuilder.NoteInput(
            content: "My note",
            relatedHighlight: BlockBuilder.HighlightInput(text: "source", chapter: "Chapter 2", date: Date()),
            date: Date(timeIntervalSince1970: 1_698_456_000)
        )

        try await appender.appendNote(note, to: "page_note")

        let calls = await api.recordedCalls()
        #expect(calls.count == 1)
        #expect(calls.first?.blockID == "page_note")
        #expect(calls.first?.children.count == 2)
        #expect(calls.first?.children.first?["type"] == .string("paragraph"))
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

        let calls = await api.recordedCalls()
        #expect(calls.isEmpty)
    }
}

private actor MockNotionPageBlockAppendAPI: NotionPageBlockAppendAPI {
    struct Call {
        let blockID: String
        let children: [Block]
    }

    private var calls: [Call] = []

    func appendBlockChildren(blockId: String, children: [Block]) async throws -> NotionObject {
        calls.append(Call(blockID: blockId, children: children))
        return ["object": .string("list")]
    }

    func recordedCalls() -> [Call] {
        calls
    }
}
