//
//  NotionPageBlockAppender.swift
//  LanRead
//

import Foundation

struct NotionHighlightSnapshot: Equatable, Sendable {
    let highlightText: String
    let noteText: String?
    let chapter: String?
    let highlightDate: Date
    let noteDate: Date?
}

enum NotionPageBlockAppendError: LocalizedError, Equatable {
    case invalidPageID

    var errorDescription: String? {
        switch self {
        case .invalidPageID:
            return NSLocalizedString("notion.page.error.invalid_page_id", comment: "")
        }
    }
}

protocol NotionPageBlockAppendAPI {
    func appendBlockChildren(blockId: String, children: [Block]) async throws -> NotionObject
    func listBlockChildren(blockId: String, startCursor: String?, pageSize: Int) async throws -> NotionObject
    func archiveBlock(blockId: String) async throws -> NotionObject
}

extension NotionAPIClient: NotionPageBlockAppendAPI {}

actor NotionPageBlockAppender {
    private static let maxAppendBatchSize = 100
    private static let maxPayloadBytes = 450_000
    private static let notesHeading = "📝 Highlights & Notes"

    private let notionClient: NotionPageBlockAppendAPI

    init(notionClient: NotionPageBlockAppendAPI = NotionAPIClient()) {
        self.notionClient = notionClient
    }

    func replaceHighlightsAndNotes(_ snapshots: [NotionHighlightSnapshot], to pageID: String) async throws {
        let blockID = try normalizedPageID(pageID)

        let existingBlockIDs = try await fetchAllChildBlockIDs(parentBlockID: blockID)
        for existingBlockID in existingBlockIDs {
            _ = try await notionClient.archiveBlock(blockId: existingBlockID)
        }

        let rebuiltBlocks = buildSyncedBlocks(from: snapshots)
        try await appendBlocksInBatches(rebuiltBlocks, to: blockID)
    }

    func appendHighlight(_ highlight: BlockBuilder.HighlightInput, to pageID: String) async throws {
        let blockID = try normalizedPageID(pageID)
        let blocks = BlockBuilder.buildBlocks(for: highlight)
        _ = try await notionClient.appendBlockChildren(blockId: blockID, children: blocks)
    }

    func appendNote(_ note: BlockBuilder.NoteInput, to pageID: String) async throws {
        let blockID = try normalizedPageID(pageID)
        let blocks = BlockBuilder.buildBlocks(for: note)
        _ = try await notionClient.appendBlockChildren(blockId: blockID, children: blocks)
    }

    func appendHighlight(_ highlight: Highlight, to pageID: String) async throws {
        try await appendHighlight(BlockBuilder.HighlightInput(from: highlight), to: pageID)
    }

    func appendNoteIfExists(from highlight: Highlight, to pageID: String) async throws {
        guard let noteBlocks = BlockBuilder.buildBlocksForNote(from: highlight) else {
            return
        }

        let blockID = try normalizedPageID(pageID)
        _ = try await notionClient.appendBlockChildren(blockId: blockID, children: noteBlocks)
    }

    private func appendBlocksInBatches(_ blocks: [Block], to blockID: String) async throws {
        guard !blocks.isEmpty else { return }

        var chunk: [Block] = []

        for block in blocks {
            let candidateChunk = chunk + [block]
            let exceedsCountLimit = candidateChunk.count > Self.maxAppendBatchSize
            let exceedsPayloadLimit = isPayloadTooLarge(candidateChunk)

            if !chunk.isEmpty && (exceedsCountLimit || exceedsPayloadLimit) {
                _ = try await notionClient.appendBlockChildren(blockId: blockID, children: chunk)
                chunk = [block]
            } else {
                chunk = candidateChunk
            }
        }

        if !chunk.isEmpty {
            _ = try await notionClient.appendBlockChildren(blockId: blockID, children: chunk)
        }
    }

    private func fetchAllChildBlockIDs(parentBlockID: String) async throws -> [String] {
        var result: [String] = []
        var cursor: String?

        while true {
            let response = try await notionClient.listBlockChildren(
                blockId: parentBlockID,
                startCursor: cursor,
                pageSize: Self.maxAppendBatchSize
            )

            result.append(contentsOf: Self.extractBlockIDs(from: response))

            let hasMore = response["has_more"]?.boolValue ?? false
            if !hasMore {
                break
            }

            cursor = response["next_cursor"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if cursor?.isEmpty != false {
                break
            }
        }

        return result
    }

    private static func extractBlockIDs(from response: NotionObject) -> [String] {
        guard let results = response["results"]?.arrayValue else {
            return []
        }

        return results.compactMap { element in
            guard let object = element.objectValue,
                  let blockID = object["id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !blockID.isEmpty else {
                return nil
            }
            return blockID
        }
    }

    private func buildSyncedBlocks(from snapshots: [NotionHighlightSnapshot]) -> [Block] {
        var blocks: [Block] = [
            Self.headingBlock(content: Self.notesHeading),
            Self.dividerBlock()
        ]

        let sortedSnapshots = snapshots.sorted { lhs, rhs in
            if lhs.highlightDate != rhs.highlightDate {
                return lhs.highlightDate < rhs.highlightDate
            }
            if lhs.noteDate != rhs.noteDate {
                return (lhs.noteDate ?? lhs.highlightDate) < (rhs.noteDate ?? rhs.highlightDate)
            }
            return lhs.highlightText < rhs.highlightText
        }

        for (index, snapshot) in sortedSnapshots.enumerated() {
            let highlightInput = BlockBuilder.HighlightInput(
                text: snapshot.highlightText,
                chapter: snapshot.chapter,
                date: snapshot.highlightDate
            )
            blocks.append(contentsOf: BlockBuilder.buildBlocks(for: highlightInput))

            if let noteContent = normalize(snapshot.noteText) {
                let noteInput = BlockBuilder.NoteInput(
                    content: noteContent,
                    relatedHighlight: highlightInput,
                    date: snapshot.noteDate ?? snapshot.highlightDate
                )
                blocks.append(contentsOf: BlockBuilder.buildBlocks(for: noteInput))
            }

            if index < sortedSnapshots.count - 1 {
                blocks.append(Self.spacerBlock())
            }
        }

        return blocks
    }

    private static func headingBlock(content: String) -> Block {
        [
            "object": .string("block"),
            "type": .string("heading_1"),
            "heading_1": .object([
                "rich_text": richTextArray(content: content)
            ])
        ]
    }

    private static func dividerBlock() -> Block {
        [
            "object": .string("block"),
            "type": .string("divider"),
            "divider": .object([:])
        ]
    }

    private static func spacerBlock() -> Block {
        [
            "object": .string("block"),
            "type": .string("paragraph"),
            "paragraph": .object([
                "rich_text": .array([])
            ])
        ]
    }

    private static func richTextArray(content: String) -> JSONValue {
        .array([
            .object([
                "type": .string("text"),
                "text": .object([
                    "content": .string(content)
                ])
            ])
        ])
    }

    private func normalizedPageID(_ rawPageID: String) throws -> String {
        let pageID = rawPageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pageID.isEmpty else {
            throw NotionPageBlockAppendError.invalidPageID
        }
        return pageID
    }

    private func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isPayloadTooLarge(_ blocks: [Block]) -> Bool {
        let payload: NotionObject = [
            "children": .array(blocks.map { .object($0) })
        ]
        guard let data = try? JSONEncoder().encode(payload) else {
            return false
        }
        return data.count > Self.maxPayloadBytes
    }
}
