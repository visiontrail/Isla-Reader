//
//  BlockBuilder.swift
//  LanRead
//

import Foundation

struct BlockBuilder {
    static let maxTextLength = 2000
    private static let truncationSuffix = "..."

    struct HighlightInput: Equatable, Sendable {
        let text: String
        let chapter: String?
        let date: Date

        init(text: String, chapter: String?, date: Date) {
            self.text = text
            self.chapter = chapter
            self.date = date
        }

        init(from highlight: Highlight) {
            text = highlight.selectedText
            chapter = highlight.chapter
            date = highlight.createdAt
        }
    }

    struct NoteInput: Equatable, Sendable {
        let content: String
        let relatedHighlight: HighlightInput?
        let date: Date

        init(content: String, relatedHighlight: HighlightInput?, date: Date) {
            self.content = content
            self.relatedHighlight = relatedHighlight
            self.date = date
        }
    }

    static func buildBlocks(for highlight: HighlightInput) -> [Block] {
        [
            quoteBlock(content: normalizedContent(highlight.text))
        ]
    }

    static func buildBlocks(for note: NoteInput) -> [Block] {
        [
            calloutBlock(content: normalizedContent(note.content))
        ]
    }

    static func buildBlocks(for highlight: Highlight) -> [Block] {
        buildBlocks(for: HighlightInput(from: highlight))
    }

    static func buildBlocksForNote(from highlight: Highlight) -> [Block]? {
        guard let rawNote = highlight.note else {
            return nil
        }

        let trimmed = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let note = NoteInput(
            content: trimmed,
            relatedHighlight: HighlightInput(from: highlight),
            date: highlight.updatedAt
        )
        return buildBlocks(for: note)
    }

    private static func quoteBlock(content: String) -> Block {
        [
            "object": .string("block"),
            "type": .string("quote"),
            "quote": .object([
                "rich_text": richTextArray(content: content),
                "color": .string("default")
            ])
        ]
    }

    private static func paragraphBlock(content: String) -> Block {
        [
            "object": .string("block"),
            "type": .string("paragraph"),
            "paragraph": .object([
                "rich_text": richTextArray(content: content),
                "color": .string("default")
            ])
        ]
    }

    private static func calloutBlock(content: String) -> Block {
        [
            "object": .string("block"),
            "type": .string("callout"),
            "callout": .object([
                "rich_text": richTextArray(content: content),
                "icon": .object([
                    "type": .string("emoji"),
                    "emoji": .string("💡")
                ]),
                "color": .string("default")
            ])
        ]
    }

    private static func richTextArray(content: String, color: String = "default") -> JSONValue {
        .array([
            .object([
                "type": .string("text"),
                "text": .object([
                    "content": .string(content)
                ]),
                "annotations": .object([
                    "bold": .bool(false),
                    "italic": .bool(false),
                    "strikethrough": .bool(false),
                    "underline": .bool(false),
                    "code": .bool(false),
                    "color": .string(color)
                ])
            ])
        ])
    }

    private static func normalizedContent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.isEmpty ? "-" : trimmed

        guard safe.count > maxTextLength else {
            return safe
        }

        let headCount = max(maxTextLength - truncationSuffix.count, 0)
        return String(safe.prefix(headCount)) + truncationSuffix
    }

}
