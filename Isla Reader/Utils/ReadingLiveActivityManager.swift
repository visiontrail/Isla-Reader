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

    private init() {}

    func startForTonightIfNeeded(
        goalMinutes: Int,
        minutesReadToday: Int = 0,
        reminderHour: Int = ReadingReminderConstants.defaultReminderHour,
        reminderMinute: Int = ReadingReminderConstants.defaultReminderMinute,
        deepLink: String = ReadingReminderConstants.defaultDeepLink
    ) async {
        guard #available(iOS 16.1, *) else {
            DebugLogger.warning("ReadingLiveActivityManager: ActivityKit is unavailable on this iOS version.")
            return
        }

        let now = Date()
        guard isWithinTonightWindow(now, reminderHour: reminderHour, reminderMinute: reminderMinute) else {
            let startTime = String(format: "%02d:%02d", min(max(reminderHour, 0), 23), min(max(reminderMinute, 0), 59))
            DebugLogger.info("ReadingLiveActivityManager: Skipped start, current time is outside \(startTime)~23:59 window.")
            return
        }

        guard !hasLiveActivityForTonight(now: now) else {
            DebugLogger.info("ReadingLiveActivityManager: Existing activity found for tonight, skip duplicate start.")
            return
        }

        await start(
            goalMinutes: goalMinutes,
            minutesReadToday: minutesReadToday,
            deepLink: deepLink
        )
    }

    func start(
        goalMinutes: Int,
        minutesReadToday: Int,
        deepLink: String
    ) async {
        guard #available(iOS 16.1, *) else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            DebugLogger.warning("ReadingLiveActivityManager: Live Activities are disabled by system settings.")
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
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: contentState, staleDate: staleDate)
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } else {
                _ = try Activity.request(
                    attributes: attributes,
                    contentState: contentState,
                    pushType: nil
                )
                scheduleLegacyAutoEndIfNeeded(staleDate: staleDate)
            }
            DebugLogger.info("ReadingLiveActivityManager: Live Activity started successfully.")
        } catch {
            DebugLogger.error("ReadingLiveActivityManager: Failed to start Live Activity.", error: error)
        }
    }

    func endAll() async {
        guard #available(iOS 16.1, *) else { return }

        legacyAutoEndTask?.cancel()
        legacyAutoEndTask = nil

        for activity in Activity<ReadingReminderAttributes>.activities {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
        DebugLogger.info("ReadingLiveActivityManager: Ended all reading reminder Live Activities.")
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
