//
//  SyncQueueItem.swift
//  LanRead
//

import CoreData
import Foundation

enum SyncQueueItemType: String, Codable, Sendable {
    case highlight
    case note
}

enum SyncQueueItemStatus: String, Sendable {
    case pending
    case inProgress
    case failed
}

@objc(SyncQueueItem)
public final class SyncQueueItem: NSManagedObject {}

extension SyncQueueItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SyncQueueItem> {
        NSFetchRequest<SyncQueueItem>(entityName: "SyncQueueItem")
    }

    @NSManaged public var id: UUID
    @NSManaged public var targetBookId: String
    @NSManaged public var type: String
    @NSManaged public var payload: Data
    @NSManaged public var status: String
    @NSManaged public var retryCount: Int16
    @NSManaged public var createdAt: Date

    var queueType: SyncQueueItemType? {
        get { SyncQueueItemType(rawValue: type) }
        set { type = newValue?.rawValue ?? SyncQueueItemType.highlight.rawValue }
    }

    var queueStatus: SyncQueueItemStatus {
        get { SyncQueueItemStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }
}

extension SyncQueueItem: Identifiable {}
