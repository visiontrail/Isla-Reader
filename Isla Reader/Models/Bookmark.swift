//
//  Bookmark.swift
//  LanRead
//
//  Created by AI Assistant on 2026/1/14.
//

import Foundation
import CoreData

@objc(Bookmark)
public class Bookmark: NSManagedObject {
    
}

extension Bookmark {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Bookmark> {
        NSFetchRequest<Bookmark>(entityName: "Bookmark")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var chapterIndex: Int32
    @NSManaged public var pageIndex: Int32
    @NSManaged public var chapterTitle: String?
    @NSManaged public var createdAt: Date
    
    // Relationship
    @NSManaged public var book: Book
    
}

struct BookmarkLocation: Hashable {
    let chapterIndex: Int
    let pageIndex: Int
    let chapterTitle: String?
}

extension Bookmark: Identifiable {
    
    var location: BookmarkLocation {
        BookmarkLocation(
            chapterIndex: Int(chapterIndex),
            pageIndex: Int(pageIndex),
            chapterTitle: chapterTitle
        )
    }
    
    var displayTitle: String {
        if let chapterTitle = chapterTitle, !chapterTitle.isEmpty {
            return chapterTitle
        }
        return String(format: NSLocalizedString("bookmark.chapter_format", comment: "Bookmark chapter"), Int(chapterIndex) + 1)
    }
    
    var displayPage: String {
        String(format: NSLocalizedString("bookmark.page_format", comment: "Bookmark page number"), Int(pageIndex) + 1)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
}
