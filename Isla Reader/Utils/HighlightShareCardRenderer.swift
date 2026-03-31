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
    let profileDisplayName: String
    let profileAvatarData: Data?
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
        coverImageData: Data?,
        profileDisplayName: String = "Reader",
        profileAvatarData: Data? = nil
    ) -> HighlightShareCardPayload {
        HighlightShareCardPayload(
            highlightText: normalizedHighlightText(highlightText),
            noteText: normalizedNoteText(noteText),
            profileDisplayName: normalizedProfileDisplayName(profileDisplayName),
            profileAvatarData: profileAvatarData,
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

    static func normalizedProfileDisplayName(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Reader" : trimmed
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

enum HighlightShareFrameStyle: String, CaseIterable, Identifiable, Sendable {
    case none = "NONE"
    case white = "WHITE"
    case black = "BLACK"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

enum HighlightShareError: LocalizedError {
    case renderFailed
    case writeFailed
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Failed to render share image."
        case .writeFailed:
            return "Failed to write share image."
        case .imageTooLarge:
            return "Share image is too large to export."
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
    static func renderPNG(
        payload: HighlightShareCardPayload,
        frameStyle: HighlightShareFrameStyle = .none
    ) async throws -> URL {
        var lastError: Error?
        for mode in HighlightShareCardRenderMode.fallbackOrder {
            do {
                let image = try await MainActor.run {
                    try renderImage(payload: payload, mode: mode, frameStyle: frameStyle)
                }
                let data = try encodePNGData(from: image)
                return try writePNGDataToTemporaryFile(data)
            } catch {
                lastError = error
                guard mode.shouldAttemptFallback else {
                    throw error
                }
                DebugLogger.warning(
                    "HighlightShareCardRenderer: \(mode.displayName) 导出失败，回退为 \(HighlightShareCardRenderMode.truncated.displayName)。原因: \(error.localizedDescription)"
                )
            }
        }

        throw lastError ?? HighlightShareError.writeFailed
    }

    static func renderImage(
        payload: HighlightShareCardPayload,
        frameStyle: HighlightShareFrameStyle = .none
    ) async throws -> UIImage {
        try await MainActor.run {
            var lastError: Error?
            for mode in HighlightShareCardRenderMode.fallbackOrder {
                do {
                    return try renderImage(payload: payload, mode: mode, frameStyle: frameStyle)
                } catch {
                    lastError = error
                    guard mode.shouldAttemptFallback else {
                        throw error
                    }
                    DebugLogger.warning(
                        "HighlightShareCardRenderer: \(mode.displayName) 渲染失败，回退为 \(HighlightShareCardRenderMode.truncated.displayName)。原因: \(error.localizedDescription)"
                    )
                }
            }

            throw lastError ?? HighlightShareError.renderFailed
        }
    }

    @MainActor
    private static func renderImage(
        payload: HighlightShareCardPayload,
        mode: HighlightShareCardRenderMode,
        frameStyle: HighlightShareFrameStyle
    ) throws -> UIImage {
        let layoutProfile = resolveLayoutProfile(payload: payload, mode: mode, frameStyle: frameStyle)
        let renderer = ImageRenderer(
            content: HighlightShareCardView(
                payload: payload,
                mode: mode,
                layoutProfile: layoutProfile,
                frameStyle: frameStyle
            )
        )
        renderer.scale = HighlightShareCardStyle.exportScale
        renderer.proposedSize = ProposedViewSize(
            width: HighlightShareCardStyle.cardWidth,
            height: mode.proposedHeight(for: frameStyle)
        )

        guard let image = renderer.uiImage else {
            throw HighlightShareError.renderFailed
        }
        try validateRenderedImage(image, mode: mode)
        return image
    }

    private static func encodePNGData(from image: UIImage) throws -> Data {
        guard let data = image.pngData() else {
            throw HighlightShareError.writeFailed
        }
        return data
    }

    private static func writePNGDataToTemporaryFile(_ data: Data) throws -> URL {
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

    @MainActor
    private static func validateRenderedImage(
        _ image: UIImage,
        mode: HighlightShareCardRenderMode
    ) throws {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw HighlightShareError.renderFailed
        }

        switch mode {
        case .truncated:
            return
        case .fullLength:
            break
        }

        let pixelCount = pixelWidth * pixelHeight
        guard pixelHeight <= HighlightShareCardStyle.maxFullLengthPixelHeight,
              pixelCount <= HighlightShareCardStyle.maxFullLengthPixelCount else {
            throw HighlightShareError.imageTooLarge
        }
    }

    @MainActor
    private static func resolveLayoutProfile(
        payload: HighlightShareCardPayload,
        mode: HighlightShareCardRenderMode,
        frameStyle: HighlightShareFrameStyle
    ) -> HighlightShareCardLayoutProfile {
        guard mode == .fullLength else {
            return .inlineDefault
        }

        let fixedContentHeight = estimatedFixedContentHeight(payload: payload, mode: mode, frameStyle: frameStyle)
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
        mode: HighlightShareCardRenderMode,
        frameStyle: HighlightShareFrameStyle
    ) -> CGFloat {
        let highlightFont = UIFont.systemFont(ofSize: 58, weight: .semibold)
        let attributionFont = UIFont.systemFont(ofSize: 33, weight: .semibold)
        let noteFont = UIFont.systemFont(ofSize: 36, weight: .regular)
        let noteNameFont = UIFont.systemFont(ofSize: 24, weight: .semibold)

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
            let noteNameHeight = estimatedTextHeight(
                payload.profileDisplayName,
                width: HighlightShareCardStyle.noteBubbleContentWidth,
                font: noteNameFont,
                lineSpacing: 0,
                lineLimit: 1
            )
            let noteHeight = estimatedTextHeight(
                sanitizedForMeasurement(noteText),
                width: HighlightShareCardStyle.noteBubbleContentWidth,
                font: noteFont,
                lineSpacing: 8,
                lineLimit: mode.noteLineLimit
            )
            let bubbleHeight = noteNameHeight
                + HighlightShareCardStyle.noteNameBubbleSpacing
                + noteHeight
                + (HighlightShareCardStyle.noteBubbleVerticalPadding * 2)
            noteCardHeight = max(HighlightShareCardStyle.noteAvatarSize, bubbleHeight)
        } else {
            noteCardHeight = 0
        }

        let stackSpacingCount = payload.noteText == nil ? 2 : 3
        let effectiveSpacingCount = frameStyle == .none ? stackSpacingCount : max(stackSpacingCount - 1, 0)
        return (HighlightShareCardStyle.verticalPadding * 2)
            + topBlockHeight
            + noteCardHeight
            + (HighlightShareCardStyle.stackSpacing * CGFloat(effectiveSpacingCount))
            + (frameStyle == .none ? HighlightShareCardStyle.footerHeight : 0)
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
    let frameStyle: HighlightShareFrameStyle
    let generatedAt: Date = Date()

    private var coverUIImage: UIImage? {
        guard let coverImageData = payload.coverImageData else {
            return nil
        }
        return UIImage(data: coverImageData)
    }

    var body: some View {
        Group {
            switch frameStyle {
            case .none:
                cardContent(showLegacyFooter: true)
            case .white, .black:
                framedCard
            }
        }
        .frame(width: HighlightShareCardStyle.cardWidth, height: mode.fixedHeight(for: frameStyle))
        .frame(minHeight: mode.minimumHeight(for: frameStyle), alignment: .top)
    }

    private var framedCard: some View {
        ZStack {
            (frameStyle == .white ? Color.white : Color.black)

            VStack(spacing: 0) {
                cardContent(showLegacyFooter: false)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(frameStyle == .white ? Color.black.opacity(0.08) : Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(
                        color: frameStyle == .white ? Color.black.opacity(0.14) : Color.black.opacity(0.45),
                        radius: 16,
                        x: 0,
                        y: 8
                    )
                    .frame(maxHeight: .infinity)

                HStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Image("LanReadIcon")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(frameStyle == .white ? Color.black.opacity(0.16) : Color.white.opacity(0.22), lineWidth: 1)
                            )

                        Text(payload.footerText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 12)

                    Text(Self.frameTimestampFormatter.string(from: generatedAt))
                        .lineLimit(1)
                }
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(frameStyle == .white ? Color.black.opacity(0.78) : Color.white.opacity(0.88))
                .frame(height: HighlightShareCardStyle.frameFooterHeight)
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, HighlightShareCardStyle.frameHorizontalPadding)
            .padding(.top, HighlightShareCardStyle.frameTopPadding)
            .padding(.bottom, HighlightShareCardStyle.frameBottomPadding)
        }
    }

    private func cardContent(showLegacyFooter: Bool) -> some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 36) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("“\(payload.highlightText)”")
                        .font(.system(size: 58, weight: .semibold, design: .serif))
                        .foregroundColor(highlightTextColor)
                        .lineSpacing(10)
                        .lineLimit(mode.highlightLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .bottom, spacing: 24) {
                        Text(payload.attributionLine)
                            .font(.system(size: 33, weight: .semibold, design: .serif))
                            .foregroundColor(attributionTextColor)
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
                    HStack(alignment: .top, spacing: HighlightShareCardStyle.noteRowSpacing) {
                        profileAvatarView(size: HighlightShareCardStyle.noteAvatarSize)

                        noteBubbleView(noteText: noteText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                if layoutProfile.coverPlacement == .bottomFill {
                    coverView(
                        width: layoutProfile.bottomCoverSize.width,
                        height: layoutProfile.bottomCoverSize.height
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if showLegacyFooter {
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
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 78)
        }
    }

    @ViewBuilder
    private func profileAvatarView(size: CGFloat) -> some View {
        Group {
            if let avatarData = payload.profileAvatarData, let avatarImage = UIImage(data: avatarData) {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(defaultAvatarBackgroundGradient)
                    Text(avatarInitial)
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(noteAvatarBorderColor, lineWidth: 1.2)
        )
        .shadow(color: noteAvatarShadowColor, radius: 6, x: 0, y: 3)
    }

    private func noteBubbleView(noteText: String) -> some View {
        VStack(alignment: .leading, spacing: HighlightShareCardStyle.noteNameBubbleSpacing) {
            Text(payload.profileDisplayName)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(noteDisplayNameColor)
                .lineLimit(1)

            Text(
                MarkdownRenderer.render(
                    noteText,
                    textColor: noteTextColor,
                    typography: .shareCard
                )
            )
                .lineSpacing(8)
                .lineLimit(mode.noteLineLimit)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HighlightShareCardStyle.noteBubbleHorizontalPadding)
        .padding(.vertical, HighlightShareCardStyle.noteBubbleVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(noteBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(noteBorderColor, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            ChatBubbleTail()
                .fill(noteBackgroundColor)
                .frame(width: 20, height: 20)
                .offset(x: -9, y: 28)
                .overlay(
                    ChatBubbleTail()
                        .stroke(noteBorderColor, lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .offset(x: -9, y: 28)
                )
        }
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
                    .fill(coverPlaceholderColor)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundColor(coverPlaceholderIconColor)
                    )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(coverBorderColor, lineWidth: 1)
        )
        .shadow(color: coverShadowColor, radius: 10, x: 0, y: 6)
    }

    private var isDarkContent: Bool {
        frameStyle == .white
    }

    private var backgroundGradient: LinearGradient {
        if isDarkContent {
            return LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.14, blue: 0.17),
                    Color(red: 0.20, green: 0.21, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 0.99),
                Color(red: 0.98, green: 0.98, blue: 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var highlightTextColor: Color {
        isDarkContent ? Color(red: 0.90, green: 0.92, blue: 0.97) : Color(red: 0.16, green: 0.21, blue: 0.30)
    }

    private var attributionTextColor: Color {
        isDarkContent ? Color(red: 0.72, green: 0.77, blue: 0.84) : Color(red: 0.33, green: 0.40, blue: 0.48)
    }

    private var noteTextColor: Color {
        isDarkContent ? Color(red: 0.89, green: 0.91, blue: 0.95) : Color(red: 0.24, green: 0.29, blue: 0.36)
    }

    private var noteDisplayNameColor: Color {
        isDarkContent ? Color(red: 0.75, green: 0.81, blue: 0.92) : Color(red: 0.28, green: 0.37, blue: 0.49)
    }

    private var noteBackgroundColor: Color {
        isDarkContent ? Color.black.opacity(0.42) : Color.white.opacity(0.95)
    }

    private var noteBorderColor: Color {
        isDarkContent ? Color.white.opacity(0.14) : Color.black.opacity(0.06)
    }

    private var coverPlaceholderColor: Color {
        isDarkContent ? Color.white.opacity(0.12) : Color.white.opacity(0.75)
    }

    private var coverPlaceholderIconColor: Color {
        isDarkContent ? Color(red: 0.78, green: 0.82, blue: 0.88) : Color(red: 0.47, green: 0.53, blue: 0.60)
    }

    private var coverBorderColor: Color {
        isDarkContent ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    private var coverShadowColor: Color {
        isDarkContent ? Color.black.opacity(0.30) : Color.black.opacity(0.14)
    }

    private var noteAvatarBorderColor: Color {
        isDarkContent ? Color.white.opacity(0.20) : Color.white.opacity(0.86)
    }

    private var noteAvatarShadowColor: Color {
        isDarkContent ? Color.black.opacity(0.32) : Color.black.opacity(0.12)
    }

    private var defaultAvatarBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: isDarkContent
            ? [Color(red: 0.31, green: 0.44, blue: 0.77), Color(red: 0.24, green: 0.34, blue: 0.62)]
            : [Color(red: 0.40, green: 0.57, blue: 0.93), Color(red: 0.30, green: 0.46, blue: 0.84)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var avatarInitial: String {
        let trimmed = payload.profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let letter = String(trimmed.prefix(1)).uppercased()
        return letter.isEmpty ? "U" : letter
    }

    private static let frameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct ChatBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private extension HighlightShareCardRenderMode {
    func proposedHeight(for frameStyle: HighlightShareFrameStyle) -> CGFloat? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return HighlightShareCardStyle.baselineHeight + frameStyle.additionalHeight
        }
    }

    func fixedHeight(for frameStyle: HighlightShareFrameStyle) -> CGFloat? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return HighlightShareCardStyle.baselineHeight + frameStyle.additionalHeight
        }
    }

    func minimumHeight(for frameStyle: HighlightShareFrameStyle) -> CGFloat? {
        switch self {
        case .fullLength:
            return HighlightShareCardStyle.baselineHeight + frameStyle.additionalHeight
        case .truncated:
            return nil
        }
    }
}

private enum HighlightShareCardStyle {
    static let cardWidth: CGFloat = 1080
    static let exportScale: CGFloat = 1
    static let baselineHeight: CGFloat = cardWidth
    static let maxFullLengthPixelHeight: CGFloat = 12_000
    static let maxFullLengthPixelCount: CGFloat = cardWidth * maxFullLengthPixelHeight
    static let inlineCoverWidth: CGFloat = 126
    static let inlineCoverHeight: CGFloat = 186
    static let coverAspectRatio: CGFloat = inlineCoverWidth / inlineCoverHeight
    static let contentWidth: CGFloat = cardWidth - (72 * 2)
    static let noteAvatarSize: CGFloat = 86
    static let noteRowSpacing: CGFloat = 20
    static let noteBubbleHorizontalPadding: CGFloat = 30
    static let noteBubbleVerticalPadding: CGFloat = 22
    static let noteBubbleContentWidth: CGFloat = contentWidth
        - noteAvatarSize
        - noteRowSpacing
        - (noteBubbleHorizontalPadding * 2)
    static let noteNameBubbleSpacing: CGFloat = 10
    static let topBlockSpacing: CGFloat = 18
    static let stackSpacing: CGFloat = 36
    static let verticalPadding: CGFloat = 78
    static let footerHeight: CGFloat = 44
    static let coverInlineSpacing: CGFloat = 24
    static let coverBottomFillTriggerWhitespace: CGFloat = 340
    static let coverBottomFillFactor: CGFloat = 0.62
    static let bottomCoverMinHeight: CGFloat = 240
    static let bottomCoverMaxHeight: CGFloat = 360
    static let frameHorizontalPadding: CGFloat = 42
    static let frameTopPadding: CGFloat = 42
    static let frameBottomPadding: CGFloat = 24
    static let frameFooterHeight: CGFloat = 110
}

private enum HighlightShareCardRenderMode {
    case fullLength
    case truncated

    static let fallbackOrder: [HighlightShareCardRenderMode] = [.fullLength, .truncated]

    var shouldAttemptFallback: Bool {
        switch self {
        case .fullLength:
            return true
        case .truncated:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .fullLength:
            return "长图模式"
        case .truncated:
            return "省略模式"
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

private extension HighlightShareFrameStyle {
    var additionalHeight: CGFloat {
        switch self {
        case .none:
            return 0
        case .white, .black:
            return HighlightShareCardStyle.frameTopPadding
                + HighlightShareCardStyle.frameBottomPadding
                + HighlightShareCardStyle.frameFooterHeight
        }
    }
}
