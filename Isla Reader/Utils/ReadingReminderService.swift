//
//  ReadingReminderService.swift
//  LanRead
//
//  Created by Assistant on 2025/2/14.
//

import Foundation
import UserNotifications

final class ReadingReminderService {
    static let shared = ReadingReminderService()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private init() {}
    
    func enableDailyReminder(goalMinutes: Int) async -> Bool {
        let granted = await requestAuthorization()
        guard granted else {
            DebugLogger.warning("Notification authorization was not granted for reading reminder.")
            return false
        }
        
        await scheduleDailyReminder(goalMinutes: goalMinutes)
        return true
    }
    
    @discardableResult
    func refreshReminderIfNeeded(isEnabled: Bool, goalMinutes: Int) async -> Bool {
        let authorizationStatus = await currentAuthorizationStatus()
        
        guard isEnabled else {
            cancelReminder()
            return authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
        }
        
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await scheduleDailyReminder(goalMinutes: goalMinutes)
            return true
        case .denied:
            cancelReminder()
            DebugLogger.warning("Notification authorization denied; reading reminder cancelled.")
            return false
        case .notDetermined:
            return await enableDailyReminder(goalMinutes: goalMinutes)
        @unknown default:
            DebugLogger.warning("Unknown notification authorization status; skipping reminder scheduling.")
            return false
        }
    }
    
    func cancelReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [ReadingReminderConstants.notificationIdentifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [ReadingReminderConstants.notificationIdentifier])
        Task { @MainActor in
            await ReadingLiveActivityManager.shared.endAll()
        }
        DebugLogger.info("Cancelled reading reminder notifications.")
    }

    func isReadingReminderNotification(_ request: UNNotificationRequest) -> Bool {
        if request.identifier == ReadingReminderConstants.notificationIdentifier {
            return true
        }

        return shouldOpenContinueReading(from: request.content.userInfo)
    }

    func shouldOpenContinueReading(from userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo[ReadingReminderConstants.userInfoOpenKey] as? String) == ReadingReminderConstants.userInfoOpenContinueReadingValue
    }

    func isContinueReadingURL(_ url: URL) -> Bool {
        let allowedSchemes = ["isla-reader", "lanread"]
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            return false
        }
        return url.host?.lowercased() == "read" && url.path.lowercased() == "/last"
    }
    
    private func requestAuthorization() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound]
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            notificationCenter.requestAuthorization(options: options) { granted, error in
                if let error = error {
                    DebugLogger.error("Failed to request notification authorization", error: error)
                }
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
    
    private func scheduleDailyReminder(goalMinutes: Int) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [ReadingReminderConstants.notificationIdentifier])
        
        let content = buildContent(goalMinutes: goalMinutes)
        var dateComponents = DateComponents()
        dateComponents.hour = ReadingReminderConstants.reminderHour
        dateComponents.minute = ReadingReminderConstants.reminderMinute
        dateComponents.calendar = Calendar.current
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: ReadingReminderConstants.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            notificationCenter.add(request) { error in
                if let error = error {
                    DebugLogger.error("Failed to schedule reading reminder", error: error)
                } else {
                    DebugLogger.info("Scheduled reading reminder at 20:00 local time.")
                }
                continuation.resume()
            }
        }
    }
    
    private func buildContent(goalMinutes: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Start Reading"
        content.body = "Give yourself \(max(1, goalMinutes)) minutes."
        content.sound = .default
        content.userInfo = [
            ReadingReminderConstants.userInfoOpenKey: ReadingReminderConstants.userInfoOpenContinueReadingValue,
            ReadingReminderConstants.userInfoDeepLinkKey: ReadingReminderConstants.defaultDeepLink
        ]
        
        if #available(iOS 15.0, *) {
            content.relevanceScore = 1.0
            content.interruptionLevel = .timeSensitive
        }
        
        return content
    }
}
