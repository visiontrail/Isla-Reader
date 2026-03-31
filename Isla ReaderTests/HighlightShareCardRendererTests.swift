//
//  HighlightShareCardRendererTests.swift
//  LanReadTests
//

import Foundation
import Testing
import UIKit
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
            footerText: "Shared from LanRead",
            footerSubtitleText: "AI for EPUB, synced to Notion",
            coverImageData: nil
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
            footerText: "Shared from LanRead",
            footerSubtitleText: "AI for EPUB, synced to Notion",
            coverImageData: nil
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
            footerText: "Shared from LanRead",
            footerSubtitleText: "AI for EPUB, synced to Notion",
            coverImageData: nil
        )

        let fileURL = try await HighlightShareCardRenderer.renderPNG(payload: payload)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        #expect(data.count > 8)
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @Test
    func sparseContentMovesCoverToLowerArea() async throws {
        let payload = HighlightShareCardPayload.make(
            highlightText: "Work smart, not hard.",
            noteText: nil,
            bookTitle: "10x Is Easier Than 2x",
            chapterTitle: "Chapter 1",
            chapterFallback: "Unknown chapter",
            footerText: "Shared from LanRead",
            footerSubtitleText: "AI for EPUB, synced to Notion",
            coverImageData: Self.solidCoverImageData()
        )

        let image = try await HighlightShareCardRenderer.renderImage(payload: payload)
        if let pngData = image.pngData() {
            try Self.exportSnapshotIfRequested(
                pngData,
                fileName: "highlight-share-sparse-bottom-cover.png"
            )
        }

        let normalizedBounds = Self.normalizedRedBounds(in: image)
        #expect(normalizedBounds != nil)
        guard let normalizedBounds else { return }
        #expect(normalizedBounds.midY > 0.60)
    }

    @Test
    func denseContentKeepsCoverNearTop() async throws {
        let longHighlight = Array(repeating: "High leverage comes from clarity and repetition.", count: 18)
            .joined(separator: " ")
        let longNote = Array(repeating: "Write one actionable experiment and review it nightly.", count: 14)
            .joined(separator: "\n")

        let payload = HighlightShareCardPayload.make(
            highlightText: longHighlight,
            noteText: longNote,
            bookTitle: "Systems Thinking",
            chapterTitle: "Compounding",
            chapterFallback: "Unknown chapter",
            footerText: "Shared from LanRead",
            footerSubtitleText: "AI for EPUB, synced to Notion",
            coverImageData: Self.solidCoverImageData()
        )

        let image = try await HighlightShareCardRenderer.renderImage(payload: payload)
        let normalizedBounds = Self.normalizedRedBounds(in: image)
        #expect(normalizedBounds != nil)
        guard let normalizedBounds else { return }
        #expect(normalizedBounds.midY < 0.45)
    }

    @Test
    func extremelyLongContentFallsBackToTruncatedImageHeight() async throws {
        let veryLongHighlight = Array(
            repeating: "Clarity compounds when ideas are written, reviewed, and refined with intent.",
            count: 1400
        ).joined(separator: " ")

        let payload = HighlightShareCardPayload.make(
            highlightText: veryLongHighlight,
            noteText: nil,
            bookTitle: "Long-form Notes",
            chapterTitle: "Chapter 9",
            chapterFallback: "Unknown chapter",
            footerText: "Shared from LanRead",
            footerSubtitleText: "AI for EPUB, synced to Notion",
            coverImageData: nil
        )

        let image = try await HighlightShareCardRenderer.renderImage(payload: payload)
        #expect(image.size.width == 1080)
        #expect(image.size.height == 1440)
    }

    private static func solidCoverImageData() -> Data? {
        let size = CGSize(width: 180, height: 266)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 0.90, green: 0.17, blue: 0.13, alpha: 1).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()
    }

    private static func normalizedRedBounds(in image: UIImage) -> CGRect? {
        let sampledImage = downsampled(image: image, targetWidth: 360)
        guard let cgImage = sampledImage.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bufferSize = bytesPerRow * height
        var pixels = [UInt8](repeating: 0, count: bufferSize)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * bytesPerRow) + (x * bytesPerPixel)
                let red = pixels[index]
                let green = pixels[index + 1]
                let blue = pixels[index + 2]
                let alpha = pixels[index + 3]

                if red > 200, green < 70, blue < 70, alpha > 220 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        let normalizedX = CGFloat(minX) / CGFloat(width)
        let normalizedY = CGFloat(minY) / CGFloat(height)
        let normalizedWidth = CGFloat(maxX - minX + 1) / CGFloat(width)
        let normalizedHeight = CGFloat(maxY - minY + 1) / CGFloat(height)

        return CGRect(
            x: normalizedX,
            y: normalizedY,
            width: normalizedWidth,
            height: normalizedHeight
        )
    }

    private static func downsampled(image: UIImage, targetWidth: CGFloat) -> UIImage {
        guard image.size.width > 0 else {
            return image
        }

        let scale = targetWidth / image.size.width
        let targetSize = CGSize(
            width: targetWidth,
            height: max(image.size.height * scale, 1)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func exportSnapshotIfRequested(_ data: Data, fileName: String) throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["LANREAD_SNAPSHOT_OUTPUT_DIR"],
              !outputDirectory.isEmpty else {
            return
        }

        let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let outputURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: outputURL, options: [.atomic])
    }
}
