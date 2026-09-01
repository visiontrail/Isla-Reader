import Foundation
import Testing
@testable import LanRead

struct AchievementTests {
    @Test
    func catalogContainsEightUniqueBadges() {
        let achievements = AchievementCatalog.all

        #expect(achievements.count == 8)
        #expect(Set(achievements.map(\.id)).count == achievements.count)
        #expect(Set(achievements.map(\.assetName)).count == achievements.count)
    }

    @Test
    func goalsUseReadingDataAndClampDisplayedProgress() {
        let metrics = AchievementMetrics(
            totalBooks: 6,
            startedBooks: 2,
            completedBooks: 1,
            detailedReadingSeconds: 31 * 60,
            skimmingReadingSeconds: 16 * 60,
            totalReadingSeconds: 301 * 60,
            highlightCount: 8,
            bookmarkCount: 7
        )

        for achievement in AchievementCatalog.all {
            #expect(achievement.isEarned(with: metrics))
            #expect(achievement.progress(in: metrics) == achievement.goal.target)
            #expect(achievement.progressFraction(in: metrics) == 1)
        }
    }

    @Test
    func unlockedBadgesPersistAndAreNotAwardedTwice() {
        let suiteName = "AchievementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let metrics = AchievementMetrics(
            totalBooks: 1,
            startedBooks: 1,
            completedBooks: 0,
            detailedReadingSeconds: 2,
            skimmingReadingSeconds: 0,
            totalReadingSeconds: 2,
            highlightCount: 0,
            bookmarkCount: 0
        )
        let unlockDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = AchievementStore(defaults: defaults)

        let firstUnlock = store.unlockNewAchievements(for: metrics, now: unlockDate)
        #expect(firstUnlock.map(\.id) == ["first_steps"])
        #expect(store.unlockNewAchievements(for: metrics).isEmpty)

        let restoredStore = AchievementStore(defaults: defaults)
        let firstSteps = AchievementCatalog.all.first { $0.id == "first_steps" }!
        #expect(restoredStore.isUnlocked(firstSteps))
        #expect(restoredStore.unlockedAt(for: firstSteps) == unlockDate)
    }

    @Test
    func runtimeEvaluationPresentsAndDismissesUnlockEvent() {
        let suiteName = "AchievementRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let metrics = AchievementMetrics(
            totalBooks: 1,
            startedBooks: 1,
            completedBooks: 0,
            detailedReadingSeconds: 0,
            skimmingReadingSeconds: 0,
            totalReadingSeconds: 0,
            highlightCount: 0,
            bookmarkCount: 0
        )
        let store = AchievementStore(defaults: defaults)

        #expect(store.currentUnlockEvent == nil)
        #expect(store.evaluateAndPresent(metrics: metrics).map(\.id) == ["first_steps"])
        #expect(store.currentUnlockEvent?.achievements.map(\.id) == ["first_steps"])

        store.dismissCurrentUnlockEvent()
        #expect(store.currentUnlockEvent == nil)
        #expect(store.evaluateAndPresent(metrics: metrics).isEmpty)
        #expect(store.currentUnlockEvent == nil)
    }
}
