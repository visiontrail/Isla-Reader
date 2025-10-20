//
//  Annotation.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import Foundation
import CoreData

@objc(Annotation)
public class Annotation: NSManagedObject {
    
}

extension Annotation {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Annotation> {
        return NSFetchRequest<Annotation>(entityName: "Annotation")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var content: String
    @NSManaged public var position: String // JSON string for position
    @NSManaged public var chapter: String?
    @NSManaged public var pageNumber: Int32
    @NSManaged public var associatedText: String? // Text that this annotation refers to
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    
    // Relationship
    @NSManaged public var book: Book
    
}

extension Annotation: Identifiable {
    
    var displayContent: String {
        let maxLength = 200
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "..."
        }
        return content
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    var hasAssociatedText: Bool {
        return associatedText?.isEmpty == false
    }
    
}