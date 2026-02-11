//
//  NotionSessionManager.swift
//  LanRead
//

import Combine
import Foundation
import SwiftUI

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(workspaceName: String)
    case error(String)
}

struct NotionParentPageOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String?
}

enum NotionInitializationError: LocalizedError, Equatable {
    case permissionDenied
    case emptyPageList
    case invalidDatabaseResponse

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return NSLocalizedString("notion.init.error.permission_denied", comment: "")
        case .emptyPageList:
            return NSLocalizedString("notion.init.error.no_pages", comment: "")
        case .invalidDatabaseResponse:
            return NSLocalizedString("notion.init.error.invalid_database_response", comment: "")
        }
    }
}

@MainActor
final class NotionSessionManager: ObservableObject {
    static let shared = NotionSessionManager()

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var workspaceIcon: String?
    @Published private(set) var notionDatabaseID: String?
    @Published private(set) var isInitialized = false

    private let authService: NotionAuthService
    private let notionClient: NotionAPIClient
    private let mappingStore: NotionDatabaseMappingStoring
    private let initializationStore: NotionLibraryInitializationStoring
    private let syncConfigStore: NotionSyncConfigStoring
    private let syncDataCleaner: NotionSyncDataCleaning
    private var cancellables = Set<AnyCancellable>()

    init(
        authService: NotionAuthService = .shared,
        notionClient: NotionAPIClient = NotionAPIClient(),
        mappingStore: NotionDatabaseMappingStoring = NotionDatabaseMappingStore.shared,
        initializationStore: NotionLibraryInitializationStoring = NotionLibraryInitializationStore.shared,
        syncConfigStore: NotionSyncConfigStoring = CoreDataNotionSyncConfigStore.shared,
        syncDataCleaner: NotionSyncDataCleaning = NotionSyncDataCleaner.shared
    ) {
        self.authService = authService
        self.notionClient = notionClient
        self.mappingStore = mappingStore
        self.initializationStore = initializationStore
        self.syncConfigStore = syncConfigStore
        self.syncDataCleaner = syncDataCleaner
        bindAuthState()
        refreshFromStorage()
    }

    var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    func accessToken() -> String? {
        authService.accessToken
    }

    var isConnecting: Bool {
        if case .connecting = connectionState {
            return true
        }
        return false
    }

    var workspaceName: String? {
        if case .connected(let workspaceName) = connectionState {
            return workspaceName
        }
        return nil
    }

    func startAuthorization() {
        authService.startAuthorization()
    }

    func disconnect() {
        let clearedMappingsCount = mappingStore.clearAllMappings()
        initializationStore.clear()
        let cleanupResult: NotionLogoutCleanupResult
        do {
            cleanupResult = try syncDataCleaner.clearForLogout()
        } catch {
            cleanupResult = NotionLogoutCleanupResult(clearedBookMappingsCount: 0, removedQueueItemsCount: 0)
            DebugLogger.error("Notion logout cleanup failed", error: error)
        }
        notionDatabaseID = nil
        isInitialized = false
        authService.disconnect()
        if clearedMappingsCount > 0 {
            DebugLogger.info("Notion mapping store cleared count=\(clearedMappingsCount)")
        }
        if cleanupResult.clearedBookMappingsCount > 0 || cleanupResult.removedQueueItemsCount > 0 {
            DebugLogger.info(
                "Notion sync data cleared mappings=\(cleanupResult.clearedBookMappingsCount) queueItems=\(cleanupResult.removedQueueItemsCount)"
            )
        }
    }

    func fetchParentPagesForInitialization() async throws -> [NotionParentPageOption] {
        let filter: Object = [
            "property": .string("object"),
            "value": .string("page")
        ]

        let response = try await notionClient.search(query: "", filter: filter)
        let pages = Self.parseParentPages(from: response)

        guard !pages.isEmpty else {
            throw NotionInitializationError.emptyPageList
        }

        return pages
    }

    func initializeLibraryDatabase(parentPageID: String) async throws {
        let schema: Object = [
            "title": .array([
                .object([
                    "type": .string("text"),
                    "text": .object([
                        "content": .string("📚 LanRead Library")
                    ])
                ])
            ]),
            "is_inline": .bool(true),
            "properties": .object([
                "Name": .object([
                    "title": .object([:])
                ]),
                "BookID": .object([
                    "rich_text": .object([:])
                ]),
                "Author": .object([
                    "rich_text": .object([:])
                ]),
                "Last Synced": .object([
                    "date": .object([:])
                ])
            ])
        ]

        do {
            let response = try await notionClient.createDatabase(parentPageId: parentPageID, schema: schema)
            let databaseID = response["id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !databaseID.isEmpty else {
                throw NotionInitializationError.invalidDatabaseResponse
            }

            initializationStore.save(databaseID: databaseID, workspaceID: authService.workspaceID)
            try? syncConfigStore.save(
                databaseId: databaseID,
                containerPageId: parentPageID,
                workspaceName: workspaceName ?? "",
                lastSyncedAt: nil
            )
            notionDatabaseID = databaseID
            isInitialized = true
            DebugLogger.success("Notion initialization completed databaseID=\(databaseID)")
        } catch let error as NotionAPIError {
            if Self.isPermissionDenied(error) {
                throw NotionInitializationError.permissionDenied
            }
            throw error
        }
    }

    func clearErrorIfNeeded() {
        authService.clearErrorIfNeeded()
    }

    func refreshFromStorage() {
        workspaceIcon = authService.workspaceIcon
        connectionState = Self.mapState(authService.state)
        refreshInitializationState()
    }

    private func bindAuthState() {
        authService.$state
            .sink { [weak self] state in
                guard let self else { return }
                self.connectionState = Self.mapState(state)
                self.refreshInitializationState()
            }
            .store(in: &cancellables)

        authService.$workspaceIcon
            .sink { [weak self] icon in
                self?.workspaceIcon = icon
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notionAccessTokenExpired)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAccessTokenExpired()
                }
            }
            .store(in: &cancellables)
    }

    private func handleAccessTokenExpired() {
        guard isConnected || isConnecting else {
            return
        }
        disconnect()
    }

    private func refreshInitializationState() {
        guard isConnected else {
            notionDatabaseID = nil
            isInitialized = false
            return
        }

        if let syncConfig = syncConfigStore.load(),
           !syncConfig.databaseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notionDatabaseID = syncConfig.databaseId
            isInitialized = true
            return
        }

        let state = initializationStore.load(workspaceID: authService.workspaceID)
        notionDatabaseID = state.databaseID
        isInitialized = state.isInitialized
    }

    private static func mapState(_ state: NotionAuthState) -> ConnectionState {
        switch state {
        case .idle:
            return .disconnected
        case .authenticating, .finalizing:
            return .connecting
        case .connected(let workspaceName):
            return .connected(workspaceName: workspaceName)
        case .error(let message):
            return .error(message)
        }
    }

    private static func isPermissionDenied(_ error: NotionAPIError) -> Bool {
        guard case .serverError(let statusCode, let message) = error else {
            return false
        }

        if statusCode == 403 {
            return true
        }

        if statusCode == 404 {
            return true
        }

        let loweredMessage = message?.lowercased() ?? ""
        return loweredMessage.contains("permission")
            || loweredMessage.contains("capab")
            || loweredMessage.contains("forbidden")
    }

    private static func parseParentPages(from response: NotionObject) -> [NotionParentPageOption] {
        guard let rawResults = response["results"]?.arrayValue else {
            return []
        }

        return rawResults.compactMap { value in
            guard let page = value.objectValue else {
                return nil
            }

            guard page["object"]?.stringValue == "page" else {
                return nil
            }

            guard let pageID = page["id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pageID.isEmpty else {
                return nil
            }

            let title = extractedPageTitle(from: page)
            let url = page["url"]?.stringValue

            return NotionParentPageOption(
                id: pageID,
                title: title,
                subtitle: url,
                icon: extractedPageIcon(from: page)
            )
        }
    }

    private static func extractedPageTitle(from page: NotionObject) -> String {
        if let properties = page["properties"]?.objectValue {
            for property in properties.values {
                guard let propertyObject = property.objectValue,
                      propertyObject["type"]?.stringValue == "title",
                      let titleArray = propertyObject["title"]?.arrayValue else {
                    continue
                }

                let text = extractRichText(from: titleArray)
                if !text.isEmpty {
                    return text
                }
            }
        }

        return NSLocalizedString("notion.init.page.untitled", comment: "")
    }

    private static func extractedPageIcon(from page: NotionObject) -> String? {
        guard let icon = page["icon"]?.objectValue,
              let iconType = icon["type"]?.stringValue else {
            return nil
        }

        switch iconType {
        case "emoji":
            return icon["emoji"]?.stringValue
        case "external":
            return icon["external"]?.objectValue?["url"]?.stringValue
        case "file":
            return icon["file"]?.objectValue?["url"]?.stringValue
        default:
            return nil
        }
    }

    private static func extractRichText(from richText: [JSONValue]) -> String {
        let text = richText.compactMap { item in
            guard let itemObject = item.objectValue else {
                return nil
            }
            if let plainText = itemObject["plain_text"]?.stringValue, !plainText.isEmpty {
                return plainText
            }

            return itemObject["text"]?.objectValue?["content"]?.stringValue
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }
}

protocol NotionDatabaseMappingStoring {
    func pageId(for bookId: UUID) -> String?
    func setPageId(_ pageId: String, for bookId: UUID)
    func removePageId(for bookId: UUID)
    @discardableResult
    func clearAllMappings() -> Int
}

final class NotionDatabaseMappingStore: NotionDatabaseMappingStoring {
    static let shared = NotionDatabaseMappingStore()

    private let defaults: UserDefaults
    private let storageKey = "notion.database_mapping.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pageId(for bookId: UUID) -> String? {
        mappings[bookId.uuidString]
    }

    func setPageId(_ pageId: String, for bookId: UUID) {
        var updated = mappings
        updated[bookId.uuidString] = pageId
        defaults.set(updated, forKey: storageKey)
    }

    func removePageId(for bookId: UUID) {
        var updated = mappings
        updated.removeValue(forKey: bookId.uuidString)
        defaults.set(updated, forKey: storageKey)
    }

    @discardableResult
    func clearAllMappings() -> Int {
        let count = mappings.count
        defaults.removeObject(forKey: storageKey)
        return count
    }

    private var mappings: [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }
}

struct NotionInitializationState: Equatable {
    let databaseID: String?
    let isInitialized: Bool
}

protocol NotionLibraryInitializationStoring {
    func load(workspaceID: String?) -> NotionInitializationState
    func save(databaseID: String, workspaceID: String?)
    func clear()
}

final class NotionLibraryInitializationStore: NotionLibraryInitializationStoring {
    static let shared = NotionLibraryInitializationStore()

    private let defaults: UserDefaults
    private let databaseIDKey = "notion.database_id.v1"
    private let isInitializedKey = "notion.is_initialized.v1"
    private let workspaceIDKey = "notion.initialized_workspace_id.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(workspaceID: String?) -> NotionInitializationState {
        let storedWorkspaceID = defaults.string(forKey: workspaceIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWorkspaceID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let storedWorkspaceID, !storedWorkspaceID.isEmpty,
           let normalizedWorkspaceID, !normalizedWorkspaceID.isEmpty,
           storedWorkspaceID != normalizedWorkspaceID {
            clear()
            return NotionInitializationState(databaseID: nil, isInitialized: false)
        }

        let databaseID = defaults.string(forKey: databaseIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isInitialized = defaults.bool(forKey: isInitializedKey)

        guard isInitialized, let databaseID, !databaseID.isEmpty else {
            return NotionInitializationState(databaseID: nil, isInitialized: false)
        }

        return NotionInitializationState(databaseID: databaseID, isInitialized: true)
    }

    func save(databaseID: String, workspaceID: String?) {
        defaults.set(databaseID, forKey: databaseIDKey)
        defaults.set(true, forKey: isInitializedKey)

        let normalizedWorkspaceID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizedWorkspaceID.isEmpty {
            defaults.removeObject(forKey: workspaceIDKey)
        } else {
            defaults.set(normalizedWorkspaceID, forKey: workspaceIDKey)
        }
    }

    func clear() {
        defaults.removeObject(forKey: databaseIDKey)
        defaults.removeObject(forKey: isInitializedKey)
        defaults.removeObject(forKey: workspaceIDKey)
    }
}
