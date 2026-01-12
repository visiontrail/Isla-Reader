//
//  DataResetService.swift
//  LanRead
//
//  Created by AI Assistant on 2025/3/15.
//

import CoreData
import Foundation

struct DataResetResult {
    let removedBookCount: Int
    let freedBytes: Int64
    
    var formattedFreedSize: String {
        CacheCleanupService.formattedSize(from: freedBytes)
    }
}

final class DataResetService {
    static let shared = DataResetService()
    
    private let fileManager: FileManager
    private let cacheCleanupService: CacheCleanupService
    private let skimmingService: SkimmingModeService
    
    init(fileManager: FileManager = .default,
         cacheCleanupService: CacheCleanupService = .shared,
         skimmingService: SkimmingModeService = .shared) {
        self.fileManager = fileManager
        self.cacheCleanupService = cacheCleanupService
        self.skimmingService = skimmingService
    }
    
    func wipeAllData(context: NSManagedObjectContext) async throws -> DataResetResult {
        DebugLogger.info("DataResetService: 开始清除所有数据")
        
        let bookIds = await fetchBookIds(context: context)
        let initialCacheUsage = await cacheCleanupService.currentUsage(context: context)
        
        let bookFiles = try removeAllBookFiles()
        let deletedObjects = try await deleteAllEntities(context: context)
        let cacheUsage = try await cacheCleanupService.clearCaches(context: context)
        let freedCacheBytes = max(Int64(0), initialCacheUsage.totalBytes - cacheUsage.totalBytes)
        
        clearUserDefaults(bookIds: bookIds)
        await resetSettings()
        
        let totalFreed = bookFiles.freedBytes + freedCacheBytes
        DebugLogger.success("DataResetService: 已删除 \(bookIds.count) 本书，释放 \(totalFreed) bytes，删除 Core Data 对象 \(deletedObjects) 个")
        
        return DataResetResult(
            removedBookCount: bookIds.count,
            freedBytes: totalFreed
        )
    }
    
    private func fetchBookIds(context: NSManagedObjectContext) async -> [UUID] {
        await context.perform {
            let request: NSFetchRequest<Book> = Book.fetchRequest()
            let books = (try? context.fetch(request)) ?? []
            return books.map { $0.id }
        }
    }
    
    private func deleteAllEntities(context: NSManagedObjectContext) async throws -> Int {
        guard let coordinator = context.persistentStoreCoordinator else {
            DebugLogger.warning("DataResetService: 缺少 persistentStoreCoordinator，跳过 Core Data 清理")
            return 0
        }
        
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.persistentStoreCoordinator = coordinator
        
        let deletedObjectIDs = try await backgroundContext.perform {
            let entityNames = [
                "Annotation",
                "Bookmark",
                "Highlight",
                "ReadingProgress",
                "LibraryItem",
                "Book"
            ]
            var deletedIDs: [NSManagedObjectID] = []
            
            for name in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: name)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeObjectIDs
                
                if let result = try backgroundContext.execute(deleteRequest) as? NSBatchDeleteResult,
                   let objectIDs = result.result as? [NSManagedObjectID] {
                    deletedIDs.append(contentsOf: objectIDs)
                }
            }
            
            try backgroundContext.save()
            return deletedIDs
        }
        
        await context.perform {
            guard !deletedObjectIDs.isEmpty else { return }
            let changes = [NSDeletedObjectsKey: deletedObjectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            context.reset()
        }

        return deletedObjectIDs.count
    }
    
    private func removeAllBookFiles() throws -> (removedFiles: Int, freedBytes: Int64) {
        guard let directory = BookFileLocator.booksDirectory(fileManager: fileManager) else {
            DebugLogger.warning("DataResetService: 未能解析书籍目录路径")
            return (0, 0)
        }
        guard fileManager.fileExists(atPath: directory.path) else {
            DebugLogger.info("DataResetService: 书籍目录不存在，无需删除文件")
            return (0, 0)
        }
        
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )
        var removedFiles = 0
        var freedBytes: Int64 = 0
        
        for url in contents {
            let size = fileSize(at: url)
            do {
                try fileManager.removeItem(at: url)
                removedFiles += 1
                freedBytes += size
            } catch {
                DebugLogger.warning("DataResetService: 无法删除书籍文件 \(url.lastPathComponent) - \(error.localizedDescription)")
            }
        }
        
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            DebugLogger.warning("DataResetService: 无法移除 Books 目录 - \(error.localizedDescription)")
        }
        
        return (removedFiles, freedBytes)
    }
    
    private func fileSize(at url: URL) -> Int64 {
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
            if let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                return Int64(size)
            }
        }
        return 0
    }
    
    private func clearUserDefaults(bookIds: [UUID]) {
        let defaults = UserDefaults.standard
        for key in AppSettings.persistedKeys {
            defaults.removeObject(forKey: key)
        }
        
        for id in bookIds {
            defaults.removeObject(forKey: "skimming_last_chapter_\(id.uuidString)")
        }
        
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("skimming_last_chapter_") {
            defaults.removeObject(forKey: key)
        }
        
        defaults.synchronize()
    }
    
    @MainActor
    private func resetSettings() {
        skimmingService.clearInMemoryCache()
        skimmingService.clearAllStoredProgress()
        AppSettings.shared.resetToDefaults()
    }
}
