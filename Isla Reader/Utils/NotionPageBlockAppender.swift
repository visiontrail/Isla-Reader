//
//  NotionPageBlockAppender.swift
//  LanRead
//

import Foundation

struct NotionHighlightReadingLocation: Equatable, Sendable {
    let chapterIndex: Int
    let pageIndex: Int
    let textOffset: Int?
}

struct NotionHighlightSnapshot: Equatable, Sendable {
    let highlightText: String
    let noteText: String?
    let chapter: String?
    let createdAt: Date
    let updatedAt: Date
    let readingLocation: NotionHighlightReadingLocation?
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
    private static let unknownChapterHeadingKey = "highlight.list.unknown_chapter"

    private let notionClient: NotionPageBlockAppendAPI
    private let highlightSortModeProvider: @Sendable () -> HighlightSortMode

    init(
        notionClient: NotionPageBlockAppendAPI = NotionAPIClient(),
        highlightSortModeProvider: @escaping @Sendable () -> HighlightSortMode = { AppSettings.currentHighlightSortMode() }
    ) {
        self.notionClient = notionClient
        self.highlightSortModeProvider = highlightSortModeProvider
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

        switch highlightSortModeProvider() {
        case .modifiedTime:
            appendModifiedTimeGroupedSnapshots(snapshots, to: &blocks)
        case .chapter:
            appendChapterGroupedSnapshots(snapshots, to: &blocks)
        }

        return blocks
    }

    private func appendModifiedTimeGroupedSnapshots(_ snapshots: [NotionHighlightSnapshot], to blocks: inout [Block]) {
        guard !snapshots.isEmpty else { return }

        var previousGrouping: ModifiedTimeGrouping?

        for (index, snapshot) in snapshots.enumerated() {
            let grouping = modifiedTimeGrouping(for: snapshot)
            let startsNewDateSection = grouping != previousGrouping

            if startsNewDateSection {
                if previousGrouping != nil {
                    blocks.append(Self.spacerBlock())
                }
                blocks.append(Self.subheadingBlock(content: grouping.title))
            }

            appendSnapshot(snapshot, to: &blocks)
            previousGrouping = grouping

            guard index < snapshots.count - 1 else {
                continue
            }

            let nextGrouping = modifiedTimeGrouping(for: snapshots[index + 1])
            if nextGrouping == grouping {
                blocks.append(Self.spacerBlock())
            }
        }
    }

    private func appendChapterGroupedSnapshots(_ snapshots: [NotionHighlightSnapshot], to blocks: inout [Block]) {
        guard !snapshots.isEmpty else { return }

        var previousGrouping: ChapterGrouping?

        for (index, snapshot) in snapshots.enumerated() {
            let grouping = chapterGrouping(for: snapshot)
            let startsNewChapter = grouping != previousGrouping

            if startsNewChapter {
                if previousGrouping != nil {
                    blocks.append(Self.spacerBlock())
                }
                blocks.append(Self.subheadingBlock(content: grouping.title))
            }

            appendSnapshot(snapshot, to: &blocks)
            previousGrouping = grouping

            guard index < snapshots.count - 1 else {
                continue
            }

            let nextGrouping = chapterGrouping(for: snapshots[index + 1])
            if nextGrouping == grouping {
                blocks.append(Self.spacerBlock())
            }
        }
    }

    private func appendSnapshot(_ snapshot: NotionHighlightSnapshot, to blocks: inout [Block]) {
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

    private static func subheadingBlock(content: String) -> Block {
        [
            "object": .string("block"),
            "type": .string("heading_2"),
            "heading_2": .object([
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

    private func chapterGrouping(for snapshot: NotionHighlightSnapshot) -> ChapterGrouping {
        let title = normalize(snapshot.chapter)
            ?? NSLocalizedString(Self.unknownChapterHeadingKey, comment: "Unknown chapter heading for Notion sync grouping")
        return ChapterGrouping(title: title)
    }

    private func modifiedTimeGrouping(for snapshot: NotionHighlightSnapshot) -> ModifiedTimeGrouping {
        let dayStart = Calendar.current.startOfDay(for: snapshot.updatedAt)
        let title = DateFormatter.localizedString(from: dayStart, dateStyle: .medium, timeStyle: .none)
        return ModifiedTimeGrouping(dayStart: dayStart, title: title)
    }

    private struct ChapterGrouping: Equatable {
        let title: String
    }

    private struct ModifiedTimeGrouping: Equatable {
        let dayStart: Date
        let title: String
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
