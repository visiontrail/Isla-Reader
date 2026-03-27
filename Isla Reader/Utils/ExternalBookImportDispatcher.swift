//
//  ExternalBookImportDispatcher.swift
//  LanRead
//
//  Created by Codex on 2026/3/27.
//

import Foundation
import UniformTypeIdentifiers

enum ExternalBookImportDispatcher {
    static let didReceiveBookURL = Notification.Name("ExternalBookImportDispatcher.didReceiveBookURL")
    private static let bookURLUserInfoKey = "bookURL"

    static func isSupportedBookURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if url.pathExtension.lowercased() == "epub" {
            return true
        }

        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .epub)
        }

        return false
    }

    static func post(url: URL) {
        NotificationCenter.default.post(
            name: didReceiveBookURL,
            object: nil,
            userInfo: [bookURLUserInfoKey: url]
        )
    }

    static func extractURL(from notification: Notification) -> URL? {
        notification.userInfo?[bookURLUserInfoKey] as? URL
    }
}
