//
//  ReadingLiveActivityManager.swift
//  LanRead
//
//  Created by Assistant on 2026/2/10.
//

import Foundation
import ActivityKit

@MainActor
final class ReadingLiveActivityManager {
    static let shared = ReadingLiveActivityManager()

    private let calendar = Calendar.current
    private var legacyAutoEndTask: Task<Void, Never>?
    private var lastPublishedContentState: ReadingReminderAttributes.ContentState?

    private init() {}

    func startForTonightIfNeeded(
        goalMinutes: Int,
        minutesReadToday: Int = ReadingDailyStatsStore.shared.todayReadingMinutes(),
        reminderHour: Int = ReadingReminderConstants.defaultReminderHour,
        reminderMinute: Int = ReadingReminderConstants.defaultReminderMinute,
        deepLink: String = ReadingReminderConstants.defaultDeepLink
    ) async {
        let now = Date()
        let normalizedHour = min(max(reminderHour, 0), 23)
        let normalizedMinute = min(max(reminderMinute, 0), 59)
        DebugLogger.info(
            "[LiveActivityFlow] startForTonightIfNeeded invoked. " +
            "now=\(now), goalMinutes=\(goalMinutes), minutesReadToday=\(minutesReadToday), " +
            "reminder=\(String(format: "%02d:%02d", normalizedHour, normalizedMinute)), deepLink=\(deepLink)"
        )

        guard #available(iOS 16.1, *) else {
            DebugLogger.warning("ReadingLiveActivityManager: ActivityKit is unavailable on this iOS version.")
            return
        }

        guard isWithinTonightWindow(now, reminderHour: reminderHour, reminderMinute: reminderMinute) else {
            let startTime = String(format: "%02d:%02d", normalizedHour, normalizedMinute)
            DebugLogger.info(
                "[LiveActivityFlow] Skipped start because current time is outside today's start window. " +
                "now=\(now), allowedWindow=\(startTime)~23:59"
            )
            return
        }

        guard !hasLiveActivityForTonight(now: now) else {
            let activeCount = Activity<ReadingReminderAttributes>.activities.count
            DebugLogger.info(
                "[LiveActivityFlow] Skipped start because an activity for tonight already exists. " +
                "activeCount=\(activeCount)"
            )
            return
        }

        DebugLogger.info("[LiveActivityFlow] Conditions passed. Starting Live Activity request.")
        await start(
            goalMinutes: goalMinutes,
            minutesReadToday: minutesReadToday,
            deepLink: deepLink
        )
    }

    func updateIfNeeded(
        goalMinutes: Int,
        minutesReadToday: Int,
        deepLink: String = ReadingReminderConstants.defaultDeepLink
    ) async {
        guard #available(iOS 16.1, *) else { return }

        let safeGoalMinutes = max(1, goalMinutes)
        let safeMinutesReadToday = max(0, minutesReadToday)
        let contentState = ReadingReminderAttributes.ContentState(
            goalMinutes: safeGoalMinutes,
            minutesReadToday: safeMinutesReadToday,
            deepLink: deepLink
        )

        guard contentState != lastPublishedContentState else {
            return
        }

        let activities = Activity<ReadingReminderAttributes>.activities
        guard !activities.isEmpty else {
            DebugLogger.info(
                "[LiveActivityFlow] Skipped update because there is no active Live Activity. " +
                "goalMinutes=\(safeGoalMinutes), minutesReadToday=\(safeMinutesReadToday)"
            )
            return
        }

        let staleDate = endOfToday()
        for activity in activities {
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: contentState, staleDate: staleDate)
                await activity.update(content)
            } else {
                await activity.update(using: contentState)
            }
            DebugLogger.info(
                "[LiveActivityFlow] Updated Live Activity content. " +
                "activityID=\(activity.id), goalMinutes=\(safeGoalMinutes), minutesReadToday=\(safeMinutesReadToday)"
            )
        }

        lastPublishedContentState = contentState
    }

    func start(
        goalMinutes: Int,
        minutesReadToday: Int,
        deepLink: String
    ) async {
        guard #available(iOS 16.1, *) else { return }

        let areActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let existingCount = Activity<ReadingReminderAttributes>.activities.count
        DebugLogger.info(
            "[LiveActivityFlow] start invoked. areActivitiesEnabled=\(areActivitiesEnabled), existingCount=\(existingCount)"
        )

        guard areActivitiesEnabled else {
            DebugLogger.warning("[LiveActivityFlow] Live Activities are disabled by system settings.")
            return
        }

        let safeGoalMinutes = max(1, goalMinutes)
        let safeMinutesReadToday = max(0, minutesReadToday)
        let staleDate = endOfToday()
        let attributes = ReadingReminderAttributes(reminderDate: Date())
        let contentState = ReadingReminderAttributes.ContentState(
            goalMinutes: safeGoalMinutes,
            minutesReadToday: safeMinutesReadToday,
            deepLink: deepLink
        )

        do {
            let activity: Activity<ReadingReminderAttributes>
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: contentState, staleDate: staleDate)
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    contentState: contentState,
                    pushType: nil
                )
                scheduleLegacyAutoEndIfNeeded(staleDate: staleDate)
            }
            DebugLogger.info(
                "[LiveActivityFlow] Live Activity started successfully. " +
                "activityID=\(activity.id), goalMinutes=\(safeGoalMinutes), minutesReadToday=\(safeMinutesReadToday), staleDate=\(String(describing: staleDate))"
            )
            lastPublishedContentState = contentState
        } catch {
            DebugLogger.error("[LiveActivityFlow] Failed to start Live Activity.", error: error)
        }
    }

    func endAll() async {
        guard #available(iOS 16.1, *) else { return }

        legacyAutoEndTask?.cancel()
        legacyAutoEndTask = nil

        let activities = Activity<ReadingReminderAttributes>.activities
        DebugLogger.info("[LiveActivityFlow] endAll invoked. activeCountBeforeEnd=\(activities.count)")
        for activity in activities {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
            DebugLogger.info("[LiveActivityFlow] Ended Live Activity. activityID=\(activity.id)")
        }
        lastPublishedContentState = nil
        DebugLogger.info("[LiveActivityFlow] Completed endAll for reading reminder Live Activities.")
    }

    @available(iOS 16.1, *)
    private func hasLiveActivityForTonight(now: Date) -> Bool {
        Activity<ReadingReminderAttributes>.activities.contains { activity in
            calendar.isDate(activity.attributes.reminderDate, inSameDayAs: now)
        }
    }

    private func isWithinTonightWindow(_ date: Date, reminderHour: Int, reminderMinute: Int) -> Bool {
        let safeHour = min(max(reminderHour, 0), 23)
        let safeMinute = min(max(reminderMinute, 0), 59)

        guard
            let start = calendar.date(
                bySettingHour: safeHour,
                minute: safeMinute,
                second: 0,
                of: date
            ),
            let end = endOfToday(for: date)
        else {
            return false
        }

        return date >= start && date <= end
    }

    private func endOfToday(for date: Date = Date()) -> Date? {
        calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date)
    }

    private func scheduleLegacyAutoEndIfNeeded(staleDate: Date?) {
        guard let staleDate else { return }
        let remainingTime = staleDate.timeIntervalSinceNow
        guard remainingTime > 0 else { return }

        legacyAutoEndTask?.cancel()
        legacyAutoEndTask = Task { [weak self] in
            let sleepNanoseconds = UInt64(remainingTime * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: sleepNanoseconds)
            } catch {
                return
            }
            await self?.endAll()
        }
    }
}

final class ReadingDailyStatsStore {
    static let shared = ReadingDailyStatsStore()

    private enum Keys {
        static let todayStartTimestamp = "reading_daily_stats_today_start_timestamp"
        static let todayReadingSeconds = "reading_daily_stats_today_reading_seconds"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func todayReadingMinutes() -> Int {
        todayReadingSeconds() / 60
    }

    func todayReadingSeconds() -> Int {
        normalizeForToday()
        return max(0, defaults.integer(forKey: Keys.todayReadingSeconds))
    }

    func addReadingSeconds(_ seconds: Int) {
        guard seconds > 0 else { return }
        normalizeForToday()
        let current = max(0, defaults.integer(forKey: Keys.todayReadingSeconds))
        defaults.set(current + seconds, forKey: Keys.todayReadingSeconds)
    }

    private func normalizeForToday() {
        let todayStart = calendar.startOfDay(for: Date())
        let storedTimestamp = defaults.double(forKey: Keys.todayStartTimestamp)
        let storedDate = Date(timeIntervalSince1970: storedTimestamp)

        if storedTimestamp <= 0 || !calendar.isDate(storedDate, inSameDayAs: todayStart) {
            defaults.set(todayStart.timeIntervalSince1970, forKey: Keys.todayStartTimestamp)
            defaults.set(0, forKey: Keys.todayReadingSeconds)
        }
    }
}
