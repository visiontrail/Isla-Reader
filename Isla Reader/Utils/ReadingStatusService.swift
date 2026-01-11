//
//  ReadingStatusService.swift
//  LanRead
//
//  Created by AI Assistant on 2025/12/2.
//

import Foundation
import CoreData

/// Service to manage and update reading statuses automatically
final class ReadingStatusService {
    static let shared = ReadingStatusService()
    
    private init() {}
    
    /// Number of days of inactivity before marking a book as "paused"
    private let pauseThresholdDays: Int = 7
    
    /// Updates reading statuses for all books based on last access time
    /// - Parameter context: The managed object context to use
    func updateAllReadingStatuses(in context: NSManagedObjectContext) {
        DebugLogger.info("ReadingStatusService: Starting status update check")
        
        // Fetch all library items
        let fetchRequest: NSFetchRequest<LibraryItem> = LibraryItem.fetchRequest()
        
        do {
            let libraryItems = try context.fetch(fetchRequest)
            var updatedCount = 0
            
            for item in libraryItems {
                if shouldPauseReading(item) {
                    item.status = .paused
                    updatedCount += 1
                    DebugLogger.info("ReadingStatusService: Updated '\(item.book.displayTitle)' to 'paused' due to inactivity")
                }
            }
            
            // Save if any changes were made
            if updatedCount > 0 {
                try context.save()
                DebugLogger.success("ReadingStatusService: Updated \(updatedCount) book(s) to 'paused' status")
            } else {
                DebugLogger.info("ReadingStatusService: No books need status update")
            }
            
        } catch {
            DebugLogger.error("ReadingStatusService: Failed to update reading statuses: \(error)")
        }
    }
    
    /// Checks if a library item should be marked as paused
    /// - Parameter item: The library item to check
    /// - Returns: True if the item should be marked as paused
    private func shouldPauseReading(_ item: LibraryItem) -> Bool {
        // Only check items that are currently in "reading" status
        guard item.status == .reading else {
            return false
        }
        
        // Check if lastAccessedAt exists
        guard let lastAccessedAt = item.lastAccessedAt else {
            // If no last accessed date, check the reading progress lastReadAt
            if let lastReadAt = item.book.readingProgress?.lastReadAt {
                return isInactive(since: lastReadAt)
            }
            return false
        }
        
        // Check if the book has been inactive for the threshold period
        return isInactive(since: lastAccessedAt)
    }
    
    /// Checks if a date is beyond the inactivity threshold
    /// - Parameter date: The date to check
    /// - Returns: True if the date is older than the pause threshold
    private func isInactive(since date: Date) -> Bool {
        let calendar = Calendar.current
        let daysSinceLastAccess = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        return daysSinceLastAccess >= pauseThresholdDays
    }
    
    /// Updates the reading status for a specific book
    /// - Parameters:
    ///   - book: The book to update
    ///   - context: The managed object context to use
    func updateReadingStatus(for book: Book, in context: NSManagedObjectContext) {
        guard let libraryItem = book.libraryItem else {
            return
        }
        
        if shouldPauseReading(libraryItem) {
            libraryItem.status = .paused
            
            do {
                try context.save()
                DebugLogger.info("ReadingStatusService: Updated '\(book.displayTitle)' to 'paused'")
            } catch {
                DebugLogger.error("ReadingStatusService: Failed to update status: \(error)")
            }
        }
    }
}

