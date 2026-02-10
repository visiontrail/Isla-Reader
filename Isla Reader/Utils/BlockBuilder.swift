//
//  BlockBuilder.swift
//  LanRead
//

import Foundation

struct BlockBuilder {
    static let maxTextLength = 2000
    private static let truncationSuffix = "..."
    private static let fallbackChapter = "Unknown Chapter"

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
            quoteBlock(content: normalizedContent(highlight.text)),
            footerBlock(chapter: highlight.chapter, date: highlight.date)
        ]
    }

    static func buildBlocks(for note: NoteInput) -> [Block] {
        [
            paragraphBlock(content: normalizedContent(note.content)),
            footerBlock(chapter: note.relatedHighlight?.chapter, date: note.date)
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

    private static func footerBlock(chapter: String?, date: Date) -> Block {
        let chapterText = normalizedChapter(chapter)
        let dateText = formattedDate(date)
        let content = normalizedContent("\(chapterText) • \(dateText)")

        return [
            "object": .string("block"),
            "type": .string("paragraph"),
            "paragraph": .object([
                "rich_text": richTextArray(content: content, color: "gray"),
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

    private static func normalizedChapter(_ rawChapter: String?) -> String {
        guard let rawChapter else {
            return fallbackChapter
        }

        let trimmed = rawChapter.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackChapter : trimmed
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
