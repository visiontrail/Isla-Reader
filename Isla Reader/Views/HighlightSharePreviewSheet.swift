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
    let image: UIImage
    let fileURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var shareSheetPayload: ShareSheetPayload?
    @State private var shareFailedAlert = false
    @State private var downloadAlert: DownloadAlert?

    private struct ShareSheetPayload: Identifiable {
        let id = UUID()
        let activityItems: [Any]
    }

    private struct DownloadAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 10)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
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

    private func startShare() {
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        DebugLogger.info("HighlightSharePreviewSheet: 点击分享按钮，fileExists=\(fileExists)")
        if !fileExists {
            DebugLogger.warning("HighlightSharePreviewSheet: 分享文件不存在，将继续分享 UIImage")
        }

        // 始终分享 UIImage，系统分享面板会提供“保存图片”等图片专用操作。
        let activityItems: [Any] = [image]

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
            PHAssetChangeRequest.creationRequestForAsset(from: image)
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
