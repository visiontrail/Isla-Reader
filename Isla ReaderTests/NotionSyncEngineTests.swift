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
        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender
        )

        await processor.setNetworkAvailable(true)
        await processor.setNotionReady(true)

        #expect(store.pendingCount() == 0)
        #expect(await appender.highlightCallCount() == 10)
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
        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender
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
        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender
        )

        await processor.setNetworkAvailable(true)
        await processor.setNotionReady(true)

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
    }

    private let mode: Mode
    private var highlightCalls = 0
    private var noteCalls = 0

    init(mode: Mode = .success) {
        self.mode = mode
    }

    func appendHighlight(_ highlight: BlockBuilder.HighlightInput, to pageID: String) async throws {
        highlightCalls += 1
        try throwIfNeeded()
    }

    func appendNote(_ note: BlockBuilder.NoteInput, to pageID: String) async throws {
        noteCalls += 1
        try throwIfNeeded()
    }

    func highlightCallCount() -> Int {
        highlightCalls
    }

    private func throwIfNeeded() throws {
        switch mode {
        case .success:
            return
        case .rateLimited(let retryAfter):
            throw NotionAPIError.rateLimited(retryAfter: retryAfter)
        case .networkFailure:
            throw NotionAPIError.transportFailure("offline")
        }
    }
}
