//
//  ReadingReminderService.swift
//  Isla Reader
//
//  Created by Assistant on 2025/2/14.
//

import Foundation
import UserNotifications

final class ReadingReminderService {
    static let shared = ReadingReminderService()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let reminderIdentifier = "reading_reminder_daily"
    private let categoryIdentifier = "READING_REMINDER"
    private let reminderHour = 20
    private let reminderMinute = 0
    
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
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [reminderIdentifier])
        DebugLogger.info("Cancelled reading reminder notifications.")
    }
    
    private func requestAuthorization() async -> Bool {
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        if #available(iOS 15.0, *) {
            options.insert(.timeSensitive)
        }
        
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
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        await registerNotificationCategory()
        
        let content = buildContent(goalMinutes: goalMinutes)
        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute
        dateComponents.calendar = Calendar.current
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)
        
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
    
    private func registerNotificationCategory() async {
        let action = UNNotificationAction(
            identifier: "READING_REMINDER_OPEN",
            title: NSLocalizedString("reading_reminder.action.open", comment: "CTA to open the app from reminder"),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [action],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        let existingCategories = await withCheckedContinuation { (continuation: CheckedContinuation<Set<UNNotificationCategory>, Never>) in
            notificationCenter.getNotificationCategories { categories in
                continuation.resume(returning: categories)
            }
        }
        
        var categories = existingCategories
        categories.insert(category)
        notificationCenter.setNotificationCategories(categories)
    }
    
    private func buildContent(goalMinutes: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("reading_reminder.title", comment: "Reading reminder notification title")
        content.body = String(
            format: NSLocalizedString("reading_reminder.body", comment: "Reading reminder body"),
            goalMinutes
        )
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        
        if #available(iOS 15.0, *) {
            content.relevanceScore = 1.0
        }
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        
        return content
    }
}
