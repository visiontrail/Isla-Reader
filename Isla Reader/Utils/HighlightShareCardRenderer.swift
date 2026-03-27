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
    let footerSubtitleText: String
    let coverImageData: Data?

    var attributionLine: String {
        "— \(bookTitle) · \(chapterTitle)"
    }

    static func make(
        highlightText: String,
        noteText: String?,
        bookTitle: String,
        chapterTitle: String?,
        chapterFallback: String,
        footerText: String,
        footerSubtitleText: String,
        coverImageData: Data?
    ) -> HighlightShareCardPayload {
        HighlightShareCardPayload(
            highlightText: normalizedHighlightText(highlightText),
            noteText: normalizedNoteText(noteText),
            bookTitle: normalizedBookTitle(bookTitle),
            chapterTitle: normalizedChapterTitle(from: chapterTitle, fallback: chapterFallback),
            footerText: footerText.trimmingCharacters(in: .whitespacesAndNewlines),
            footerSubtitleText: footerSubtitleText.trimmingCharacters(in: .whitespacesAndNewlines),
            coverImageData: coverImageData
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

private enum HighlightShareCoverPlacement {
    case inlineTrailing
    case bottomFill
}

private struct HighlightShareCardLayoutProfile {
    let coverPlacement: HighlightShareCoverPlacement
    let bottomCoverSize: CGSize

    static let inlineDefault = HighlightShareCardLayoutProfile(
        coverPlacement: .inlineTrailing,
        bottomCoverSize: .zero
    )
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
        let layoutProfile = resolveLayoutProfile(payload: payload, mode: mode)
        let renderer = ImageRenderer(
            content: HighlightShareCardView(
                payload: payload,
                mode: mode,
                layoutProfile: layoutProfile
            )
        )
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = ProposedViewSize(width: HighlightShareCardStyle.cardWidth, height: mode.proposedHeight)

        guard let image = renderer.uiImage else {
            throw HighlightShareError.renderFailed
        }
        return image
    }

    @MainActor
    private static func resolveLayoutProfile(
        payload: HighlightShareCardPayload,
        mode: HighlightShareCardRenderMode
    ) -> HighlightShareCardLayoutProfile {
        guard mode == .fullLength else {
            return .inlineDefault
        }

        let fixedContentHeight = estimatedFixedContentHeight(payload: payload, mode: mode)
        let remainingWhitespace = HighlightShareCardStyle.baselineHeight - fixedContentHeight
        guard remainingWhitespace > HighlightShareCardStyle.coverBottomFillTriggerWhitespace else {
            return .inlineDefault
        }

        let bottomCoverHeight = min(
            max(
                remainingWhitespace * HighlightShareCardStyle.coverBottomFillFactor,
                HighlightShareCardStyle.bottomCoverMinHeight
            ),
            HighlightShareCardStyle.bottomCoverMaxHeight
        )
        return HighlightShareCardLayoutProfile(
            coverPlacement: .bottomFill,
            bottomCoverSize: CGSize(
                width: bottomCoverHeight * HighlightShareCardStyle.coverAspectRatio,
                height: bottomCoverHeight
            )
        )
    }

    @MainActor
    private static func estimatedFixedContentHeight(
        payload: HighlightShareCardPayload,
        mode: HighlightShareCardRenderMode
    ) -> CGFloat {
        let highlightFont = UIFont.systemFont(ofSize: 58, weight: .semibold)
        let attributionFont = UIFont.systemFont(ofSize: 33, weight: .semibold)
        let noteFont = UIFont.systemFont(ofSize: 36, weight: .regular)

        let highlightHeight = estimatedTextHeight(
            "“\(payload.highlightText)”",
            width: HighlightShareCardStyle.contentWidth,
            font: highlightFont,
            lineSpacing: 10,
            lineLimit: mode.highlightLineLimit
        )
        let attributionHeight = estimatedTextHeight(
            payload.attributionLine,
            width: HighlightShareCardStyle.contentWidth
                - HighlightShareCardStyle.inlineCoverWidth
                - HighlightShareCardStyle.coverInlineSpacing,
            font: attributionFont,
            lineSpacing: 0,
            lineLimit: mode.attributionLineLimit
        )

        let topBlockHeight = highlightHeight
            + HighlightShareCardStyle.topBlockSpacing
            + max(attributionHeight, HighlightShareCardStyle.inlineCoverHeight)

        let noteCardHeight: CGFloat
        if let noteText = payload.noteText {
            let noteHeight = estimatedTextHeight(
                sanitizedForMeasurement(noteText),
                width: HighlightShareCardStyle.noteTextWidth,
                font: noteFont,
                lineSpacing: 8,
                lineLimit: mode.noteLineLimit
            )
            noteCardHeight = noteHeight + (HighlightShareCardStyle.noteVerticalPadding * 2)
        } else {
            noteCardHeight = 0
        }

        let stackSpacingCount = payload.noteText == nil ? 2 : 3
        return (HighlightShareCardStyle.verticalPadding * 2)
            + topBlockHeight
            + noteCardHeight
            + (HighlightShareCardStyle.stackSpacing * CGFloat(stackSpacingCount))
            + HighlightShareCardStyle.footerHeight
    }

    @MainActor
    private static func estimatedTextHeight(
        _ text: String,
        width: CGFloat,
        font: UIFont,
        lineSpacing: CGFloat,
        lineLimit: Int?
    ) -> CGFloat {
        guard width > 0 else {
            return 0
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing

        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )

        let bounding = attributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let measuredHeight = ceil(bounding.height)
        guard let lineLimit else {
            return measuredHeight
        }

        let singleLine = ceil(font.lineHeight)
        let maxHeight = (singleLine * CGFloat(lineLimit))
            + (lineSpacing * CGFloat(max(lineLimit - 1, 0)))
        return min(measuredHeight, maxHeight)
    }

    private static func sanitizedForMeasurement(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
    }
}

private struct HighlightShareCardView: View {
    let payload: HighlightShareCardPayload
    let mode: HighlightShareCardRenderMode
    let layoutProfile: HighlightShareCardLayoutProfile

    private var coverUIImage: UIImage? {
        guard let coverImageData = payload.coverImageData else {
            return nil
        }
        return UIImage(data: coverImageData)
    }

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

                    HStack(alignment: .bottom, spacing: 24) {
                        Text(payload.attributionLine)
                            .font(.system(size: 33, weight: .semibold, design: .serif))
                            .foregroundColor(Color(red: 0.33, green: 0.40, blue: 0.48))
                            .lineLimit(mode.attributionLineLimit)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if layoutProfile.coverPlacement == .inlineTrailing {
                            coverView(
                                width: HighlightShareCardStyle.inlineCoverWidth,
                                height: HighlightShareCardStyle.inlineCoverHeight
                            )
                        }
                    }
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

                if layoutProfile.coverPlacement == .bottomFill {
                    coverView(
                        width: layoutProfile.bottomCoverSize.width,
                        height: layoutProfile.bottomCoverSize.height
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                HStack(spacing: 12) {
                    Text(payload.footerText)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.45, green: 0.49, blue: 0.56))
                        .lineLimit(1)

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

                    Text(payload.footerSubtitleText)
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.45, green: 0.49, blue: 0.56))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 78)
        }
        .frame(width: HighlightShareCardStyle.cardWidth, height: mode.fixedHeight)
        .frame(minHeight: mode.minimumHeight, alignment: .top)
    }

    @ViewBuilder
    private func coverView(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let coverUIImage {
                Image(uiImage: coverUIImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.75))
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundColor(Color(red: 0.47, green: 0.53, blue: 0.60))
                    )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 6)
    }
}

private enum HighlightShareCardStyle {
    static let cardWidth: CGFloat = 1080
    static let baselineHeight: CGFloat = 1440
    static let inlineCoverWidth: CGFloat = 126
    static let inlineCoverHeight: CGFloat = 186
    static let coverAspectRatio: CGFloat = inlineCoverWidth / inlineCoverHeight
    static let contentWidth: CGFloat = cardWidth - (72 * 2)
    static let noteTextWidth: CGFloat = contentWidth - (36 * 2)
    static let topBlockSpacing: CGFloat = 18
    static let stackSpacing: CGFloat = 36
    static let verticalPadding: CGFloat = 78
    static let noteVerticalPadding: CGFloat = 26
    static let footerHeight: CGFloat = 44
    static let coverInlineSpacing: CGFloat = 24
    static let coverBottomFillTriggerWhitespace: CGFloat = 340
    static let coverBottomFillFactor: CGFloat = 0.62
    static let bottomCoverMinHeight: CGFloat = 240
    static let bottomCoverMaxHeight: CGFloat = 360
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
