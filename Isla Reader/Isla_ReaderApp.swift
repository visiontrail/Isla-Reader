//
//  Isla_ReaderApp.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import UIKit
import GoogleMobileAds
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard ReadingReminderService.shared.isReadingReminderNotification(response.notification.request) else {
            return
        }

        Task { @MainActor in
            ReadingReminderCoordinator.shared.requestContinueReading(triggeredByReminder: true)
        }
    }
}

@main
struct Isla_ReaderApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var notionSessionManager = NotionSessionManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        NetworkPermissionWarmup.shared.triggerWarmupIfNeeded()
        
        // Update reading statuses on app launch
        // Check for books that haven't been accessed in a week and mark them as paused
        Task {
            await MainActor.run {
                ReadingStatusService.shared.updateAllReadingStatuses(
                    in: PersistenceController.shared.container.viewContext
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.locale, appSettings.locale)
                .environmentObject(notionSessionManager)
        }
    }
}
