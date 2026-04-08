import AppKit
import BatchModels
import BatchSupport
import Foundation
import SwiftUI

public struct ShareCardRenderPayload: Equatable, Sendable {
    public var highlightText: String
    public var noteText: String?
    public var profileDisplayName: String
    public var profileAvatarData: Data?
    public var bookTitle: String
    public var chapterTitle: String
    public var footerText: String
    public var footerSubtitleText: String
    public var coverImageData: Data?
    public var generatedAt: Date
    public var timeZoneIdentifier: String?

    public var attributionLine: String {
        "— \(bookTitle) · \(chapterTitle)"
    }

    public init(
        highlightText: String,
        noteText: String?,
        profileDisplayName: String,
        profileAvatarData: Data?,
        bookTitle: String,
        chapterTitle: String,
        footerText: String,
        footerSubtitleText: String,
        coverImageData: Data?,
        generatedAt: Date = Date(),
        timeZoneIdentifier: String? = nil
    ) {
        self.highlightText = Self.normalizedHighlightText(highlightText)
        self.noteText = Self.normalizedNoteText(noteText)
        self.profileDisplayName = Self.normalizedProfileDisplayName(profileDisplayName)
        self.profileAvatarData = profileAvatarData
        self.bookTitle = Self.normalizedBookTitle(bookTitle)
        self.chapterTitle = Self.normalizedChapterTitle(chapterTitle)
        self.footerText = footerText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.footerSubtitleText = footerSubtitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.coverImageData = coverImageData
        self.generatedAt = generatedAt
        self.timeZoneIdentifier = Self.normalizedTimeZoneIdentifier(timeZoneIdentifier)
    }

    private static func normalizedHighlightText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    private static func normalizedNoteText(_ noteText: String?) -> String? {
        guard let noteText = noteText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !noteText.isEmpty else {
            return nil
        }
        return noteText
    }

    private static func normalizedProfileDisplayName(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Reader" : trimmed
    }

    private static func normalizedBookTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private static func normalizedChapterTitle(_ chapterTitle: String) -> String {
        let trimmed = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Chapter" : trimmed
    }

    private static func normalizedTimeZoneIdentifier(_ timeZoneIdentifier: String?) -> String? {
        guard let timeZoneIdentifier = timeZoneIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !timeZoneIdentifier.isEmpty,
              TimeZone(identifier: timeZoneIdentifier) != nil else {
            return nil
        }
        return timeZoneIdentifier
    }
}

private enum ShareCardRenderMode {
    case fullLength
    case truncated

    static let fallbackOrder: [ShareCardRenderMode] = [.fullLength, .truncated]

    var shouldAttemptFallback: Bool {
        switch self {
        case .fullLength:
            return true
        case .truncated:
            return false
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

    func proposedHeight(for frameStyle: ShareCardStyle) -> CGFloat? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return ShareCardLayout.baselineHeight + frameStyle.additionalHeight
        }
    }

    func fixedHeight(for frameStyle: ShareCardStyle) -> CGFloat? {
        switch self {
        case .fullLength:
            return nil
        case .truncated:
            return ShareCardLayout.baselineHeight + frameStyle.additionalHeight
        }
    }

    func minimumHeight(for frameStyle: ShareCardStyle) -> CGFloat? {
        switch self {
        case .fullLength:
            return ShareCardLayout.baselineHeight + frameStyle.additionalHeight
        case .truncated:
            return nil
        }
    }
}

private enum ShareCardCoverPlacement {
    case inlineTrailing
    case bottomFill
}

private struct ShareCardLayoutProfile {
    let coverPlacement: ShareCardCoverPlacement
    let bottomCoverSize: CGSize

    static let inlineDefault = ShareCardLayoutProfile(
        coverPlacement: .inlineTrailing,
        bottomCoverSize: .zero
    )
}

private enum ShareCardLayout {
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

private extension ShareCardStyle {
    var additionalHeight: CGFloat {
        switch self {
        case .none:
            return 0
        case .white, .black:
            return ShareCardLayout.frameTopPadding
                + ShareCardLayout.frameBottomPadding
                + ShareCardLayout.frameFooterHeight
        }
    }
}

public struct ShareCardRenderer: Sendable {
    public init() {}

    public func render(payload: ShareCardRenderPayload, style: ShareCardStyle, to outputURL: URL) throws {
        let pngData = try renderPNGData(payload: payload, style: style)

        do {
            let directory = outputURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: outputURL, options: .atomic)
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.ioFailure("Failed writing share card image at \(outputURL.path): \(error.localizedDescription)")
        }
    }

    private func renderPNGData(payload: ShareCardRenderPayload, style: ShareCardStyle) throws -> Data {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try renderPNGDataOnMainThread(payload: payload, style: style)
            }
        }

        var result: Result<Data, Error>?
        DispatchQueue.main.sync {
            result = Result {
                try MainActor.assumeIsolated {
                    try renderPNGDataOnMainThread(payload: payload, style: style)
                }
            }
        }

        guard let result else {
            throw BatchError.runtime("ShareCardRenderer failed to receive render result.")
        }
        return try result.get()
    }

    @MainActor
    private func renderPNGDataOnMainThread(payload: ShareCardRenderPayload, style: ShareCardStyle) throws -> Data {
        var lastError: Error?
        for mode in ShareCardRenderMode.fallbackOrder {
            do {
                let image = try renderImage(payload: payload, mode: mode, style: style)
                return try makePNGData(image: image)
            } catch {
                lastError = error
                if !mode.shouldAttemptFallback {
                    throw error
                }
            }
        }

        throw lastError ?? BatchError.runtime("Failed to render share card image.")
    }

    @MainActor
    private func renderImage(
        payload: ShareCardRenderPayload,
        mode: ShareCardRenderMode,
        style: ShareCardStyle
    ) throws -> NSImage {
        let layoutProfile = resolveLayoutProfile(payload: payload, mode: mode, style: style)
        let renderer = ImageRenderer(
            content: ShareCardView(
                payload: payload,
                mode: mode,
                layoutProfile: layoutProfile,
                frameStyle: style
            )
        )
        renderer.scale = ShareCardLayout.exportScale
        renderer.proposedSize = ProposedViewSize(
            width: ShareCardLayout.cardWidth,
            height: mode.proposedHeight(for: style)
        )

        guard let image = renderer.nsImage else {
            throw BatchError.runtime("Failed to render share card image for style=\(style.rawValue).")
        }
        try validateRenderedImage(image, mode: mode)
        return image
    }

    @MainActor
    private func resolveLayoutProfile(
        payload: ShareCardRenderPayload,
        mode: ShareCardRenderMode,
        style: ShareCardStyle
    ) -> ShareCardLayoutProfile {
        guard mode == .fullLength else {
            return .inlineDefault
        }

        let fixedContentHeight = estimatedFixedContentHeight(payload: payload, mode: mode, style: style)
        let remainingWhitespace = ShareCardLayout.baselineHeight - fixedContentHeight
        guard remainingWhitespace > ShareCardLayout.coverBottomFillTriggerWhitespace else {
            return .inlineDefault
        }

        let bottomCoverHeight = min(
            max(
                remainingWhitespace * ShareCardLayout.coverBottomFillFactor,
                ShareCardLayout.bottomCoverMinHeight
            ),
            ShareCardLayout.bottomCoverMaxHeight
        )
        return ShareCardLayoutProfile(
            coverPlacement: .bottomFill,
            bottomCoverSize: CGSize(
                width: bottomCoverHeight * ShareCardLayout.coverAspectRatio,
                height: bottomCoverHeight
            )
        )
    }

    @MainActor
    private func estimatedFixedContentHeight(
        payload: ShareCardRenderPayload,
        mode: ShareCardRenderMode,
        style: ShareCardStyle
    ) -> CGFloat {
        let highlightFont = NSFont.systemFont(ofSize: 58, weight: .semibold)
        let attributionFont = NSFont.systemFont(ofSize: 33, weight: .semibold)
        let noteFont = NSFont.systemFont(ofSize: 36, weight: .regular)
        let noteNameFont = NSFont.systemFont(ofSize: 24, weight: .semibold)

        let highlightHeight = estimatedTextHeight(
            "“\(payload.highlightText)”",
            width: ShareCardLayout.contentWidth,
            font: highlightFont,
            lineSpacing: 10,
            lineLimit: mode.highlightLineLimit
        )
        let attributionHeight = estimatedTextHeight(
            payload.attributionLine,
            width: ShareCardLayout.contentWidth
                - ShareCardLayout.inlineCoverWidth
                - ShareCardLayout.coverInlineSpacing,
            font: attributionFont,
            lineSpacing: 0,
            lineLimit: mode.attributionLineLimit
        )

        let topBlockHeight = highlightHeight
            + ShareCardLayout.topBlockSpacing
            + max(attributionHeight, ShareCardLayout.inlineCoverHeight)

        let noteCardHeight: CGFloat
        if let noteText = payload.noteText {
            let noteNameHeight = estimatedTextHeight(
                payload.profileDisplayName,
                width: ShareCardLayout.noteBubbleContentWidth,
                font: noteNameFont,
                lineSpacing: 0,
                lineLimit: 1
            )
            let noteHeight = estimatedTextHeight(
                sanitizedForMeasurement(noteText),
                width: ShareCardLayout.noteBubbleContentWidth,
                font: noteFont,
                lineSpacing: 8,
                lineLimit: mode.noteLineLimit
            )
            let bubbleHeight = noteNameHeight
                + ShareCardLayout.noteNameBubbleSpacing
                + noteHeight
                + (ShareCardLayout.noteBubbleVerticalPadding * 2)
            noteCardHeight = max(ShareCardLayout.noteAvatarSize, bubbleHeight)
        } else {
            noteCardHeight = 0
        }

        let stackSpacingCount = payload.noteText == nil ? 2 : 3
        let effectiveSpacingCount = style == .none ? stackSpacingCount : max(stackSpacingCount - 1, 0)
        return (ShareCardLayout.verticalPadding * 2)
            + topBlockHeight
            + noteCardHeight
            + (ShareCardLayout.stackSpacing * CGFloat(effectiveSpacingCount))
            + (style == .none ? ShareCardLayout.footerHeight : 0)
    }

    @MainActor
    private func estimatedTextHeight(
        _ text: String,
        width: CGFloat,
        font: NSFont,
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
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let measuredHeight = ceil(bounding.height)
        guard let lineLimit else {
            return measuredHeight
        }

        let singleLine = ceil(font.ascender - font.descender + font.leading)
        let maxHeight = (singleLine * CGFloat(lineLimit))
            + (lineSpacing * CGFloat(max(lineLimit - 1, 0)))
        return min(measuredHeight, maxHeight)
    }

    private func validateRenderedImage(_ image: NSImage, mode: ShareCardRenderMode) throws {
        let pixelSize = imagePixelSize(image)
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            throw BatchError.runtime("Rendered share card has invalid pixel size.")
        }

        if mode == .truncated {
            return
        }

        let pixelCount = pixelSize.width * pixelSize.height
        guard pixelSize.height <= ShareCardLayout.maxFullLengthPixelHeight,
              pixelCount <= ShareCardLayout.maxFullLengthPixelCount else {
            throw BatchError.runtime("Rendered share card is too large in full-length mode.")
        }
    }

    private func imagePixelSize(_ image: NSImage) -> CGSize {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return image.size
        }
        return CGSize(width: CGFloat(bitmap.pixelsWide), height: CGFloat(bitmap.pixelsHigh))
    }

    private func makePNGData(image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw BatchError.runtime("Failed to encode rendered share card to PNG.")
        }
        return data
    }

    private func sanitizedForMeasurement(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
    }
}

private struct ShareCardView: View {
    let payload: ShareCardRenderPayload
    let mode: ShareCardRenderMode
    let layoutProfile: ShareCardLayoutProfile
    let frameStyle: ShareCardStyle

    private var coverImage: NSImage? {
        guard let coverImageData = payload.coverImageData else {
            return nil
        }
        return NSImage(data: coverImageData)
    }

    private var footerTimestampText: String {
        Self.frameTimestampFormatter.formattedString(
            from: payload.generatedAt,
            timeZoneIdentifier: payload.timeZoneIdentifier
        )
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
        .frame(width: ShareCardLayout.cardWidth, height: mode.fixedHeight(for: frameStyle))
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
                        footerAppIcon(size: 36, cornerRadius: 8)

                        Text(payload.footerText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 12)

                    Text(footerTimestampText)
                        .lineLimit(1)
                }
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(frameStyle == .white ? Color.black.opacity(0.78) : Color.white.opacity(0.88))
                .frame(height: ShareCardLayout.frameFooterHeight)
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, ShareCardLayout.frameHorizontalPadding)
            .padding(.top, ShareCardLayout.frameTopPadding)
            .padding(.bottom, ShareCardLayout.frameBottomPadding)
        }
    }

    private func cardContent(showLegacyFooter: Bool) -> some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 36) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("“\(payload.highlightText)”")
                        .font(.system(size: 58, weight: .semibold, design: .serif))
                        .foregroundStyle(highlightTextColor)
                        .lineSpacing(10)
                        .lineLimit(mode.highlightLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .bottom, spacing: 24) {
                        Text(payload.attributionLine)
                            .font(.system(size: 33, weight: .semibold, design: .serif))
                            .foregroundStyle(attributionTextColor)
                            .lineLimit(mode.attributionLineLimit)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if layoutProfile.coverPlacement == .inlineTrailing {
                            coverView(
                                width: ShareCardLayout.inlineCoverWidth,
                                height: ShareCardLayout.inlineCoverHeight
                            )
                        }
                    }
                }

                if let noteText = payload.noteText {
                    HStack(alignment: .top, spacing: ShareCardLayout.noteRowSpacing) {
                        profileAvatarView(size: ShareCardLayout.noteAvatarSize)

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
                        footerAppIcon(size: 44, cornerRadius: 10)

                        Text(payload.footerText)
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.56))
                            .lineLimit(1)

                        if !payload.footerSubtitleText.isEmpty {
                            Text(payload.footerSubtitleText)
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.56))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 78)
        }
    }

    @ViewBuilder
    private func footerAppIcon(size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let appIcon = Self.footerAppIconImage {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(frameStyle == .white ? Color.black.opacity(0.16) : Color.white.opacity(0.22), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(frameStyle == .white ? Color.black.opacity(0.08) : Color.white.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(
                    Text("L")
                        .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                        .foregroundStyle(frameStyle == .white ? Color.black.opacity(0.78) : Color.white.opacity(0.88))
                )
        }
    }

    @ViewBuilder
    private func profileAvatarView(size: CGFloat) -> some View {
        Group {
            if let avatarData = payload.profileAvatarData,
               let avatarImage = NSImage(data: avatarData) {
                Image(nsImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(defaultAvatarBackgroundGradient)
                    Text(avatarInitial)
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
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
        VStack(alignment: .leading, spacing: ShareCardLayout.noteNameBubbleSpacing) {
            Text(payload.profileDisplayName)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(noteDisplayNameColor)
                .lineLimit(1)

            Text(sanitizedMarkdown(noteText))
                .font(.system(size: 36, weight: .regular, design: .default))
                .foregroundStyle(noteTextColor)
                .lineSpacing(8)
                .lineLimit(mode.noteLineLimit)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ShareCardLayout.noteBubbleHorizontalPadding)
        .padding(.vertical, ShareCardLayout.noteBubbleVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(noteBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(noteBorderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func coverView(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let coverImage {
                Image(nsImage: coverImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(coverPlaceholderColor)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(coverPlaceholderIconColor)
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

    private func sanitizedMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
    }

    private static let footerAppIconImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "LanReadAppIcon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    private static let frameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private extension DateFormatter {
    func formattedString(from date: Date, timeZoneIdentifier: String?) -> String {
        let originalTimeZone = timeZone
        if let timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            self.timeZone = timeZone
        } else {
            self.timeZone = .current
        }
        defer { self.timeZone = originalTimeZone }
        return string(from: date)
    }
}
