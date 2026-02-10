//
//  BookMapping.swift
//  LanRead
//

import CoreData
import Foundation

@objc(BookMapping)
public class BookMapping: NSManagedObject {}

extension BookMapping {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BookMapping> {
        NSFetchRequest<BookMapping>(entityName: "BookMapping")
    }

    @NSManaged public var bookID: String
    @NSManaged public var notionPageID: String
    @NSManaged public var updatedAt: Date
}

extension BookMapping: Identifiable {}
