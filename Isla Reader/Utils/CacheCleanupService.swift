//
//  CacheCleanupService.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/3/10.
//

import Foundation
import CoreData

struct CacheUsage {
    let cacheDirectoryBytes: Int64
    let aiSummaryBytes: Int64
    let skimmingSummaryBytes: Int64
    
    var totalBytes: Int64 {
        cacheDirectoryBytes + aiSummaryBytes + skimmingSummaryBytes
    }
}

final class CacheCleanupService {
    static let shared = CacheCleanupService()
    
    private let fileManager: FileManager
    private let skimmingService: SkimmingModeService
    
    init(fileManager: FileManager = .default, skimmingService: SkimmingModeService = .shared) {
        self.fileManager = fileManager
        self.skimmingService = skimmingService
    }
    
    func currentUsage(context: NSManagedObjectContext) async -> CacheUsage {
        let directoryBytes = cacheDirectorySize()
        let coreDataBreakdown = await coreDataUsage(context: context)
        
        return CacheUsage(
            cacheDirectoryBytes: directoryBytes,
            aiSummaryBytes: coreDataBreakdown.aiBytes,
            skimmingSummaryBytes: coreDataBreakdown.skimmingBytes
        )
    }
    
    func clearCaches(context: NSManagedObjectContext) async throws -> CacheUsage {
        DebugLogger.info("CacheCleanupService: 开始清理缓存")
        
        let directoryFreed = try removeCacheDirectoryContents()
        DebugLogger.info("CacheCleanupService: 已删除缓存目录文件 \(directoryFreed) bytes")
        URLCache.shared.removeAllCachedResponses()
        
        let clearedCoreData = try await clearCoreDataCaches(context: context)
        DebugLogger.info("CacheCleanupService: 清理了 Core Data 缓存 ai=\(clearedCoreData.aiBytes) bytes, skimming=\(clearedCoreData.skimmingBytes) bytes")
        
        skimmingService.clearInMemoryCache()
        skimmingService.clearStoredProgress(for: clearedCoreData.bookIds)
        
        let usage = await currentUsage(context: context)
        DebugLogger.success("CacheCleanupService: 清理完成，剩余 \(usage.totalBytes) bytes")
        return usage
    }
    
    static func formattedSize(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Private Helpers
    
    private func cacheDirectoryURL() -> URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    }
    
    private func cacheDirectorySize() -> Int64 {
        guard let cacheURL = cacheDirectoryURL(),
              let enumerator = fileManager.enumerator(
                at: cacheURL,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return 0
        }
        
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
               values.isDirectory == false {
                if let total = values.totalFileAllocatedSize {
                    size += Int64(total)
                } else if let allocated = values.fileAllocatedSize {
                    size += Int64(allocated)
                }
            }
        }
        
        return size
    }
    
    private func removeCacheDirectoryContents() throws -> Int64 {
        let freedBytes = cacheDirectorySize()
        guard let cacheURL = cacheDirectoryURL() else { return freedBytes }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
            for url in contents {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    DebugLogger.warning("CacheCleanupService: 无法删除缓存文件 \(url.lastPathComponent) - \(error.localizedDescription)")
                }
            }
        } catch {
            DebugLogger.error("CacheCleanupService: 读取缓存目录失败 - \(error.localizedDescription)")
            throw error
        }
        
        return freedBytes
    }
    
    private func coreDataUsage(context: NSManagedObjectContext) async -> (aiBytes: Int64, skimmingBytes: Int64) {
        await context.perform {
            let request: NSFetchRequest<Book> = Book.fetchRequest()
            let books = (try? context.fetch(request)) ?? []
            var aiBytes: Int64 = 0
            var skimmingBytes: Int64 = 0
            
            for book in books {
                aiBytes += Int64(book.aiSummary?.lengthOfBytes(using: .utf8) ?? 0)
                aiBytes += Int64(book.aiKeyPoints?.lengthOfBytes(using: .utf8) ?? 0)
                skimmingBytes += Int64(book.skimmingSummaries?.lengthOfBytes(using: .utf8) ?? 0)
            }
            
            return (aiBytes, skimmingBytes)
        }
    }
    
    private func clearCoreDataCaches(context: NSManagedObjectContext) async throws -> (aiBytes: Int64, skimmingBytes: Int64, bookIds: [UUID]) {
        try await context.perform {
            let request: NSFetchRequest<Book> = Book.fetchRequest()
            let books = try context.fetch(request)
            var aiBytes: Int64 = 0
            var skimmingBytes: Int64 = 0
            var bookIds: [UUID] = []
            
            for book in books {
                bookIds.append(book.id)
                
                if let summary = book.aiSummary {
                    aiBytes += Int64(summary.lengthOfBytes(using: .utf8))
                    book.aiSummary = nil
                }
                
                if let keyPoints = book.aiKeyPoints {
                    aiBytes += Int64(keyPoints.lengthOfBytes(using: .utf8))
                    book.aiKeyPoints = nil
                }
                
                if book.aiSummaryGeneratedAt != nil {
                    book.aiSummaryGeneratedAt = nil
                }
                
                if let skimming = book.skimmingSummaries {
                    skimmingBytes += Int64(skimming.lengthOfBytes(using: .utf8))
                    book.skimmingSummaries = nil
                }
            }
            
            if context.hasChanges {
                try context.save()
            }
            
            return (aiBytes, skimmingBytes, bookIds)
        }
    }
}
