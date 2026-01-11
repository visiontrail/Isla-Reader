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
        let directURL = URL(fileURLWithPath: storedPath)
        
        if fileManager.fileExists(atPath: directURL.path) {
            return (directURL, directURL.lastPathComponent)
        }
        
        let fileName = directURL.lastPathComponent
        guard !fileName.isEmpty else { return nil }
        
        guard let booksDirectory = booksDirectory(fileManager: fileManager) else { return nil }
        let fallbackURL = booksDirectory.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fallbackURL.path) {
            return (fallbackURL, fileName)
        }
        
        return nil
    }
    
    /// Returns the app's `Documents/Books` directory URL.
    static func booksDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Books")
    }
}
