//
//  LibraryItem.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import Foundation
import CoreData
import SwiftUI

public enum ReadingStatus: String, CaseIterable {
    case wantToRead = "want_to_read"
    case reading = "reading"
    case finished = "finished"
    case paused = "paused"
    
    var displayName: String {
        switch self {
        case .wantToRead:
            return NSLocalizedString("reading.status.want_to_read", comment: "Want to read status")
        case .reading:
            return NSLocalizedString("reading.status.reading", comment: "Currently reading status")
        case .finished:
            return NSLocalizedString("reading.status.finished", comment: "Finished reading status")
        case .paused:
            return NSLocalizedString("reading.status.paused", comment: "Paused reading status")
        }
    }
    
    var displayNameKey: LocalizedStringKey {
        switch self {
        case .wantToRead:
            return LocalizedStringKey("reading.status.want_to_read")
        case .reading:
            return LocalizedStringKey("reading.status.reading")
        case .finished:
            return LocalizedStringKey("reading.status.finished")
        case .paused:
            return LocalizedStringKey("reading.status.paused")
        }
    }
}

@objc(LibraryItem)
public class LibraryItem: NSManagedObject {
    
}

extension LibraryItem {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LibraryItem> {
        return NSFetchRequest<LibraryItem>(entityName: "LibraryItem")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var statusRaw: String
    @NSManaged public var tags: String? // JSON array of tags
    @NSManaged public var isFavorite: Bool
    @NSManaged public var rating: Int16 // 1-5 stars
    @NSManaged public var addedAt: Date
    @NSManaged public var lastAccessedAt: Date?
    @NSManaged public var sortOrder: Int32
    
    // Relationship
    @NSManaged public var book: Book
    
}

extension LibraryItem: Identifiable {
    
    var status: ReadingStatus {
        get {
            return ReadingStatus(rawValue: statusRaw) ?? .wantToRead
        }
        set {
            statusRaw = newValue.rawValue
        }
    }
    
    var tagList: [String] {
        guard let tags = tags,
              let data = tags.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
    }
    
    func setTags(_ newTags: [String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: newTags),
              let jsonString = String(data: data, encoding: .utf8) else {
            tags = nil
            return
        }
        tags = jsonString
    }
    
    var hasRating: Bool {
        return rating > 0
    }
    
    var ratingStars: String {
        guard rating > 0 else { return "" }
        return String(repeating: "★", count: Int(rating)) + String(repeating: "☆", count: 5 - Int(rating))
    }
    
    var isRecentlyAccessed: Bool {
        guard let lastAccessedAt = lastAccessedAt else { return false }
        let calendar = Calendar.current
        return calendar.isDateInToday(lastAccessedAt) || calendar.isDateInYesterday(lastAccessedAt)
    }
    
}