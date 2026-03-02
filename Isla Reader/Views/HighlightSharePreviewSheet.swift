//
//  HighlightSharePreviewSheet.swift
//  LanRead
//
//  Created by AI Assistant on 2026/3/2.
//

import SwiftUI
import UIKit

struct HighlightSharePreviewSheet: View {
    let image: UIImage
    let fileURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var presentingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var shareFailedAlert = false

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
                VStack(spacing: 10) {
                    Button(action: startShare) {
                        Label(NSLocalizedString("highlight.share.image_button", comment: ""), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $presentingShareSheet) {
            ActivityShareSheet(activityItems: shareItems) { _, completed, _, error in
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
    }

    private func startShare() {
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        DebugLogger.info("HighlightSharePreviewSheet: 点击分享按钮，fileExists=\(fileExists)")
        if fileExists {
            shareItems = [fileURL]
        } else {
            // 如果临时文件意外缺失，降级为直接分享内存中的图片，避免按钮无响应。
            shareItems = [image]
            DebugLogger.warning("HighlightSharePreviewSheet: 分享文件不存在，降级为分享 UIImage")
        }

        guard !shareItems.isEmpty else {
            shareFailedAlert = true
            return
        }
        presentingShareSheet = true
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
