//
//  HighlightShareCardRenderer.swift
//  LanRead
//
//  Created by AI Assistant on 2026/3/2.
//

import SwiftUI
import UIKit

struct HighlightShareCardPayload: Sendable {
    let highlightText: String
    let noteText: String?
    let bookTitle: String
    let chapterTitle: String
    let footerText: String

    var attributionLine: String {
        "— \(bookTitle) · \(chapterTitle)"
    }

    static func make(
        highlightText: String,
        noteText: String?,
        bookTitle: String,
        chapterTitle: String?,
        chapterFallback: String,
        footerText: String
    ) -> HighlightShareCardPayload {
        HighlightShareCardPayload(
            highlightText: normalizedHighlightText(highlightText),
            noteText: normalizedNoteText(noteText),
            bookTitle: normalizedBookTitle(bookTitle),
            chapterTitle: normalizedChapterTitle(from: chapterTitle, fallback: chapterFallback),
            footerText: footerText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func normalizedChapterTitle(from chapterTitle: String?, fallback: String) -> String {
        guard let chapterTitle = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !chapterTitle.isEmpty else {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return chapterTitle
    }

    static func normalizedNoteText(_ noteText: String?) -> String? {
        guard let noteText = noteText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !noteText.isEmpty else {
            return nil
        }
        return noteText
    }

    private static func normalizedHighlightText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    private static func normalizedBookTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

enum HighlightShareError: LocalizedError {
    case renderFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Failed to render share image."
        case .writeFailed:
            return "Failed to write share image."
        }
    }
}

enum HighlightShareCardRenderer {
    static func renderPNG(payload: HighlightShareCardPayload) async throws -> URL {
        let image = try await renderImage(payload: payload)
        guard let data = image.pngData() else {
            throw HighlightShareError.writeFailed
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("highlight-share-\(UUID().uuidString)")
            .appendingPathExtension("png")
        do {
            try data.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            throw HighlightShareError.writeFailed
        }
    }

    static func renderImage(payload: HighlightShareCardPayload) async throws -> UIImage {
        try await MainActor.run {
            do {
                return try renderImage(payload: payload, mode: .fullLength)
            } catch {
                DebugLogger.warning("HighlightShareCardRenderer: 长图渲染失败，回退为省略模式。原因: \(error.localizedDescription)")
                return try renderImage(payload: payload, mode: .truncated)
            }
        }
    }

    @MainActor
    private static func renderImage(
        payload: HighlightShareCardPayload,
        mode: HighlightShareCardRenderMode
    ) throws -> UIImage {
        let renderer = ImageRenderer(content: HighlightShareCardView(payload: payload, mode: mode))
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = ProposedViewSize(width: HighlightShareCardStyle.cardWidth, height: mode.proposedHeight)

        guard let image = renderer.uiImage else {
            throw HighlightShareError.renderFailed
        }
        return image
    }
}

private struct HighlightShareCardView: View {
    let payload: HighlightShareCardPayload
    let mode: HighlightShareCardRenderMode

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 0.99),
                    Color(red: 0.98, green: 0.98, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 36) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("“\(payload.highlightText)”")
                        .font(.system(size: 58, weight: .semibold, design: .serif))
                        .foregroundColor(Color(red: 0.16, green: 0.21, blue: 0.30))
                        .lineSpacing(10)
                        .lineLimit(mode.highlightLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(payload.attributionLine)
                        .font(.system(size: 33, weight: .semibold, design: .serif))
                        .foregroundColor(Color(red: 0.33, green: 0.40, blue: 0.48))
                        .lineLimit(mode.attributionLineLimit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let noteText = payload.noteText {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(
                            MarkdownRenderer.render(
                                noteText,
                                textColor: Color(red: 0.24, green: 0.29, blue: 0.36),
                                typography: .shareCard
                            )
                        )
                            .lineSpacing(8)
                            .lineLimit(mode.noteLineLimit)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 26)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Text(payload.footerText)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.45, green: 0.49, blue: 0.56))

                    Image("LanReadIcon")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 78)
        }
        .frame(width: HighlightShareCardStyle.cardWidth, height: mode.fixedHeight)
        .frame(minHeight: mode.minimumHeight, alignment: .top)
    }
}

private enum HighlightShareCardStyle {
    static let cardWidth: CGFloat = 1080
    static let baselineHeight: CGFloat = 1440
}

private enum HighlightShareCardRenderMode {
    case fullLength
    case truncated

    var proposedHeight: CGFloat? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return HighlightShareCardStyle.baselineHeight
        }
    }

    var fixedHeight: CGFloat? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return HighlightShareCardStyle.baselineHeight
        }
    }

    var minimumHeight: CGFloat? {
        switch self {
        case .fullLength:
            return HighlightShareCardStyle.baselineHeight
        case .truncated:
            return nil
        }
    }

    var highlightLineLimit: Int? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return 9
        }
    }

    var attributionLineLimit: Int? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return 2
        }
    }

    var noteLineLimit: Int? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return 8
        }
    }
}
