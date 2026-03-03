//
//  BundledSampleBookSeeder.swift
//  LanRead
//
//  Created by AI Assistant on 2026/3/3.
//

import Foundation
import CoreData

final class BundledSampleBookSeeder {
    static let shared = BundledSampleBookSeeder()

    private let defaults: UserDefaults
    private let importService: BookImportService

    private let seededKey = "bundled_sample_book_seeded_v1"
    private let sampleFileName = "LanRead_Getting_Started_Multilingual"

    private init(defaults: UserDefaults = .standard, importService: BookImportService = .shared) {
        self.defaults = defaults
        self.importService = importService
    }

    @MainActor
    func seedIfNeeded(context: NSManagedObjectContext) async {
        guard !defaults.bool(forKey: seededKey) else {
            DebugLogger.info("BundledSampleBookSeeder: 已标记为完成，跳过预置示例书")
            return
        }

        guard let sampleURL = bundledSampleBookURL() else {
            DebugLogger.error("BundledSampleBookSeeder: 未找到内置示例书资源")
            return
        }

        do {
            _ = try await importService.importBook(from: sampleURL, context: context)
            defaults.set(true, forKey: seededKey)
            DebugLogger.success("BundledSampleBookSeeder: 预置示例书导入成功")
        } catch BookImportError.bookAlreadyExists(let title) {
            defaults.set(true, forKey: seededKey)
            DebugLogger.info("BundledSampleBookSeeder: 示例书已存在，标记完成 - \(title)")
        } catch {
            DebugLogger.error("BundledSampleBookSeeder: 导入示例书失败 - \(error.localizedDescription)")
        }
    }

    private func bundledSampleBookURL() -> URL? {
        if let url = Bundle.main.url(
            forResource: sampleFileName,
            withExtension: "epub",
            subdirectory: "SampleBooks"
        ) {
            return url
        }

        if let url = Bundle.main.url(forResource: sampleFileName, withExtension: "epub") {
            return url
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let enumerator = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "\(sampleFileName).epub" {
                return url
            }
        }
        return nil
    }
}
