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
    let bookReadingStatusRaw: String?
    let bookProgressPercentage: Double?
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
    case invalidOperation

    var errorDescription: String? {
        switch self {
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
    func replaceHighlightsAndNotes(_ snapshots: [NotionHighlightSnapshot], to pageID: String) async throws
}

protocol NotionHighlightSnapshotStoring: Sendable {
    func fetchSnapshots(for bookID: String) throws -> [NotionHighlightSnapshot]
}

extension NotionBookSyncer: NotionBookSyncing {}
extension NotionPageBlockAppender: NotionContentAppending {}

final class CoreDataNotionHighlightSnapshotStore: @unchecked Sendable, NotionHighlightSnapshotStoring {
    static let shared = CoreDataNotionHighlightSnapshotStore(container: PersistenceController.shared.container)

    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func fetchSnapshots(for bookID: String) throws -> [NotionHighlightSnapshot] {
        try performOnBackgroundContext { context in
            guard let bookUUID = UUID(uuidString: bookID) else {
                return []
            }

            let request: NSFetchRequest<Highlight> = Highlight.fetchRequest()
            request.predicate = NSPredicate(format: "book.id == %@", bookUUID as CVarArg)

            let highlights: [Highlight] = try context.fetch(request)
            let snapshots: [NotionHighlightSnapshot] = highlights.compactMap { highlight -> NotionHighlightSnapshot? in
                guard let text = self.normalize(highlight.selectedText) else {
                    return nil
                }

                let normalizedNote = self.normalize(highlight.note)
                let createdAt = highlight.createdAt
                let updatedAt = highlight.updatedAt
                let readingLocation = self.decodeReadingLocation(from: highlight.startPosition)

                return NotionHighlightSnapshot(
                    highlightText: text,
                    noteText: normalizedNote,
                    chapter: self.normalize(highlight.chapter),
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    readingLocation: readingLocation,
                    highlightDate: createdAt,
                    noteDate: normalizedNote == nil ? nil : updatedAt
                )
            }

            let sortMode = AppSettings.currentHighlightSortMode()
            return self.sortSnapshots(snapshots, mode: sortMode)
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

    private func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sortSnapshots(_ snapshots: [NotionHighlightSnapshot], mode: HighlightSortMode) -> [NotionHighlightSnapshot] {
        switch mode {
        case .modifiedTime:
            return snapshots.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
        case .chapter:
            return snapshots.sorted(by: compareByChapter)
        }
    }

    private func compareByChapter(_ lhs: NotionHighlightSnapshot, _ rhs: NotionHighlightSnapshot) -> Bool {
        switch (lhs.readingLocation, rhs.readingLocation) {
        case let (.some(left), .some(right)):
            if left.chapterIndex != right.chapterIndex {
                return left.chapterIndex < right.chapterIndex
            }
            if left.pageIndex != right.pageIndex {
                return left.pageIndex < right.pageIndex
            }
            let leftOffset = left.textOffset ?? Int.max
            let rightOffset = right.textOffset ?? Int.max
            if leftOffset != rightOffset {
                return leftOffset < rightOffset
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func decodeReadingLocation(from rawStartPosition: String) -> NotionHighlightReadingLocation? {
        guard let data = rawStartPosition.data(using: .utf8) else {
            return nil
        }

        if let anchor = try? JSONDecoder().decode(SelectionAnchor.self, from: data) {
            return NotionHighlightReadingLocation(
                chapterIndex: max(anchor.chapterIndex, 0),
                pageIndex: max(anchor.pageIndex, 0),
                textOffset: anchor.offset
            )
        }

        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let chapterValue = payload["chapterIndex"] as? NSNumber,
           let pageValue = payload["pageIndex"] as? NSNumber {
            return NotionHighlightReadingLocation(
                chapterIndex: max(chapterValue.intValue, 0),
                pageIndex: max(pageValue.intValue, 0),
                textOffset: payload["offset"] as? Int
            )
        }

        return nil
    }

    private struct SelectionAnchor: Decodable {
        let chapterIndex: Int
        let pageIndex: Int
        let offset: Int?
    }
}

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

    typealias LibraryRebuildHandler = @Sendable (_ reason: String) async -> Bool

    private let queueStore: NotionSyncQueueStoring
    private let bookSyncer: NotionBookSyncing
    private let blockAppender: NotionContentAppending
    private let highlightSnapshotStore: NotionHighlightSnapshotStoring
    private let syncConfigStore: NotionSyncConfigStoring
    private let libraryRebuildHandler: LibraryRebuildHandler

    private let debounceDelay: TimeInterval
    private let libraryRebuildRetryDelay: TimeInterval
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
        highlightSnapshotStore: NotionHighlightSnapshotStoring = CoreDataNotionHighlightSnapshotStore.shared,
        syncConfigStore: NotionSyncConfigStoring = CoreDataNotionSyncConfigStore.shared,
        debounceDelay: TimeInterval = 2,
        libraryRebuildRetryDelay: TimeInterval = 1,
        unknownErrorDelay: TimeInterval = 8,
        maxRetryCount: Int16 = 5,
        libraryRebuildHandler: @escaping LibraryRebuildHandler = { reason in
            await NotionSessionManager.shared.rebuildLibraryDatabaseIfPossible(reason: reason)
        }
    ) {
        self.queueStore = queueStore
        self.bookSyncer = bookSyncer
        self.blockAppender = blockAppender
        self.highlightSnapshotStore = highlightSnapshotStore
        self.syncConfigStore = syncConfigStore
        self.debounceDelay = debounceDelay
        self.libraryRebuildRetryDelay = libraryRebuildRetryDelay
        self.unknownErrorDelay = unknownErrorDelay
        self.maxRetryCount = maxRetryCount
        self.libraryRebuildHandler = libraryRebuildHandler
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
                let action = await handleFailure(error, for: task)
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
                author: payload.bookAuthor,
                readingStatusRaw: payload.bookReadingStatusRaw,
                readingProgressPercentage: payload.bookProgressPercentage
            )
        )
        let snapshots = try highlightSnapshotStore.fetchSnapshots(for: payload.bookID)
        try await blockAppender.replaceHighlightsAndNotes(snapshots, to: pageID)
    }

    private func handleFailure(_ error: Error, for task: NotionSyncQueueTask) async -> FailureAction {
        let nextRetryCount = task.retryCount + 1
        let shouldRetry = nextRetryCount <= maxRetryCount
        let message = error.localizedDescription

        if shouldTriggerLibraryRebuild(for: error) {
            let rebuildReason = "sync_task=\(task.id.uuidString) error=\(message)"
            let rebuildSucceeded = await libraryRebuildHandler(rebuildReason)
            do {
                try queueStore.markTaskFailed(
                    id: task.id,
                    retryCount: nextRetryCount,
                    shouldRetry: shouldRetry,
                    message: message
                )
            } catch {
                DebugLogger.error("NotionSyncEngine: failed to persist rebuild retry state", error: error)
            }

            guard shouldRetry else {
                return .continueProcessing
            }

            if rebuildSucceeded {
                DebugLogger.warning("NotionSyncEngine: library rebuilt, retrying sync task \(task.id)")
                return .pauseAndStop(delay: libraryRebuildRetryDelay)
            }

            DebugLogger.warning("NotionSyncEngine: rebuild attempt failed, fallback to regular retry")
            return .pauseAndStop(delay: unknownErrorDelay)
        }

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

    private func shouldTriggerLibraryRebuild(for error: Error) -> Bool {
        guard case NotionAPIError.serverError(let statusCode, let message) = error else {
            return false
        }

        let lowered = message?.lowercased() ?? ""
        if statusCode == 400 && lowered.contains("archived ancestor") {
            return true
        }

        if statusCode == 404 && lowered.contains("could not find database") {
            return true
        }

        return false
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

        var touchedBooks: [String: (title: String, author: String, statusRaw: String?, progressPercentage: Double?)] = [:]

        let insertedHighlights = context.insertedObjects.compactMap { $0 as? Highlight }
        for highlight in insertedHighlights {
            collectBookInfo(from: highlight, into: &touchedBooks)
        }

        let updatedHighlights = context.updatedObjects.compactMap { $0 as? Highlight }
        for highlight in updatedHighlights where !highlight.isInserted {
            guard shouldSyncUpdatedHighlight(highlight) else {
                continue
            }
            collectBookInfo(from: highlight, into: &touchedBooks)
        }

        let deletedHighlights = context.deletedObjects.compactMap { $0 as? Highlight }
        for highlight in deletedHighlights {
            collectBookInfo(from: highlight, into: &touchedBooks)
        }

        var enqueuedCount = 0
        for (bookID, metadata) in touchedBooks {
            let payload = NotionSyncPayload(
                bookID: bookID,
                bookTitle: metadata.title,
                bookAuthor: metadata.author,
                bookReadingStatusRaw: metadata.statusRaw,
                bookProgressPercentage: metadata.progressPercentage,
                chapter: nil,
                highlightText: nil,
                noteContent: nil,
                eventDate: Date()
            )

            if queueStore.enqueue(operation: .highlight, payload: payload, in: context) {
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

    private func shouldSyncUpdatedHighlight(_ highlight: Highlight) -> Bool {
        let relevantKeys: Set<String> = ["selectedText", "note", "chapter"]
        let changedKeys = Set(highlight.changedValues().keys)
        return !changedKeys.isDisjoint(with: relevantKeys)
    }

    private func collectBookInfo(
        from highlight: Highlight,
        into touchedBooks: inout [String: (title: String, author: String, statusRaw: String?, progressPercentage: Double?)]
    ) {
        guard let bookInfo = extractBookInfo(from: highlight) else {
            return
        }

        touchedBooks[bookInfo.id] = (
            title: bookInfo.title,
            author: bookInfo.author,
            statusRaw: bookInfo.statusRaw,
            progressPercentage: bookInfo.progressPercentage
        )
    }

    private func extractBookInfo(
        from highlight: Highlight
    ) -> (id: String, title: String, author: String, statusRaw: String?, progressPercentage: Double?)? {
        let book = highlight.book
        let id = book.id.uuidString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        let title = normalize(book.title) ?? "Untitled"
        let author = normalize(book.author) ?? "Unknown"
        let statusRaw = normalize(book.libraryItem?.statusRaw) ?? ReadingStatus.wantToRead.rawValue
        let progressPercentage = normalizeProgress(book.readingProgress?.progressPercentage)
        return (id, title, author, statusRaw, progressPercentage)
    }

    private func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeProgress(_ progress: Double?) -> Double {
        guard let progress, progress.isFinite else {
            return 0
        }
        return min(max(progress, 0), 1)
    }
}
