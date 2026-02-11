//
//  NotionSyncConfig.swift
//  LanRead
//

import CoreData
import Foundation

@objc(NotionSyncConfig)
public final class NotionSyncConfig: NSManagedObject {}

extension NotionSyncConfig {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NotionSyncConfig> {
        NSFetchRequest<NotionSyncConfig>(entityName: "NotionSyncConfig")
    }

    @NSManaged public var databaseId: String
    @NSManaged public var containerPageId: String
    @NSManaged public var workspaceName: String
    @NSManaged public var lastSyncedAt: Date?
}

extension NotionSyncConfig: Identifiable {}
