//
//  SyncQueue.swift
//  LanRead
//

import CoreData
import Foundation

@objc(SyncQueue)
public final class SyncQueue: NSManagedObject {}

extension SyncQueue {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SyncQueue> {
        NSFetchRequest<SyncQueue>(entityName: "SyncQueue")
    }

    @NSManaged public var id: UUID
    @NSManaged public var operationType: String
    @NSManaged public var payload: String
    @NSManaged public var statusRaw: String
    @NSManaged public var retryCount: Int32
    @NSManaged public var nextAttemptAt: Date
    @NSManaged public var lastError: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
}

extension SyncQueue: Identifiable {}
