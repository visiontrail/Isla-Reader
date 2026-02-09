//
//  NotionSessionManagerTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct NotionSessionManagerTests {
    @Test
    func storesAndRetrievesPageMapping() {
        let defaults = makeIsolatedDefaults()
        let store = NotionDatabaseMappingStore(defaults: defaults)
        let bookID = UUID()

        store.setPageId("page-123", for: bookID)

        #expect(store.pageId(for: bookID) == "page-123")
    }

    @Test
    func clearAllMappingsRemovesStoredEntries() {
        let defaults = makeIsolatedDefaults()
        let store = NotionDatabaseMappingStore(defaults: defaults)

        store.setPageId("page-a", for: UUID())
        store.setPageId("page-b", for: UUID())

        let removedCount = store.clearAllMappings()

        #expect(removedCount == 2)

        let persisted = defaults.dictionary(forKey: "notion.database_mapping.v1") as? [String: String]
        #expect((persisted ?? [:]).isEmpty)
    }
}

private extension NotionSessionManagerTests {
    func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "NotionSessionManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
