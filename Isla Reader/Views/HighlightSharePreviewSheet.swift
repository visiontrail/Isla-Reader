//
//  HighlightSharePreviewSheet.swift
//  LanRead
//
//  Created by AI Assistant on 2026/3/2.
//

import SwiftUI
import UIKit
import Photos

struct HighlightSharePreviewSheet: View {
    let cardPayload: HighlightShareCardPayload

    @Environment(\.dismiss) private var dismiss
    @State private var shareSheetPayload: ShareSheetPayload?
    @State private var shareFailedAlert = false
    @State private var downloadAlert: DownloadAlert?
    @State private var selectedFrameStyle: HighlightShareFrameStyle = .none
    @State private var renderedImage: UIImage
    @State private var renderedImageCache: [HighlightShareFrameStyle: UIImage]
    @State private var renderToken = UUID()
    @State private var isRenderingStyle = false

    private struct ShareSheetPayload: Identifiable {
        let id = UUID()
        let activityItems: [Any]
    }

    private struct DownloadAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init(initialImage: UIImage, cardPayload: HighlightShareCardPayload) {
        self.cardPayload = cardPayload
        _renderedImage = State(initialValue: initialImage)
        _renderedImageCache = State(initialValue: [.none: initialImage])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        frameStyleSelector
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        ZStack {
                            Image(uiImage: renderedImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 10)

                            if isRenderingStyle {
                                ProgressView()
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("highlight.share.preview_title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button(action: startShare) {
                        Label(NSLocalizedString("highlight.share.image_button", comment: ""), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: downloadImageToAlbum) {
                        Label(NSLocalizedString("highlight.share.download_button", comment: ""), systemImage: "arrow.down.to.line")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(.ultraThinMaterial)
            }
        }
        .sheet(item: $shareSheetPayload) { payload in
            ActivityShareSheet(activityItems: payload.activityItems) { _, completed, _, error in
                if let error {
                    DebugLogger.error("HighlightSharePreviewSheet: 分享失败", error: error)
                    return
                }
                DebugLogger.info("HighlightSharePreviewSheet: 分享面板结束，completed=\(completed)")
            }
        }
        .alert(NSLocalizedString("highlight.share.generate_failed.title", comment: ""), isPresented: $shareFailedAlert) {
            Button(NSLocalizedString("common.confirm", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("highlight.share.generate_failed.message", comment: ""))
        }
        .alert(item: $downloadAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: "")))
            )
        }
    }

    private var frameStyleSelector: some View {
        HStack(spacing: 10) {
            ForEach(HighlightShareFrameStyle.allCases) { style in
                Button(action: { selectFrameStyle(style) }) {
                    VStack(spacing: 8) {
                        frameStyleGlyph(for: style)
                            .frame(width: 42, height: 52)

                        Text(style.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selectedFrameStyle == style ? Color.red : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRenderingStyle)
            }
        }
    }

    @ViewBuilder
    private func frameStyleGlyph(for style: HighlightShareFrameStyle) -> some View {
        switch style {
        case .none:
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(.systemBackground))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.65), lineWidth: 2)
                Image(systemName: "slash.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        case .white:
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.78))
                    .padding(.horizontal, 5)
                    .padding(.top, 5)
                    .padding(.bottom, 14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
        case .black:
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.97, blue: 0.99))
                    .padding(.horizontal, 5)
                    .padding(.top, 5)
                    .padding(.bottom, 14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func selectFrameStyle(_ style: HighlightShareFrameStyle) {
        guard selectedFrameStyle != style else { return }
        selectedFrameStyle = style

        if let cached = renderedImageCache[style] {
            renderedImage = cached
            return
        }

        isRenderingStyle = true
        let token = UUID()
        renderToken = token

        Task {
            do {
                let image = try await HighlightShareCardRenderer.renderImage(payload: cardPayload, frameStyle: style)
                await MainActor.run {
                    guard renderToken == token else { return }
                    renderedImageCache[style] = image
                    renderedImage = image
                    isRenderingStyle = false
                }
            } catch {
                await MainActor.run {
                    guard renderToken == token else { return }
                    DebugLogger.error("HighlightSharePreviewSheet: 样式渲染失败", error: error)
                    isRenderingStyle = false
                    shareFailedAlert = true
                }
            }
        }
    }

    private func startShare() {
        // 始终分享 UIImage，系统分享面板会提供“保存图片”等图片专用操作。
        let activityItems: [Any] = [renderedImage]

        guard !activityItems.isEmpty else {
            shareFailedAlert = true
            return
        }
        shareSheetPayload = ShareSheetPayload(activityItems: activityItems)
    }

    private func downloadImageToAlbum() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            saveImageToPhotoLibrary()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    handlePhotoAuthorization(newStatus)
                }
            }
        case .denied, .restricted:
            showPhotoPermissionDeniedAlert()
        @unknown default:
            showPhotoPermissionDeniedAlert()
        }
    }

    private func handlePhotoAuthorization(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited:
            saveImageToPhotoLibrary()
        case .denied, .restricted:
            showPhotoPermissionDeniedAlert()
        case .notDetermined:
            showPhotoPermissionDeniedAlert()
        @unknown default:
            showPhotoPermissionDeniedAlert()
        }
    }

    private func saveImageToPhotoLibrary() {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: renderedImage)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    DebugLogger.info("HighlightSharePreviewSheet: 图片已保存到相册")
                    downloadAlert = DownloadAlert(
                        title: NSLocalizedString("highlight.share.save_success.title", comment: ""),
                        message: NSLocalizedString("highlight.share.save_success.message", comment: "")
                    )
                    return
                }

                DebugLogger.error("HighlightSharePreviewSheet: 保存图片到相册失败", error: error)
                downloadAlert = DownloadAlert(
                    title: NSLocalizedString("highlight.share.save_failed.title", comment: ""),
                    message: NSLocalizedString("highlight.share.save_failed.message", comment: "")
                )
            }
        }
    }

    private func showPhotoPermissionDeniedAlert() {
        DebugLogger.warning("HighlightSharePreviewSheet: 相册写入权限不可用")
        downloadAlert = DownloadAlert(
            title: NSLocalizedString("highlight.share.save_failed.title", comment: ""),
            message: NSLocalizedString("highlight.share.photo_permission_denied.message", comment: "")
        )
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: UIActivityViewController.CompletionWithItemsHandler?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = completion
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
