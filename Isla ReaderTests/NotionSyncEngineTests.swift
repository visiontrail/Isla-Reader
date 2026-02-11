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
        let now = Date()
        for index in 0..<10 {
            store.seed(
                task: makeTask(
                    operationType: .highlight,
                    retryCount: 0,
                    highlightText: "highlight \(index)",
                    noteContent: nil
                ),
                nextAttemptAt: now
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
            ),
            nextAttemptAt: Date()
        )
        store.seed(
            task: makeTask(
                operationType: .highlight,
                retryCount: 0,
                highlightText: "second highlight",
                noteContent: nil
            ),
            nextAttemptAt: Date()
        )

        let appender = MockAppender(mode: .rateLimited(retryAfter: 3))
        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender
        )

        let start = Date()
        await processor.setNetworkAvailable(true)
        await processor.setNotionReady(true)

        let failures = store.failureRecords()
        #expect(failures.count == 1)
        #expect(failures.first?.retryCount == 1)
        #expect(abs((failures.first?.nextAttemptAt.timeIntervalSince(start) ?? 0) - 3) < 1.5)

        let pauses = store.pauseRecords()
        #expect(pauses.count == 1)
        #expect(abs((pauses.first?.timeIntervalSince(start) ?? 0) - 3) < 1.5)
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
            ),
            nextAttemptAt: Date()
        )

        let appender = MockAppender(mode: .networkFailure)
        let processor = NotionSyncQueueProcessor(
            queueStore: store,
            bookSyncer: MockBookSyncer(),
            blockAppender: appender
        )

        let start = Date()
        await processor.setNetworkAvailable(true)
        await processor.setNotionReady(true)

        let failures = store.failureRecords()
        #expect(failures.count == 1)
        #expect(failures.first?.retryCount == 1)
        #expect(abs((failures.first?.nextAttemptAt.timeIntervalSince(start) ?? 0) - 1) < 1.0)
    }
}

private func makeTask(
    operationType: NotionSyncOperationType,
    retryCount: Int32,
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
        let retryCount: Int32
        let nextAttemptAt: Date
        let message: String
    }

    private struct StoredTask {
        var task: NotionSyncQueueTask
        var nextAttemptAt: Date
    }

    private let queue = DispatchQueue(label: "NotionSyncEngineTests.InMemorySyncQueueStore")
    private var tasks: [StoredTask] = []
    private var failures: [FailureRecord] = []
    private var pauses: [Date] = []

    func seed(task: NotionSyncQueueTask, nextAttemptAt: Date) {
        queue.sync {
            tasks.append(StoredTask(task: task, nextAttemptAt: nextAttemptAt))
        }
    }

    func fetchNextPendingTask(now: Date) throws -> NotionSyncQueueTask? {
        queue.sync {
            guard let index = tasks.firstIndex(where: { $0.nextAttemptAt <= now }) else {
                return nil
            }
            return tasks[index].task
        }
    }

    func nextPendingAttemptDate() throws -> Date? {
        queue.sync {
            tasks.map(\.nextAttemptAt).min()
        }
    }

    func markTaskSynced(id: UUID) throws {
        queue.sync {
            tasks.removeAll { $0.task.id == id }
        }
    }

    func markTaskFailed(id: UUID, retryCount: Int32, nextAttemptAt: Date, message: String) throws {
        queue.sync {
            guard let index = tasks.firstIndex(where: { $0.task.id == id }) else { return }
            let current = tasks[index]
            tasks[index] = StoredTask(
                task: NotionSyncQueueTask(
                    id: current.task.id,
                    operationType: current.task.operationType,
                    payload: current.task.payload,
                    retryCount: retryCount
                ),
                nextAttemptAt: nextAttemptAt
            )
            failures.append(
                FailureRecord(
                    id: id,
                    retryCount: retryCount,
                    nextAttemptAt: nextAttemptAt,
                    message: message
                )
            )
        }
    }

    func pausePendingTasks(until: Date, message: String) throws {
        queue.sync {
            pauses.append(until)
            for index in tasks.indices where tasks[index].nextAttemptAt < until {
                tasks[index].nextAttemptAt = until
            }
        }
    }

    func pendingCount() -> Int {
        queue.sync { tasks.count }
    }

    func failureRecords() -> [FailureRecord] {
        queue.sync { failures }
    }

    func pauseRecords() -> [Date] {
        queue.sync { pauses }
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
