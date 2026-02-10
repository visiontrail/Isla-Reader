//
//  NotionPageBlockAppender.swift
//  LanRead
//

import Foundation

enum NotionPageBlockAppendError: LocalizedError, Equatable {
    case invalidPageID

    var errorDescription: String? {
        switch self {
        case .invalidPageID:
            return NSLocalizedString("Notion 页面 ID 无效", comment: "")
        }
    }
}

protocol NotionPageBlockAppendAPI {
    func appendBlockChildren(blockId: String, children: [Block]) async throws -> NotionObject
}

extension NotionAPIClient: NotionPageBlockAppendAPI {}

actor NotionPageBlockAppender {
    private let notionClient: NotionPageBlockAppendAPI

    init(notionClient: NotionPageBlockAppendAPI = NotionAPIClient()) {
        self.notionClient = notionClient
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

    private func normalizedPageID(_ rawPageID: String) throws -> String {
        let pageID = rawPageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pageID.isEmpty else {
            throw NotionPageBlockAppendError.invalidPageID
        }
        return pageID
    }
}
