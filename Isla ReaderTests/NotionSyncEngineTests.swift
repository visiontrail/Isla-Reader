//
//  NotionSyncEngineTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct NotionSyncEngineTests {
    @Test
    func processesTenPendingTasksWhenNotionAndNetworkReady() async throws {
        let store = InMemorySyncQueueStore()
        for index in 0..<10 {
            store.seed(
                task: makeTask(
                    operationType: .highlight,
                    retryCount: 0,
                    highlightText: "highlight \(index)",
                    noteContent: nil
                )
            )
        }

        let appender = MockAppender()
        let snapshotStore = MockHighlightSnapshotStore()
        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender,
            highlightSnapshotStore: snapshotStore
        )

        await processor.setNetworkAvailable(true)
        await processor.setNotionReady(true)

        #expect(store.pendingCount() == 0)
        #expect(await appender.replaceCallCount() == 10)
    }

    @Test
    func rateLimitPausesQueueUsingRetryAfter() async throws {
        let store = InMemorySyncQueueStore()
        store.seed(
            task: makeTask(
                operationType: .note,
                retryCount: 0,
                highlightText: "source",
                noteContent: "note content"
            )
        )
        store.seed(
            task: makeTask(
                operationType: .highlight,
                retryCount: 0,
                highlightText: "second highlight",
                noteContent: nil
            )
        )

        let appender = MockAppender(mode: .rateLimited(retryAfter: 3))
        let snapshotStore = MockHighlightSnapshotStore()
        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender,
            highlightSnapshotStore: snapshotStore
        )

        await processor.setNetworkAvailable(true)
        await processor.setNotionReady(true)

        let failures = store.failureRecords()
        #expect(failures.count == 1)
        #expect(failures.first?.retryCount == 1)
        #expect(failures.first?.shouldRetry == true)
    }

    @Test
    func networkFailureUsesExponentialBackoff() async throws {
        let store = InMemorySyncQueueStore()
        store.seed(
            task: makeTask(
                operationType: .highlight,
                retryCount: 0,
                highlightText: "network case",
                noteContent: nil
            )
        )

        let appender = MockAppender(mode: .networkFailure)
        let snapshotStore = MockHighlightSnapshotStore()
        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender,
            highlightSnapshotStore: snapshotStore
        )

        await processor.setNetworkAvailable(true)
        await processor.setNotionReady(true)

        let failures = store.failureRecords()
        #expect(failures.count == 1)
        #expect(failures.first?.retryCount == 1)
        #expect(failures.first?.shouldRetry == true)
    }

    @Test
    func archivedAncestorErrorTriggersLibraryRebuildFlow() async throws {
        let store = InMemorySyncQueueStore()
        store.seed(
            task: makeTask(
                operationType: .highlight,
                retryCount: 0,
                highlightText: "needs rebuild",
                noteContent: nil
            )
        )

        let appender = MockAppender(
            mode: .serverError(
                statusCode: 400,
                message: "Can't edit page on block with an archived ancestor."
            )
        )
        let snapshotStore = MockHighlightSnapshotStore()
        let rebuildTracker = RebuildTracker()

        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender,
            highlightSnapshotStore: snapshotStore,
            libraryRebuildRetryDelay: 60,
            libraryRebuildHandler: { reason in
                await rebuildTracker.record(reason: reason)
                return true
            }
        )

        await processor.setNetworkAvailable(true)
        await processor.setNotionReady(true)

        #expect(await rebuildTracker.count() == 1)
        let failures = store.failureRecords()
        #expect(failures.count == 1)
        #expect(failures.first?.retryCount == 1)
        #expect(failures.first?.shouldRetry == true)
    }
}

private func makeTask(
    operationType: NotionSyncOperationType,
    retryCount: Int16,
    highlightText: String?,
    noteContent: String?
) -> NotionSyncQueueTask {
    NotionSyncQueueTask(
        id: UUID(),
        operationType: operationType,
        payload: NotionSyncPayload(
            bookID: UUID().uuidString,
            bookTitle: "Test Book",
            bookAuthor: "Test Author",
            bookReadingStatusRaw: nil,
            bookProgressPercentage: nil,
            chapter: "Chapter 1",
            highlightText: highlightText,
            noteContent: noteContent,
            eventDate: Date()
        ),
        retryCount: retryCount
    )
}

private final class InMemorySyncQueueStore: @unchecked Sendable, NotionSyncQueueStoring {
    struct FailureRecord {
        let id: UUID
        let retryCount: Int16
        let shouldRetry: Bool
        let message: String
    }

    private let queue = DispatchQueue(label: "NotionSyncEngineTests.InMemorySyncQueueStore")
    private var tasks: [NotionSyncQueueTask] = []
    private var failures: [FailureRecord] = []

    func seed(task: NotionSyncQueueTask) {
        queue.sync {
            tasks.append(task)
        }
    }

    func fetchNextPendingTask() throws -> NotionSyncQueueTask? {
        queue.sync {
            guard let index = tasks.indices.first else {
                return nil
            }
            return tasks[index]
        }
    }

    func resetInProgressTasks() throws {}

    func markTaskSynced(id: UUID) throws {
        queue.sync {
            tasks.removeAll { $0.id == id }
        }
    }

    func markTaskFailed(id: UUID, retryCount: Int16, shouldRetry: Bool, message: String) throws {
        queue.sync {
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
            let current = tasks[index]
            let updated = NotionSyncQueueTask(
                id: current.id,
                operationType: current.operationType,
                payload: current.payload,
                retryCount: retryCount
            )

            if shouldRetry {
                tasks[index] = updated
            } else {
                tasks.remove(at: index)
            }

            failures.append(
                FailureRecord(
                    id: id,
                    retryCount: retryCount,
                    shouldRetry: shouldRetry,
                    message: message
                )
            )
        }
    }

    func pendingCount() -> Int {
        queue.sync { tasks.count }
    }

    func failureRecords() -> [FailureRecord] {
        queue.sync { failures }
    }
}

private actor MockBookSyncer: NotionBookSyncing {
    func sync(book: BookInfo) async throws -> String {
        "notion_page_test"
    }
}

private actor MockAppender: NotionContentAppending {
    enum Mode {
        case success
        case rateLimited(retryAfter: TimeInterval)
        case networkFailure
        case serverError(statusCode: Int, message: String?)
    }

    private let mode: Mode
    private var replaceCalls = 0

    init(mode: Mode = .success) {
        self.mode = mode
    }

    func replaceHighlightsAndNotes(_ snapshots: [NotionHighlightSnapshot], to pageID: String) async throws {
        replaceCalls += 1
        try throwIfNeeded()
    }

    func replaceCallCount() -> Int {
        replaceCalls
    }

    private func throwIfNeeded() throws {
        switch mode {
        case .success:
            return
        case .rateLimited(let retryAfter):
            throw NotionAPIError.rateLimited(retryAfter: retryAfter)
        case .networkFailure:
            throw NotionAPIError.transportFailure("offline")
        case .serverError(let statusCode, let message):
            throw NotionAPIError.serverError(statusCode: statusCode, message: message)
        }
    }
}

private actor RebuildTracker {
    private var reasons: [String] = []

    func record(reason: String) {
        reasons.append(reason)
    }

    func count() -> Int {
        reasons.count
    }
}

private final class MockHighlightSnapshotStore: NotionHighlightSnapshotStoring {
    func fetchSnapshots(for bookID: String) throws -> [NotionHighlightSnapshot] {
        [
            NotionHighlightSnapshot(
                highlightText: "highlight for \(bookID)",
                noteText: "note for \(bookID)",
                chapter: "Chapter 1",
                highlightDate: Date(timeIntervalSince1970: 1_700_000_000),
                noteDate: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]
    }
}
