//
//  Book.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import Foundation
import CoreData
import SwiftUI

@objc(Book)
public class Book: NSManagedObject {
    
}

extension Book {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Book> {
        return NSFetchRequest<Book>(entityName: "Book")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var author: String?
    @NSManaged public var language: String?
    @NSManaged public var coverImageData: Data?
    @NSManaged public var filePath: String
    @NSManaged public var fileFormat: String // epub, txt, etc.
    @NSManaged public var fileSize: Int64
    @NSManaged public var checksum: String
    @NSManaged public var totalPages: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var metadata: String? // JSON string for additional metadata
    @NSManaged public var aiSummary: String?
    @NSManaged public var aiKeyPoints: String? // JSON string for key points array
    @NSManaged public var aiSummaryGeneratedAt: Date?
    
    // Relationships
    @NSManaged public var readingProgress: ReadingProgress?
    @NSManaged public var highlights: NSSet?
    @NSManaged public var annotations: NSSet?
    @NSManaged public var libraryItem: LibraryItem?
    
}

// MARK: Generated accessors for highlights
extension Book {
    
    @objc(addHighlightsObject:)
    @NSManaged public func addToHighlights(_ value: Highlight)
    
    @objc(removeHighlightsObject:)
    @NSManaged public func removeFromHighlights(_ value: Highlight)
    
    @objc(addHighlights:)
    @NSManaged public func addToHighlights(_ values: NSSet)
    
    @objc(removeHighlights:)
    @NSManaged public func removeFromHighlights(_ values: NSSet)
    
}

// MARK: Generated accessors for annotations
extension Book {
    
    @objc(addAnnotationsObject:)
    @NSManaged public func addToAnnotations(_ value: Annotation)
    
    @objc(removeAnnotationsObject:)
    @NSManaged public func removeFromAnnotations(_ value: Annotation)
    
    @objc(addAnnotations:)
    @NSManaged public func addToAnnotations(_ values: NSSet)
    
    @objc(removeAnnotations:)
    @NSManaged public func removeFromAnnotations(_ values: NSSet)
    
}

extension Book: Identifiable {
    
    var coverImage: Image? {
        guard let coverImageData = coverImageData,
              let uiImage = UIImage(data: coverImageData) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }
    
    var displayTitle: String {
        return title.isEmpty ? "未知书籍" : title
    }
    
    var displayAuthor: String {
        return author?.isEmpty == false ? author! : "未知作者"
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
}