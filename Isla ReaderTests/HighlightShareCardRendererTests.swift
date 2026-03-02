//
//  HighlightShareCardRendererTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct HighlightShareCardRendererTests {
    @Test
    func payloadUsesFallbackChapterAndDropsEmptyNote() {
        let payload = HighlightShareCardPayload.make(
            highlightText: "  Build momentum every day.  ",
            noteText: "   ",
            bookTitle: "Atomic Habits",
            chapterTitle: nil,
            chapterFallback: "Unknown chapter",
            footerText: "Shared from LanRead"
        )

        #expect(payload.highlightText == "Build momentum every day.")
        #expect(payload.noteText == nil)
        #expect(payload.chapterTitle == "Unknown chapter")
        #expect(payload.attributionLine == "— Atomic Habits · Unknown chapter")
    }

    @Test
    func payloadKeepsTrimmedNoteAndChapter() {
        let payload = HighlightShareCardPayload.make(
            highlightText: "Discipline over motivation.",
            noteText: "\nApply this in morning routine.\n",
            bookTitle: "Deep Work",
            chapterTitle: "  Chapter 2  ",
            chapterFallback: "Unknown chapter",
            footerText: "Shared from LanRead"
        )

        #expect(payload.chapterTitle == "Chapter 2")
        #expect(payload.noteText == "Apply this in morning routine.")
    }

    @Test
    func renderPNGProducesValidTemporaryPNGFile() async throws {
        let payload = HighlightShareCardPayload.make(
            highlightText: "The journey of a thousand miles begins with a single step.",
            noteText: "Take one concrete action today.",
            bookTitle: "Tao Te Ching",
            chapterTitle: "Chapter 64",
            chapterFallback: "Unknown chapter",
            footerText: "Shared from LanRead"
        )

        let fileURL = try await HighlightShareCardRenderer.renderPNG(payload: payload)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        #expect(data.count > 8)
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
