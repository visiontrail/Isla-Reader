//
//  NotionBookSyncer.swift
//  LanRead
//

import CoreData
import Foundation

struct BookInfo: Equatable, Sendable {
    let id: String
    let title: String
    let author: String
    let readingStatusRaw: String?
    let readingProgressPercentage: Double?

    init(
        id: String,
        title: String,
        author: String,
        readingStatusRaw: String? = nil,
        readingProgressPercentage: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.readingStatusRaw = readingStatusRaw
        self.readingProgressPercentage = readingProgressPercentage
    }
}

enum NotionBookSyncError: LocalizedError, Equatable {
    case missingDatabaseID
    case invalidBookID
    case invalidCreatePageResponse

    var errorDescription: String? {
        switch self {
        case .missingDatabaseID:
            return NSLocalizedString("notion.sync.error.database_not_initialized", comment: "")
        case .invalidBookID:
            return NSLocalizedString("library.book.error.invalid_id", comment: "")
        case .invalidCreatePageResponse:
            return NSLocalizedString("notion.page.error.missing_page_id", comment: "")
        }
    }
}

protocol NotionBookSyncAPI {
    func updateDatabase(databaseId: String, properties: Object) async throws -> NotionObject
    func createPage(databaseId: String, properties: Object, children: [Block]) async throws -> NotionObject
}

extension NotionAPIClient: NotionBookSyncAPI {}

protocol BookMappingStoring {
    func notionPageID(for bookID: String) throws -> String?
    func saveMapping(bookID: String, notionPageID: String) throws
}

final class CoreDataBookMappingStore: BookMappingStoring {
    static let shared = CoreDataBookMappingStore(container: PersistenceController.shared.container)

    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func notionPageID(for bookID: String) throws -> String? {
        try performOnBackgroundContext { context in
            guard let bookUUID = UUID(uuidString: bookID) else {
                return nil
            }

            let bookRequest = Book.fetchRequest()
            bookRequest.fetchLimit = 1
            bookRequest.predicate = NSPredicate(format: "id == %@", bookUUID as CVarArg)

            guard let book = try context.fetch(bookRequest).first else {
                return nil
            }

            if let mappedPageID = book.notionPageId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !mappedPageID.isEmpty {
                return mappedPageID
            }

            let legacyRequest = BookMapping.fetchRequest()
            legacyRequest.fetchLimit = 1
            legacyRequest.predicate = NSPredicate(format: "bookID == %@", bookID)
            let legacyMapping = try context.fetch(legacyRequest).first
            guard let legacyPageID = legacyMapping?.notionPageID.trimmingCharacters(in: .whitespacesAndNewlines),
                  !legacyPageID.isEmpty else {
                return nil
            }

            // 兼容老版本映射：命中后回填到 Book.notionPageId。
            book.notionPageId = legacyPageID
            if context.hasChanges {
                try context.save()
            }
            return legacyPageID
        }
    }

    func saveMapping(bookID: String, notionPageID: String) throws {
        _ = try performOnBackgroundContext { context in
            guard let bookUUID = UUID(uuidString: bookID) else {
                return
            }

            let request = Book.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", bookUUID as CVarArg)
            guard let book = try context.fetch(request).first else {
                return
            }

            book.notionPageId = notionPageID
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

actor NotionBookSyncer {
    typealias DatabaseIDProvider = @Sendable () async -> String?

    private let notionClient: NotionBookSyncAPI
    private let mappingStore: BookMappingStoring
    private let databaseIDProvider: DatabaseIDProvider

    private var syncingBookIDs = Set<String>()
    private var waitingContinuations: [String: [CheckedContinuation<String, Error>]] = [:]
    private var schemaEnsuredDatabaseIDs = Set<String>()

    init(
        notionClient: NotionBookSyncAPI = NotionAPIClient(),
        mappingStore: BookMappingStoring = CoreDataBookMappingStore.shared,
        databaseIDProvider: @escaping DatabaseIDProvider = {
            await MainActor.run { NotionSessionManager.shared.notionDatabaseID }
        }
    ) {
        self.notionClient = notionClient
        self.mappingStore = mappingStore
        self.databaseIDProvider = databaseIDProvider
    }

    func sync(book: BookInfo) async throws -> String {
        let normalizedBookID = book.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBookID.isEmpty else {
            throw NotionBookSyncError.invalidBookID
        }

        if syncingBookIDs.contains(normalizedBookID) {
            return try await withCheckedThrowingContinuation { continuation in
                waitingContinuations[normalizedBookID, default: []].append(continuation)
            }
        }

        syncingBookIDs.insert(normalizedBookID)
        do {
            let pageID = try await performSync(book: book, normalizedBookID: normalizedBookID)
            completeSync(for: normalizedBookID, result: .success(pageID))
            return pageID
        } catch {
            completeSync(for: normalizedBookID, result: .failure(error))
            throw error
        }
    }

    private func performSync(book: BookInfo, normalizedBookID: String) async throws -> String {
        let databaseID = try await resolveDatabaseID()
        await ensureDatabaseSchemaIfNeeded(databaseID: databaseID)

        if let cachedPageID = try mappingStore.notionPageID(for: normalizedBookID), !cachedPageID.isEmpty {
            DebugLogger.info("NotionBookSyncer hit local mapping cache bookID=\(normalizedBookID)")
            return cachedPageID
        }

        let properties = Self.makeProperties(for: book)
        let created = try await createPageWithCompatibility(
            databaseID: databaseID,
            properties: properties,
            fallbackProperties: Self.makeLegacyProperties(for: book)
        )

        guard let pageID = created["id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pageID.isEmpty else {
            throw NotionBookSyncError.invalidCreatePageResponse
        }

        try mappingStore.saveMapping(bookID: normalizedBookID, notionPageID: pageID)
        DebugLogger.success("NotionBookSyncer created Notion page bookID=\(normalizedBookID) pageID=\(pageID)")
        return pageID
    }

    private func ensureDatabaseSchemaIfNeeded(databaseID: String) async {
        guard !schemaEnsuredDatabaseIDs.contains(databaseID) else {
            return
        }

        do {
            _ = try await notionClient.updateDatabase(
                databaseId: databaseID,
                properties: NotionLibrarySchema.schemaPatchProperties
            )
            schemaEnsuredDatabaseIDs.insert(databaseID)
            DebugLogger.info("NotionBookSyncer ensured database schema databaseID=\(databaseID)")
        } catch {
            DebugLogger.warning(
                "NotionBookSyncer failed to ensure database schema databaseID=\(databaseID) reason=\(error.localizedDescription)"
            )
        }
    }

    private func resolveDatabaseID() async throws -> String {
        let databaseID = (await databaseIDProvider())?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let databaseID, !databaseID.isEmpty else {
            throw NotionBookSyncError.missingDatabaseID
        }
        return databaseID
    }

    private func completeSync(for bookID: String, result: Result<String, Error>) {
        syncingBookIDs.remove(bookID)
        let continuations = waitingContinuations.removeValue(forKey: bookID) ?? []

        for continuation in continuations {
            switch result {
            case .success(let pageID):
                continuation.resume(returning: pageID)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    private func createPageWithCompatibility(
        databaseID: String,
        properties: Object,
        fallbackProperties: Object
    ) async throws -> NotionObject {
        do {
            return try await notionClient.createPage(
                databaseId: databaseID,
                properties: properties,
                children: Self.initialPageChildren
            )
        } catch let error as NotionAPIError {
            guard Self.shouldRetryWithLegacyProperties(error) else {
                throw error
            }
            DebugLogger.warning("NotionBookSyncer create page retrying with legacy properties databaseID=\(databaseID)")
            return try await notionClient.createPage(
                databaseId: databaseID,
                properties: fallbackProperties,
                children: Self.initialPageChildren
            )
        }
    }

    private static func makeProperties(for book: BookInfo) -> Object {
        var properties = makeLegacyProperties(for: book)
        properties[NotionLibrarySchema.readingProgressProperty] = NotionLibrarySchema.readingProgressPropertyValue(
            book.readingProgressPercentage
        )
        properties[NotionLibrarySchema.readingStatusProperty] = NotionLibrarySchema.readingStatusPropertyValue(
            book.readingStatusRaw
        )
        return properties
    }

    private static func makeLegacyProperties(for book: BookInfo) -> Object {
        let title = normalizedText(book.title, fallback: "Untitled")
        let author = normalizedText(book.author, fallback: "Unknown")

        return [
            NotionLibrarySchema.nameProperty: .object([
                "title": richTextArray(content: title)
            ]),
            NotionLibrarySchema.authorProperty: .object([
                "rich_text": richTextArray(content: author)
            ])
        ]
    }

    private static func shouldRetryWithLegacyProperties(_ error: NotionAPIError) -> Bool {
        guard case .serverError(_, let message) = error else {
            return false
        }

        let lowered = message?.lowercased() ?? ""
        guard lowered.contains("property"), lowered.contains("does not exist") else {
            return false
        }

        return lowered.contains(NotionLibrarySchema.readingProgressProperty)
            || lowered.contains(NotionLibrarySchema.readingStatusProperty)
    }

    private static var initialPageChildren: [Block] {
        [
            headingBlock(content: "📝 Notes"),
            dividerBlock()
        ]
    }

    private static func headingBlock(content: String) -> Block {
        [
            "object": .string("block"),
            "type": .string("heading_1"),
            "heading_1": .object([
                "rich_text": richTextArray(content: content)
            ])
        ]
    }

    private static func dividerBlock() -> Block {
        [
            "object": .string("block"),
            "type": .string("divider"),
            "divider": .object([:])
        ]
    }

    private static func richTextArray(content: String) -> JSONValue {
        .array([
            .object([
                "type": .string("text"),
                "text": .object([
                    "content": .string(content)
                ])
            ])
        ])
    }

    private static func normalizedText(_ rawText: String, fallback: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
