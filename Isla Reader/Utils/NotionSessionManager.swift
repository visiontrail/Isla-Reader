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

@MainActor
final class NotionSessionManager: ObservableObject {
    static let shared = NotionSessionManager()

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var workspaceIcon: String?

    private let authService: NotionAuthService
    private var cancellables = Set<AnyCancellable>()

    init(authService: NotionAuthService = .shared) {
        self.authService = authService
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

    func disconnect() {
        authService.disconnect()
    }

    func refreshFromStorage() {
        workspaceIcon = authService.workspaceIcon
        connectionState = Self.mapState(authService.state)
    }

    private func bindAuthState() {
        authService.$state
            .sink { [weak self] state in
                self?.connectionState = Self.mapState(state)
            }
            .store(in: &cancellables)

        authService.$workspaceIcon
            .sink { [weak self] icon in
                self?.workspaceIcon = icon
            }
            .store(in: &cancellables)
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
