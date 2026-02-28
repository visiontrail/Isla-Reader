//
//  NotionLibrarySchema.swift
//  LanRead
//

import Foundation

enum NotionLibrarySchema {
    static let nameProperty = "Name"
    static let authorProperty = "Author"
    static let readingProgressProperty = "Reading Progress"
    static let readingStatusProperty = "Reading Status"

    private static let readingStatusWantToRead = "Want to Read"
    private static let readingStatusReading = "Reading"
    private static let readingStatusFinished = "Finished"
    private static let readingStatusPaused = "Paused"
    // Notion percent format displays value * 100, so keep 4 digits here for 2 visible decimals.
    private static let readingProgressStorageDecimalPlaces = 4

    static var databaseProperties: Object {
        var properties: Object = [
            nameProperty: .object([
                "title": .object([:])
            ]),
            authorProperty: .object([
                "rich_text": .object([:])
            ])
        ]
        properties.merge(schemaPatchProperties) { current, _ in
            current
        }
        return properties
    }

    // 用于已存在数据库的补丁更新，避免影响既有字段。
    static var schemaPatchProperties: Object {
        [
            readingProgressProperty: .object([
                "number": .object([
                    "format": .string("percent")
                ])
            ]),
            readingStatusProperty: .object([
                "select": .object([
                    "options": .array([
                        .object(["name": .string(readingStatusWantToRead)]),
                        .object(["name": .string(readingStatusReading)]),
                        .object(["name": .string(readingStatusFinished)]),
                        .object(["name": .string(readingStatusPaused)])
                    ])
                ])
            ])
        ]
    }

    static func readingProgressPropertyValue(_ progressPercentage: Double?) -> JSONValue {
        .object([
            "number": .number(normalizedReadingProgress(progressPercentage))
        ])
    }

    static func readingStatusPropertyValue(_ statusRaw: String?) -> JSONValue {
        .object([
            "select": .object([
                "name": .string(readingStatusName(from: statusRaw))
            ])
        ])
    }

    private static func readingStatusName(from statusRaw: String?) -> String {
        guard let statusRaw = statusRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !statusRaw.isEmpty,
              let status = ReadingStatus(rawValue: statusRaw) else {
            return readingStatusWantToRead
        }

        switch status {
        case .wantToRead:
            return readingStatusWantToRead
        case .reading:
            return readingStatusReading
        case .finished:
            return readingStatusFinished
        case .paused:
            return readingStatusPaused
        }
    }

    private static func normalizedReadingProgress(_ progressPercentage: Double?) -> Double {
        guard let progressPercentage, progressPercentage.isFinite else {
            return 0
        }
        let clamped = min(max(progressPercentage, 0), 1)
        let scale = pow(10.0, Double(readingProgressStorageDecimalPlaces))
        return (clamped * scale).rounded() / scale
    }
}
