//
//  NotionSessionManagerTests.swift
//  LanReadTests
//

import Testing
@testable import LanRead

@MainActor
struct NotionSessionManagerTests {
    @Test
    func restoresConnectedStateFromSecureStore() {
        let secureStore = InMemorySecureStore(
            initialSession: StoredNotionSession(
                accessToken: "token-a",
                botId: "bot-a",
                workspaceId: "workspace-a",
                workspaceName: "Workspace A",
                workspaceIcon: "https://example.com/icon.png"
            )
        )
        let manager = makeManager(secureStore: secureStore)

        #expect(manager.connectionState == .connected(workspaceName: "Workspace A"))
        #expect(manager.accessToken() == "token-a")
    }

    @Test
    func disconnectClearsSecureStoreAndDatabaseMappings() {
        let secureStore = InMemorySecureStore(
            initialSession: StoredNotionSession(
                accessToken: "token-a",
                botId: "bot-a",
                workspaceId: "workspace-a",
                workspaceName: "Workspace A",
                workspaceIcon: nil
            )
        )
        let mappingStore = SpyMappingStore(returnCount: 2)
        let manager = makeManager(secureStore: secureStore, mappingStore: mappingStore)

        manager.disconnect()

        #expect(manager.connectionState == .disconnected)
        #expect(secureStore.storedSession == nil)
        #expect(mappingStore.clearCallCount == 1)
    }

    @Test
    func finalizeOAuthStoresTokenAndTransitionsToConnected() async {
        let secureStore = InMemorySecureStore()
        let exchangeService = MockExchangeService(
            response: NotionOAuthExchangeResponse(
                accessToken: "token-b",
                workspaceId: "workspace-b",
                workspaceName: "Workspace B",
                workspaceIcon: "https://example.com/workspace.png",
                botId: "bot-b"
            )
        )
        let manager = makeManager(
            secureStore: secureStore,
            exchangeService: exchangeService
        )

        await manager.finalizeOAuth(authorizationCode: "valid-code")

        #expect(manager.connectionState == .connected(workspaceName: "Workspace B"))
        #expect(secureStore.storedSession?.accessToken == "token-b")
        #expect(secureStore.storedSession?.workspaceId == "workspace-b")
    }

    @Test
    func clearsMappingsWhenSwitchingWorkspace() {
        let secureStore = InMemorySecureStore(
            initialSession: StoredNotionSession(
                accessToken: "token-a",
                botId: "bot-a",
                workspaceId: "workspace-a",
                workspaceName: "Workspace A",
                workspaceIcon: nil
            )
        )
        let mappingStore = SpyMappingStore(returnCount: 1)
        let manager = makeManager(secureStore: secureStore, mappingStore: mappingStore)

        manager.connect(
            with: NotionOAuthExchangeResponse(
                accessToken: "token-b",
                workspaceId: "workspace-b",
                workspaceName: "Workspace B",
                workspaceIcon: nil,
                botId: "bot-b"
            )
        )

        #expect(manager.connectionState == .connected(workspaceName: "Workspace B"))
        #expect(mappingStore.clearCallCount == 1)
    }
}

private extension NotionSessionManagerTests {
    func makeManager(
        secureStore: InMemorySecureStore,
        exchangeService: MockExchangeService = MockExchangeService(),
        mappingStore: SpyMappingStore = SpyMappingStore(returnCount: 0)
    ) -> NotionSessionManager {
        NotionSessionManager(
            secureStore: secureStore,
            exchangeService: exchangeService,
            mappingStore: mappingStore
        )
    }
}

private final class InMemorySecureStore: NotionSessionSecureStore {
    var storedSession: StoredNotionSession?

    init(initialSession: StoredNotionSession? = nil) {
        self.storedSession = initialSession
    }

    func save(_ session: StoredNotionSession) throws {
        storedSession = session
    }

    func load() throws -> StoredNotionSession? {
        storedSession
    }

    func delete() throws {
        storedSession = nil
    }
}

private final class MockExchangeService: NotionSessionExchangeProviding {
    let response: NotionOAuthExchangeResponse

    init(
        response: NotionOAuthExchangeResponse = NotionOAuthExchangeResponse(
            accessToken: "token-default",
            workspaceId: "workspace-default",
            workspaceName: "Workspace Default",
            workspaceIcon: nil,
            botId: "bot-default"
        )
    ) {
        self.response = response
    }

    func exchangeAuthorizationCode(_ code: String, redirectURI: String) async throws -> NotionOAuthExchangeResponse {
        response
    }
}

private final class SpyMappingStore: NotionDatabaseMappingStoring {
    private(set) var clearCallCount = 0
    private let returnCount: Int

    init(returnCount: Int) {
        self.returnCount = returnCount
    }

    func clearAllMappings() -> Int {
        clearCallCount += 1
        return returnCount
    }
}
