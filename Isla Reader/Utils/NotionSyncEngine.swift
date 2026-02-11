//
//  NotionSyncEngine.swift
//  LanRead
//

import Combine
import CoreData
import Foundation

enum NotionSyncOperationType: String, Codable, Sendable {
    case highlight
    case note
}

struct NotionSyncPayload: Codable, Sendable {
    let bookID: String
    let bookTitle: String
    let bookAuthor: String
    let chapter: String?
    let highlightText: String?
    let noteContent: String?
    let eventDate: Date
}

struct NotionSyncQueueTask: Sendable {
    let id: UUID
    let operationType: NotionSyncOperationType
    let payload: NotionSyncPayload
    let retryCount: Int16
}

enum NotionSyncQueueStoreError: LocalizedError {
    case invalidPayload
    case invalidOperation

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Sync queue payload is invalid"
        case .invalidOperation:
            return "Sync queue operation type is invalid"
        }
    }
}

protocol NotionSyncQueueStoring: Sendable {
    func fetchNextPendingTask() throws -> NotionSyncQueueTask?
    func markTaskSynced(id: UUID) throws
    func markTaskFailed(id: UUID, retryCount: Int16, shouldRetry: Bool, message: String) throws
    func resetInProgressTasks() throws
}

protocol NotionBookSyncing: Sendable {
    func sync(book: BookInfo) async throws -> String
}

protocol NotionContentAppending: Sendable {
    func appendHighlight(_ highlight: BlockBuilder.HighlightInput, to pageID: String) async throws
    func appendNote(_ note: BlockBuilder.NoteInput, to pageID: String) async throws
}

extension NotionBookSyncer: NotionBookSyncing {}
extension NotionPageBlockAppender: NotionContentAppending {}

final class CoreDataSyncQueueStore: @unchecked Sendable, NotionSyncQueueStoring {
    static let shared = CoreDataSyncQueueStore(container: PersistenceController.shared.container)

    private let container: NSPersistentContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: NSPersistentContainer) {
        self.container = container
    }

    @discardableResult
    func enqueue(
        operation: NotionSyncOperationType,
        payload: NotionSyncPayload,
        in context: NSManagedObjectContext
    ) -> Bool {
        guard let payloadData = try? encoder.encode(payload) else {
            DebugLogger.error("NotionSyncEngine: queue payload 编码失败")
            return false
        }

        let now = Date()
        let item = SyncQueueItem(context: context)
        item.id = UUID()
        item.targetBookId = payload.bookID
        item.type = operation.rawValue
        item.payload = payloadData
        item.status = SyncQueueItemStatus.pending.rawValue
        item.retryCount = 0
        item.createdAt = now
        return true
    }

    func fetchNextPendingTask() throws -> NotionSyncQueueTask? {
        try performOnBackgroundContext { context in
            let request = SyncQueueItem.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "status == %@", SyncQueueItemStatus.pending.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

            guard let item = try context.fetch(request).first else {
                return nil
            }

            item.status = SyncQueueItemStatus.inProgress.rawValue
            try self.saveIfNeeded(context)
            return try self.decodeTask(item)
        }
    }

    func resetInProgressTasks() throws {
        try performOnBackgroundContext { context in
            let request = SyncQueueItem.fetchRequest()
            request.predicate = NSPredicate(format: "status == %@", SyncQueueItemStatus.inProgress.rawValue)
            let items = try context.fetch(request)

            for item in items {
                item.status = SyncQueueItemStatus.pending.rawValue
            }

            try self.saveIfNeeded(context)
        }
    }

    func markTaskSynced(id: UUID) throws {
        _ = try performOnBackgroundContext { context in
            guard let item = try self.fetchTask(id: id, in: context) else { return }
            context.delete(item)
            try self.saveIfNeeded(context)
        }
    }

    func markTaskFailed(id: UUID, retryCount: Int16, shouldRetry: Bool, message: String) throws {
        _ = try performOnBackgroundContext { context in
            guard let item = try self.fetchTask(id: id, in: context) else { return }
            item.retryCount = retryCount
            item.status = shouldRetry ? SyncQueueItemStatus.pending.rawValue : SyncQueueItemStatus.failed.rawValue
            if !message.isEmpty {
                DebugLogger.warning("NotionSyncEngine: task \(id) failed - \(message)")
            }
            try self.saveIfNeeded(context)
        }
    }

    private func decodeTask(_ item: SyncQueueItem) throws -> NotionSyncQueueTask {
        guard let operationType = NotionSyncOperationType(rawValue: item.type) else {
            throw NotionSyncQueueStoreError.invalidOperation
        }

        let payload = try decoder.decode(NotionSyncPayload.self, from: item.payload)
        return NotionSyncQueueTask(
            id: item.id,
            operationType: operationType,
            payload: payload,
            retryCount: item.retryCount
        )
    }

    private func fetchTask(id: UUID, in context: NSManagedObjectContext) throws -> SyncQueueItem? {
        let request = SyncQueueItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private func saveIfNeeded(_ context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
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

actor NotionSyncQueueProcessor {
    private enum FailureAction {
        case continueProcessing
        case pauseAndStop(delay: TimeInterval)
    }

    private let queueStore: NotionSyncQueueStoring
    private let bookSyncer: NotionBookSyncing
    private let blockAppender: NotionContentAppending
    private let syncConfigStore: NotionSyncConfigStoring

    private let debounceDelay: TimeInterval
    private let unknownErrorDelay: TimeInterval
    private let maxRetryCount: Int16

    private var isNetworkAvailable = true
    private var isNotionReady = false
    private var isProcessing = false
    private var hasQueuedRunRequest = false
    private var scheduledRunTask: Task<Void, Never>?

    init(
        queueStore: NotionSyncQueueStoring,
        bookSyncer: NotionBookSyncing = NotionBookSyncer(),
        blockAppender: NotionContentAppending = NotionPageBlockAppender(),
        syncConfigStore: NotionSyncConfigStoring = CoreDataNotionSyncConfigStore.shared,
        debounceDelay: TimeInterval = 2,
        unknownErrorDelay: TimeInterval = 8,
        maxRetryCount: Int16 = 5
    ) {
        self.queueStore = queueStore
        self.bookSyncer = bookSyncer
        self.blockAppender = blockAppender
        self.syncConfigStore = syncConfigStore
        self.debounceDelay = debounceDelay
        self.unknownErrorDelay = unknownErrorDelay
        self.maxRetryCount = maxRetryCount
    }

    func notifyDataEnqueued() {
        scheduleRun(after: debounceDelay, reason: "data_debounce")
    }

    func setNetworkAvailable(_ isAvailable: Bool) async {
        isNetworkAvailable = isAvailable
        if isAvailable {
            await triggerSyncNow(reason: "network_recovered")
        }
    }

    func setNotionReady(_ isReady: Bool) async {
        isNotionReady = isReady
        if isReady {
            await triggerSyncNow(reason: "notion_ready")
        }
    }

    func triggerSyncNow(reason: String) async {
        scheduledRunTask?.cancel()
        scheduledRunTask = nil
        await runSyncLoop(trigger: reason)
    }

    func runSyncLoop(trigger: String) async {
        if isProcessing {
            hasQueuedRunRequest = true
            return
        }

        guard isNetworkAvailable else {
            DebugLogger.info("NotionSyncEngine: skip sync (\(trigger)) network unavailable")
            return
        }

        guard isNotionReady else {
            DebugLogger.info("NotionSyncEngine: skip sync (\(trigger)) notion not ready")
            return
        }

        isProcessing = true
        defer {
            isProcessing = false
            if hasQueuedRunRequest {
                hasQueuedRunRequest = false
                Task {
                    await self.runSyncLoop(trigger: "queued_request")
                }
            }
        }

        while !Task.isCancelled {
            guard isNetworkAvailable, isNotionReady else {
                break
            }

            let task: NotionSyncQueueTask

            do {
                guard let nextTask = try queueStore.fetchNextPendingTask() else {
                    break
                }
                task = nextTask
            } catch {
                DebugLogger.error("NotionSyncEngine: fetch pending task failed", error: error)
                break
            }

            do {
                try await syncTask(task)
                try queueStore.markTaskSynced(id: task.id)
                try? syncConfigStore.updateLastSyncedAt(Date())
            } catch {
                let action = handleFailure(error, for: task)
                switch action {
                case .continueProcessing:
                    continue
                case .pauseAndStop(let delay):
                    scheduleRun(after: delay, reason: "backoff_pause")
                    return
                }
            }
        }
    }

    private func syncTask(_ task: NotionSyncQueueTask) async throws {
        let payload = task.payload
        let pageID = try await bookSyncer.sync(
            book: BookInfo(
                id: payload.bookID,
                title: payload.bookTitle,
                author: payload.bookAuthor
            )
        )

        switch task.operationType {
        case .highlight:
            guard let text = payload.highlightText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw NotionSyncQueueStoreError.invalidPayload
            }

            let highlight = BlockBuilder.HighlightInput(
                text: text,
                chapter: payload.chapter,
                date: payload.eventDate
            )
            try await blockAppender.appendHighlight(highlight, to: pageID)

        case .note:
            guard let noteContent = payload.noteContent?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !noteContent.isEmpty else {
                throw NotionSyncQueueStoreError.invalidPayload
            }

            let relatedText = payload.highlightText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let relatedHighlight: BlockBuilder.HighlightInput?
            if let relatedText, !relatedText.isEmpty {
                relatedHighlight = BlockBuilder.HighlightInput(
                    text: relatedText,
                    chapter: payload.chapter,
                    date: payload.eventDate
                )
            } else {
                relatedHighlight = nil
            }

            let note = BlockBuilder.NoteInput(
                content: noteContent,
                relatedHighlight: relatedHighlight,
                date: payload.eventDate
            )
            try await blockAppender.appendNote(note, to: pageID)
        }
    }

    private func handleFailure(_ error: Error, for task: NotionSyncQueueTask) -> FailureAction {
        let nextRetryCount = task.retryCount + 1
        let shouldRetry = nextRetryCount <= maxRetryCount
        let message = error.localizedDescription

        if case NotionAPIError.rateLimited(let retryAfter) = error {
            let delay = max(1, retryAfter ?? 5)

            do {
                try queueStore.markTaskFailed(
                    id: task.id,
                    retryCount: nextRetryCount,
                    shouldRetry: shouldRetry,
                    message: message
                )
            } catch {
                DebugLogger.error("NotionSyncEngine: failed to persist rate-limit state", error: error)
            }

            if !shouldRetry {
                return .continueProcessing
            }
            DebugLogger.warning("NotionSyncEngine: rate limited, pause \(delay)s")
            return .pauseAndStop(delay: delay)
        }

        if isNetworkError(error) {
            let delay = networkBackoffDelay(retryCount: nextRetryCount)
            do {
                try queueStore.markTaskFailed(
                    id: task.id,
                    retryCount: nextRetryCount,
                    shouldRetry: shouldRetry,
                    message: message
                )
            } catch {
                DebugLogger.error("NotionSyncEngine: failed to persist network backoff", error: error)
            }

            if !shouldRetry {
                return .continueProcessing
            }
            DebugLogger.warning("NotionSyncEngine: network failure, backoff \(delay)s")
            return .pauseAndStop(delay: delay)
        }

        if error is NotionSyncQueueStoreError {
            do {
                try queueStore.markTaskFailed(
                    id: task.id,
                    retryCount: nextRetryCount,
                    shouldRetry: false,
                    message: message
                )
            } catch {
                DebugLogger.error("NotionSyncEngine: failed to persist terminal task state", error: error)
            }
            return .continueProcessing
        }

        let delay = unknownErrorDelay
        do {
            try queueStore.markTaskFailed(
                id: task.id,
                retryCount: nextRetryCount,
                shouldRetry: shouldRetry,
                message: message
            )
        } catch {
            DebugLogger.error("NotionSyncEngine: failed to persist retry state", error: error)
        }
        if shouldRetry {
            return .pauseAndStop(delay: delay)
        }
        return .continueProcessing
    }

    private func scheduleRun(after delay: TimeInterval, reason: String) {
        let clampedDelay = max(0, delay)
        scheduledRunTask?.cancel()
        scheduledRunTask = Task {
            if clampedDelay > 0 {
                let duration = UInt64(clampedDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: duration)
            }
            await self.runSyncLoop(trigger: reason)
        }
    }

    private func networkBackoffDelay(retryCount: Int16) -> TimeInterval {
        let exponent = max(0, min(Int(retryCount) - 1, 6))
        return pow(2, Double(exponent))
    }

    private func isNetworkError(_ error: Error) -> Bool {
        if case NotionAPIError.transportFailure = error {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }
}

final class NotionSyncEngine {
    static let shared = NotionSyncEngine()

    private let notificationCenter: NotificationCenter
    private let persistentStoreCoordinator: NSPersistentStoreCoordinator?
    private let queueStore: CoreDataSyncQueueStore
    private let processor: NotionSyncQueueProcessor
    private let networkMonitor: NetworkMonitor

    private var contextObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    init(
        container: NSPersistentContainer = PersistenceController.shared.container,
        queueStore: CoreDataSyncQueueStore = .shared,
        networkMonitor: NetworkMonitor = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.persistentStoreCoordinator = container.persistentStoreCoordinator
        self.queueStore = queueStore
        self.networkMonitor = networkMonitor
        self.notificationCenter = notificationCenter
        self.processor = NotionSyncQueueProcessor(queueStore: queueStore)
    }

    @MainActor
    func start(notionSessionManager: NotionSessionManager) {
        guard !started else { return }
        started = true

        do {
            try queueStore.resetInProgressTasks()
        } catch {
            DebugLogger.error("NotionSyncEngine: failed to reset in-progress queue tasks", error: error)
        }

        observeCoreDataChanges()
        observeNotionSession(notionSessionManager)

        networkMonitor.onConnectivityChanged = { [weak self] isConnected in
            guard let self else { return }
            Task {
                await self.processor.setNetworkAvailable(isConnected)
            }
        }
        networkMonitor.start()

        Task {
            await self.processor.setNetworkAvailable(self.networkMonitor.isConnected)
        }
    }

    private func observeCoreDataChanges() {
        contextObserver = notificationCenter.addObserver(
            forName: .NSManagedObjectContextWillSave,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleContextWillSave(notification)
        }
    }

    @MainActor
    private func observeNotionSession(_ notionSessionManager: NotionSessionManager) {
        Publishers.CombineLatest(
            notionSessionManager.$connectionState,
            notionSessionManager.$isInitialized
        )
        .sink { [weak self] connectionState, isInitialized in
            guard let self else { return }

            let notionReady: Bool
            switch connectionState {
            case .connected:
                notionReady = isInitialized
            default:
                notionReady = false
            }

            Task {
                await self.processor.setNotionReady(notionReady)
            }
        }
        .store(in: &cancellables)
    }

    private func handleContextWillSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        guard let coordinator = context.persistentStoreCoordinator else { return }
        guard coordinator === persistentStoreCoordinator else { return }

        var enqueuedCount = 0

        let insertedHighlights = context.insertedObjects.compactMap { $0 as? Highlight }
        for highlight in insertedHighlights {
            if let payload = makeHighlightPayload(from: highlight),
               queueStore.enqueue(operation: .highlight, payload: payload, in: context) {
                enqueuedCount += 1
            }

            if let notePayload = makeNotePayload(from: highlight, useUpdatedDate: false),
               queueStore.enqueue(operation: .note, payload: notePayload, in: context) {
                enqueuedCount += 1
            }
        }

        let updatedHighlights = context.updatedObjects.compactMap { $0 as? Highlight }
        for highlight in updatedHighlights where !highlight.isInserted {
            guard highlight.changedValues().keys.contains("note") else {
                continue
            }

            if let payload = makeNotePayload(from: highlight, useUpdatedDate: true),
               queueStore.enqueue(operation: .note, payload: payload, in: context) {
                enqueuedCount += 1
            }
        }

        if enqueuedCount > 0 {
            DebugLogger.info("NotionSyncEngine: queued \(enqueuedCount) sync task(s)")
            Task {
                await processor.notifyDataEnqueued()
            }
        }
    }

    private func makeHighlightPayload(from highlight: Highlight) -> NotionSyncPayload? {
        guard let bookInfo = extractBookInfo(from: highlight),
              let text = normalize(highlight.selectedText) else {
            return nil
        }

        return NotionSyncPayload(
            bookID: bookInfo.id,
            bookTitle: bookInfo.title,
            bookAuthor: bookInfo.author,
            chapter: normalize(highlight.chapter),
            highlightText: text,
            noteContent: nil,
            eventDate: highlight.createdAt
        )
    }

    private func makeNotePayload(from highlight: Highlight, useUpdatedDate: Bool) -> NotionSyncPayload? {
        guard let bookInfo = extractBookInfo(from: highlight),
              let noteContent = normalize(highlight.note) else {
            return nil
        }

        return NotionSyncPayload(
            bookID: bookInfo.id,
            bookTitle: bookInfo.title,
            bookAuthor: bookInfo.author,
            chapter: normalize(highlight.chapter),
            highlightText: normalize(highlight.selectedText),
            noteContent: noteContent,
            eventDate: useUpdatedDate ? highlight.updatedAt : highlight.createdAt
        )
    }

    private func extractBookInfo(from highlight: Highlight) -> (id: String, title: String, author: String)? {
        let book = highlight.book
        let id = book.id.uuidString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        let title = normalize(book.title) ?? "Untitled"
        let author = normalize(book.author) ?? "Unknown"
        return (id, title, author)
    }

    private func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
