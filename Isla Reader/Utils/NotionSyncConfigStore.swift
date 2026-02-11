//
//  NotionSyncConfigStore.swift
//  LanRead
//

import CoreData
import Foundation

struct NotionSyncConfigSnapshot: Equatable, Sendable {
    let databaseId: String
    let containerPageId: String
    let workspaceName: String
    let lastSyncedAt: Date?
}

protocol NotionSyncConfigStoring: Sendable {
    func load() -> NotionSyncConfigSnapshot?
    func save(databaseId: String, containerPageId: String, workspaceName: String, lastSyncedAt: Date?) throws
    func updateLastSyncedAt(_ date: Date) throws
    func clear() throws
}

final class CoreDataNotionSyncConfigStore: @unchecked Sendable, NotionSyncConfigStoring {
    static let shared = CoreDataNotionSyncConfigStore(container: PersistenceController.shared.container)

    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func load() -> NotionSyncConfigSnapshot? {
        do {
            return try performOnBackgroundContext { context in
                let request = NotionSyncConfig.fetchRequest()
                request.fetchLimit = 1
                request.sortDescriptors = [NSSortDescriptor(key: "workspaceName", ascending: true)]

                guard let config = try context.fetch(request).first else {
                    return nil
                }

                return NotionSyncConfigSnapshot(
                    databaseId: config.databaseId,
                    containerPageId: config.containerPageId,
                    workspaceName: config.workspaceName,
                    lastSyncedAt: config.lastSyncedAt
                )
            }
        } catch {
            DebugLogger.error("NotionSyncConfigStore: failed to load config", error: error)
            return nil
        }
    }

    func save(databaseId: String, containerPageId: String, workspaceName: String, lastSyncedAt: Date?) throws {
        _ = try performOnBackgroundContext { context in
            let request = NotionSyncConfig.fetchRequest()
            request.fetchLimit = 1

            let config = try context.fetch(request).first ?? NotionSyncConfig(context: context)
            config.databaseId = databaseId
            config.containerPageId = containerPageId
            config.workspaceName = workspaceName
            config.lastSyncedAt = lastSyncedAt

            if context.hasChanges {
                try context.save()
            }
        }
    }

    func updateLastSyncedAt(_ date: Date) throws {
        _ = try performOnBackgroundContext { context in
            let request = NotionSyncConfig.fetchRequest()
            request.fetchLimit = 1
            guard let config = try context.fetch(request).first else {
                return
            }

            config.lastSyncedAt = date
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func clear() throws {
        _ = try performOnBackgroundContext { context in
            let request = NotionSyncConfig.fetchRequest()
            let configs = try context.fetch(request)

            for config in configs {
                context.delete(config)
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func performOnBackgroundContext<T>(_ work: @escaping (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>!
        let context = container.newBackgroundContext()

        context.performAndWait {
            do {
                result = .success(try work(context))
            } catch {
                result = .failure(error)
            }
        }

        return try result.get()
    }
}

struct NotionLogoutCleanupResult: Sendable {
    let clearedBookMappingsCount: Int
    let removedQueueItemsCount: Int
}

protocol NotionSyncDataCleaning: Sendable {
    func clearForLogout() throws -> NotionLogoutCleanupResult
}

final class NotionSyncDataCleaner: @unchecked Sendable, NotionSyncDataCleaning {
    static let shared = NotionSyncDataCleaner(container: PersistenceController.shared.container)

    private let container: NSPersistentContainer
    private let configStore: NotionSyncConfigStoring

    init(
        container: NSPersistentContainer,
        configStore: NotionSyncConfigStoring = CoreDataNotionSyncConfigStore.shared
    ) {
        self.container = container
        self.configStore = configStore
    }

    func clearForLogout() throws -> NotionLogoutCleanupResult {
        let result = try performOnBackgroundContext { [self] context in
            let books = try self.fetchMappedBooks(in: context)
            for book in books {
                book.notionPageId = nil
            }
            let clearedBookMappingsCount = books.count

            let removedQueueItemsCount = try self.batchDeleteCount(entityName: "SyncQueueItem", context: context)
            _ = try self.batchDeleteCount(entityName: "SyncQueue", context: context)
            _ = try self.batchDeleteCount(entityName: "BookMapping", context: context)

            if context.hasChanges {
                try context.save()
            }

            return NotionLogoutCleanupResult(
                clearedBookMappingsCount: clearedBookMappingsCount,
                removedQueueItemsCount: removedQueueItemsCount
            )
        }

        try configStore.clear()
        return result
    }

    private func fetchMappedBooks(in context: NSManagedObjectContext) throws -> [Book] {
        let request = Book.fetchRequest()
        request.predicate = NSPredicate(format: "notionPageId != nil")
        return try context.fetch(request)
    }

    private func batchDeleteCount(entityName: String, context: NSManagedObjectContext) throws -> Int {
        let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let count = try context.count(for: countRequest)
        guard count > 0 else { return 0 }

        let deleteFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetchRequest)
        _ = try context.execute(deleteRequest)
        return count
    }

    private func performOnBackgroundContext<T>(_ work: @escaping (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>!
        let context = container.newBackgroundContext()

        context.performAndWait {
            do {
                result = .success(try work(context))
            } catch {
                result = .failure(error)
            }
        }

        return try result.get()
    }
}
