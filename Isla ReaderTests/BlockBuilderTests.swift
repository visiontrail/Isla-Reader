//
//  BlockBuilderTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct BlockBuilderTests {
    @Test
    func buildsQuoteAndGrayFooterForHighlight() throws {
        let highlight = BlockBuilder.HighlightInput(
            text: "We are what we repeatedly do.",
            chapter: "Chapter 1",
            date: fixedDate("2023-10-27T12:00:00Z")
        )

        let blocks = BlockBuilder.buildBlocks(for: highlight)
        #expect(blocks.count == 2)

        let quoteBlock = blocks[0]
        #expect(quoteBlock["object"] == .string("block"))
        #expect(quoteBlock["type"] == .string("quote"))

        let quote = try #require(quoteBlock["quote"]?.objectValue)
        let quoteText = try extractContent(from: quote)
        #expect(quoteText == "We are what we repeatedly do.")

        let footerBlock = blocks[1]
        #expect(footerBlock["type"] == .string("paragraph"))
        let footerParagraph = try #require(footerBlock["paragraph"]?.objectValue)
        let footerText = try extractContent(from: footerParagraph)
        #expect(footerText == "Chapter 1 • 2023-10-27")

        let color = try extractAnnotationColor(from: footerParagraph)
        #expect(color == "gray")
    }

    @Test
    func buildsParagraphAndFooterForNote() throws {
        let related = BlockBuilder.HighlightInput(
            text: "Action beats intention.",
            chapter: "Chapter 2",
            date: fixedDate("2023-10-27T12:00:00Z")
        )
        let note = BlockBuilder.NoteInput(
            content: "这句话可以放到我的每周复盘模板里。",
            relatedHighlight: related,
            date: fixedDate("2023-10-28T08:30:00Z")
        )

        let blocks = BlockBuilder.buildBlocks(for: note)
        #expect(blocks.count == 2)

        let paragraphBlock = blocks[0]
        #expect(paragraphBlock["type"] == .string("paragraph"))
        let paragraph = try #require(paragraphBlock["paragraph"]?.objectValue)
        let noteText = try extractContent(from: paragraph)
        #expect(noteText == "这句话可以放到我的每周复盘模板里。")

        let footerBlock = blocks[1]
        let footerParagraph = try #require(footerBlock["paragraph"]?.objectValue)
        let footerText = try extractContent(from: footerParagraph)
        #expect(footerText == "Chapter 2 • 2023-10-28")
    }

    @Test
    func truncatesTextOverTwoThousandCharacters() throws {
        let longText = String(repeating: "A", count: 2105)
        let highlight = BlockBuilder.HighlightInput(
            text: longText,
            chapter: "Chapter 3",
            date: fixedDate("2023-10-29T09:00:00Z")
        )

        let blocks = BlockBuilder.buildBlocks(for: highlight)
        let quote = try #require(blocks.first?["quote"]?.objectValue)
        let content = try extractContent(from: quote)

        #expect(content.count == BlockBuilder.maxTextLength)
        #expect(content.hasSuffix("..."))
    }
}

private extension BlockBuilderTests {
    func fixedDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) ?? Date(timeIntervalSince1970: 0)
    }

    func extractContent(from container: Object) throws -> String {
        let richText = try #require(container["rich_text"]?.arrayValue)
        let first = try #require(richText.first?.objectValue)
        let text = try #require(first["text"]?.objectValue)
        return try #require(text["content"]?.stringValue)
    }

    func extractAnnotationColor(from container: Object) throws -> String {
        let richText = try #require(container["rich_text"]?.arrayValue)
        let first = try #require(richText.first?.objectValue)
        let annotations = try #require(first["annotations"]?.objectValue)
        return try #require(annotations["color"]?.stringValue)
    }
}
