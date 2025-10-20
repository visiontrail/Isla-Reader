//
//  ReadingProgress.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import Foundation
import CoreData

@objc(ReadingProgress)
public class ReadingProgress: NSManagedObject {
    
}

extension ReadingProgress {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ReadingProgress> {
        return NSFetchRequest<ReadingProgress>(entityName: "ReadingProgress")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var currentPage: Int32
    @NSManaged public var currentChapter: String?
    @NSManaged public var currentPosition: String? // JSON string for detailed position
    @NSManaged public var progressPercentage: Double
    @NSManaged public var lastReadAt: Date
    @NSManaged public var totalReadingTime: Int64 // in seconds
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    
    // Relationship
    @NSManaged public var book: Book
    
}

extension ReadingProgress: Identifiable {
    
    var formattedProgress: String {
        return String(format: "%.1f%%", progressPercentage * 100)
    }
    
    var formattedReadingTime: String {
        let hours = totalReadingTime / 3600
        let minutes = (totalReadingTime % 3600) / 60
        
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }
    
    var isRecentlyRead: Bool {
        let calendar = Calendar.current
        return calendar.isDateInToday(lastReadAt) || calendar.isDateInYesterday(lastReadAt)
    }
    
}