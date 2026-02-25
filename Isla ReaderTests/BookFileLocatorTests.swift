//
//  BookFileLocatorTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct BookFileLocatorTests {
    @Test
    func resolvesExistingRegularFilePath() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try Data("fixture".utf8).write(to: tempFile, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let resolution = BookFileLocator.resolveFileURL(from: tempFile.path)
        #expect(resolution != nil)
        #expect(resolution?.url.path == tempFile.path)
        #expect(resolution?.preferredStoredPath == tempFile.lastPathComponent)
    }

    @Test
    func rejectsDirectoryPath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let resolution = BookFileLocator.resolveFileURL(from: tempDirectory.path)
        #expect(resolution == nil)
    }

    @Test
    func rejectsRootDirectoryPath() {
        let resolution = BookFileLocator.resolveFileURL(from: "/")
        #expect(resolution == nil)
    }
}
