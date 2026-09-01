//
//  Achievement.swift
//  LanRead
//

import Foundation
import SwiftUI
import CoreData

struct AchievementMetrics: Equatable {
    let totalBooks: Int
    let startedBooks: Int
    let completedBooks: Int
    let detailedReadingSeconds: Int64
    let skimmingReadingSeconds: Int64
    let totalReadingSeconds: Int64
    let highlightCount: Int
    let bookmarkCount: Int

    static func current(
        readingProgresses: [ReadingProgress],
        books: [Book],
        highlights: [Highlight],
        bookmarks: [Bookmark]
    ) -> AchievementMetrics {
        let detailedSeconds = readingProgresses.reduce(Int64(0)) {
            $0 + $1.effectiveDetailedReadingTime
        }
        let skimmingSeconds = readingProgresses.reduce(Int64(0)) {
            $0 + $1.skimmingReadingTime
        }
        let startedBooks = books.filter { book in
            if let status = book.libraryItem?.status,
               status == .reading || status == .finished {
                return true
            }

            guard let progress = book.readingProgress else { return false }
            return progress.effectiveDetailedReadingTime > 0 ||
                progress.skimmingReadingTime > 0 ||
                progress.progressPercentage > 0 ||
                progress.currentPage > 0
        }.count
        let completedBooks = books.filter { book in
            if book.libraryItem?.status == .finished {
                return true
            }
            return book.readingProgress?.progressPercentage ?? 0 >= 0.99
        }.count

        return AchievementMetrics(
            totalBooks: books.count,
            startedBooks: startedBooks,
            completedBooks: completedBooks,
            detailedReadingSeconds: detailedSeconds,
            skimmingReadingSeconds: skimmingSeconds,
            totalReadingSeconds: detailedSeconds + skimmingSeconds,
            highlightCount: highlights.count,
            bookmarkCount: bookmarks.count
        )
    }

    static func current(in context: NSManagedObjectContext) throws -> AchievementMetrics {
        try current(
            readingProgresses: context.fetch(ReadingProgress.fetchRequest()),
            books: context.fetch(Book.fetchRequest()),
            highlights: context.fetch(Highlight.fetchRequest()),
            bookmarks: context.fetch(Bookmark.fetchRequest())
        )
    }
}

enum AchievementGoal: Equatable {
    case startedBooks(Int)
    case totalBooks(Int)
    case completedBooks(Int)
    case detailedReadingMinutes(Int)
    case skimmingReadingMinutes(Int)
    case totalReadingMinutes(Int)
    case highlights(Int)
    case bookmarks(Int)

    var target: Int {
        switch self {
        case .startedBooks(let target),
             .totalBooks(let target),
             .completedBooks(let target),
             .detailedReadingMinutes(let target),
             .skimmingReadingMinutes(let target),
             .totalReadingMinutes(let target),
             .highlights(let target),
             .bookmarks(let target):
            return target
        }
    }

    func currentValue(in metrics: AchievementMetrics) -> Int {
        switch self {
        case .startedBooks:
            return metrics.startedBooks
        case .totalBooks:
            return metrics.totalBooks
        case .completedBooks:
            return metrics.completedBooks
        case .detailedReadingMinutes:
            return Int(metrics.detailedReadingSeconds / 60)
        case .skimmingReadingMinutes:
            return Int(metrics.skimmingReadingSeconds / 60)
        case .totalReadingMinutes:
            return Int(metrics.totalReadingSeconds / 60)
        case .highlights:
            return metrics.highlightCount
        case .bookmarks:
            return metrics.bookmarkCount
        }
    }
}

struct AchievementDefinition: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let descriptionKey: String
    let assetName: String
    let goal: AchievementGoal

    func progress(in metrics: AchievementMetrics) -> Int {
        min(goal.currentValue(in: metrics), goal.target)
    }

    func progressFraction(in metrics: AchievementMetrics) -> Double {
        guard goal.target > 0 else { return 0 }
        return min(1, Double(progress(in: metrics)) / Double(goal.target))
    }

    func isEarned(with metrics: AchievementMetrics) -> Bool {
        goal.currentValue(in: metrics) >= goal.target
    }
}

enum AchievementCatalog {
    static let all: [AchievementDefinition] = [
        AchievementDefinition(
            id: "first_steps",
            titleKey: "achievement.first_steps.title",
            descriptionKey: "achievement.first_steps.description",
            assetName: "AchievementFirstSteps",
            goal: .startedBooks(1)
        ),
        AchievementDefinition(
            id: "book_collector",
            titleKey: "achievement.book_collector.title",
            descriptionKey: "achievement.book_collector.description",
            assetName: "AchievementBookCollector",
            goal: .totalBooks(5)
        ),
        AchievementDefinition(
            id: "deep_focus",
            titleKey: "achievement.deep_focus.title",
            descriptionKey: "achievement.deep_focus.description",
            assetName: "AchievementDeepFocus",
            goal: .detailedReadingMinutes(30)
        ),
        AchievementDefinition(
            id: "swift_reader",
            titleKey: "achievement.swift_reader.title",
            descriptionKey: "achievement.swift_reader.description",
            assetName: "AchievementSwiftReader",
            goal: .skimmingReadingMinutes(15)
        ),
        AchievementDefinition(
            id: "highlight_hunter",
            titleKey: "achievement.highlight_hunter.title",
            descriptionKey: "achievement.highlight_hunter.description",
            assetName: "AchievementHighlightHunter",
            goal: .highlights(5)
        ),
        AchievementDefinition(
            id: "bookmark_keeper",
            titleKey: "achievement.bookmark_keeper.title",
            descriptionKey: "achievement.bookmark_keeper.description",
            assetName: "AchievementBookmarkKeeper",
            goal: .bookmarks(5)
        ),
        AchievementDefinition(
            id: "book_conqueror",
            titleKey: "achievement.book_conqueror.title",
            descriptionKey: "achievement.book_conqueror.description",
            assetName: "AchievementBookConqueror",
            goal: .completedBooks(1)
        ),
        AchievementDefinition(
            id: "reading_legend",
            titleKey: "achievement.reading_legend.title",
            descriptionKey: "achievement.reading_legend.description",
            assetName: "AchievementReadingLegend",
            goal: .totalReadingMinutes(300)
        )
    ]
}

final class AchievementStore: ObservableObject {
    static let shared = AchievementStore()

    private static let unlockedAchievementsKey = "achievement.unlocked_at_by_id.v1"

    @Published private(set) var unlockedAtByID: [String: Date]
    @Published private(set) var currentUnlockEvent: AchievementUnlockEvent?
    @Published private(set) var activePresenterID: UUID?

    private let defaults: UserDefaults
    private var pendingUnlockEvents: [AchievementUnlockEvent] = []
    private var presenters: [UUID: (priority: Int, order: Int)] = [:]
    private var presenterOrder = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.currentUnlockEvent = nil
        self.activePresenterID = nil
        let storedValues = defaults.dictionary(forKey: Self.unlockedAchievementsKey) ?? [:]
        self.unlockedAtByID = storedValues.reduce(into: [:]) { result, pair in
            guard let timestamp = pair.value as? NSNumber else { return }
            result[pair.key] = Date(timeIntervalSince1970: timestamp.doubleValue)
        }
    }

    func isUnlocked(_ achievement: AchievementDefinition) -> Bool {
        unlockedAtByID[achievement.id] != nil
    }

    func unlockedAt(for achievement: AchievementDefinition) -> Date? {
        unlockedAtByID[achievement.id]
    }

    func unlockedCount(in achievements: [AchievementDefinition] = AchievementCatalog.all) -> Int {
        achievements.reduce(0) { count, achievement in
            count + (isUnlocked(achievement) ? 1 : 0)
        }
    }

    @discardableResult
    func unlockNewAchievements(
        for metrics: AchievementMetrics,
        now: Date = Date()
    ) -> [AchievementDefinition] {
        let newlyUnlocked = AchievementCatalog.all.filter { achievement in
            !isUnlocked(achievement) && achievement.isEarned(with: metrics)
        }

        guard !newlyUnlocked.isEmpty else { return [] }

        newlyUnlocked.forEach { unlockedAtByID[$0.id] = now }
        persist()
        return newlyUnlocked
    }

    @discardableResult
    func evaluateAndPresent(
        metrics: AchievementMetrics,
        now: Date = Date()
    ) -> [AchievementDefinition] {
        let newlyUnlocked = unlockNewAchievements(for: metrics, now: now)
        guard !newlyUnlocked.isEmpty else { return [] }

        let event = AchievementUnlockEvent(achievements: newlyUnlocked)
        if currentUnlockEvent == nil {
            currentUnlockEvent = event
        } else {
            pendingUnlockEvents.append(event)
        }

        DebugLogger.success(
            "AchievementSystem: 解锁徽章 " + newlyUnlocked.map(\.id).joined(separator: ", ")
        )
        return newlyUnlocked
    }

    func dismissCurrentUnlockEvent() {
        if pendingUnlockEvents.isEmpty {
            currentUnlockEvent = nil
        } else {
            currentUnlockEvent = pendingUnlockEvents.removeFirst()
        }
    }

    func registerPresenter(id: UUID, priority: Int) {
        presenterOrder += 1
        presenters[id] = (priority: priority, order: presenterOrder)
        updateActivePresenter()
    }

    func unregisterPresenter(id: UUID) {
        presenters.removeValue(forKey: id)
        updateActivePresenter()
    }

    private func updateActivePresenter() {
        activePresenterID = presenters.max { lhs, rhs in
            if lhs.value.priority == rhs.value.priority {
                return lhs.value.order < rhs.value.order
            }
            return lhs.value.priority < rhs.value.priority
        }?.key
    }

    private func persist() {
        let timestamps = unlockedAtByID.mapValues(\.timeIntervalSince1970)
        defaults.set(timestamps, forKey: Self.unlockedAchievementsKey)
    }
}

struct AchievementUnlockEvent: Identifiable {
    let id = UUID()
    let achievements: [AchievementDefinition]
}
