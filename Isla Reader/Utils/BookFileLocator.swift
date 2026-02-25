//
//  BookFileLocator.swift
//  LanRead
//
//  Created by AI Assistant on 2025/2/3.
//

import Foundation

struct BookFileLocator {
    /// Resolve a stored file path (absolute or just file name) to an existing URL.
    /// Returns the resolved URL plus the preferred persisted path (file name) if found.
    static func resolveFileURL(from storedPath: String,
                               fileManager: FileManager = .default) -> (url: URL, preferredStoredPath: String)? {
        let normalizedPath = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return nil }

        let directURL = URL(fileURLWithPath: normalizedPath)
        if isReadableFile(at: directURL, fileManager: fileManager) {
            return (directURL, directURL.lastPathComponent)
        }

        let fileName = directURL.lastPathComponent
        guard !fileName.isEmpty else { return nil }

        guard let booksDirectory = booksDirectory(fileManager: fileManager) else { return nil }
        let fallbackURL = booksDirectory.appendingPathComponent(fileName)

        if isReadableFile(at: fallbackURL, fileManager: fileManager) {
            return (fallbackURL, fileName)
        }

        return nil
    }
    
    /// Returns the app's `Documents/Books` directory URL.
    static func booksDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Books")
    }

    private static func isReadableFile(at url: URL, fileManager: FileManager) -> Bool {
        let standardizedPath = url.standardizedFileURL.path
        guard standardizedPath != "/" else { return false }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDirectory) else {
            return false
        }

        return !isDirectory.boolValue
    }
}
