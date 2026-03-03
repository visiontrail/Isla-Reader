//
//  MainTabView.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI

struct MainTabView: View {
    private enum PhoneTab: Hashable {
        case library
        case progress
        case settings
    }

    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var reminderCoordinator = ReadingReminderCoordinator.shared
    @StateObject private var updatePromptCoordinator = AppUpdatePromptCoordinator.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var selectedPhoneTab: PhoneTab = .library
    @State private var handledContinueReadingRequestID = 0
    @State private var handledReminderTapRequestID = 0
    @State private var hasTriggeredLaunchUpdateCheck = false
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad layout with sidebar
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    LibraryView()
                }
            } else {
                // iPhone layout with tab bar
                TabView(selection: $selectedPhoneTab) {
                    LibraryView()
                        .tag(PhoneTab.library)
                        .tabItem {
                            Image(systemName: "books.vertical")
                            Text(NSLocalizedString("tab.library", comment: ""))
                        }
                    
                    ReadingProgressView()
                        .tag(PhoneTab.progress)
                        .tabItem {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text(NSLocalizedString("tab.progress", comment: ""))
                        }
                    
                    SettingsView()
                        .tag(PhoneTab.settings)
                        .tabItem {
                            Image(systemName: "gearshape")
                            Text(NSLocalizedString("tab.settings", comment: ""))
                        }
                }
            }
        }
        .tint(.blue)
        .preferredColorScheme(appSettings.theme.colorScheme)
        .onChange(of: reminderCoordinator.continueReadingRequestID) { _ in
            processPendingContinueReadingRequestIfNeeded(isSceneActive: scenePhase == .active)
        }
        .onChange(of: reminderCoordinator.reminderTapRequestID) { _ in
            processPendingReminderTapIfNeeded(isSceneActive: scenePhase == .active)
        }
        .onChange(of: scenePhase) { phase in
            let isSceneActive = phase == .active
            DebugLogger.info("[LiveActivityFlow] scenePhase changed. phase=\(String(describing: phase)), isSceneActive=\(isSceneActive)")
            processPendingContinueReadingRequestIfNeeded(isSceneActive: isSceneActive)
            processPendingReminderTapIfNeeded(isSceneActive: isSceneActive)
            if isSceneActive {
                updatePromptCoordinator.checkForUpdateIfNeeded(trigger: .foreground)
            }
        }
        .onAppear {
            guard !hasTriggeredLaunchUpdateCheck else { return }
            hasTriggeredLaunchUpdateCheck = true
            updatePromptCoordinator.checkForUpdateIfNeeded(trigger: .launch)
        }
        .onOpenURL { url in
            guard ReadingReminderService.shared.isContinueReadingURL(url) else {
                return
            }
            reminderCoordinator.requestContinueReading(triggeredByReminder: false)
        }
        .alert(item: $updatePromptCoordinator.activePrompt) { prompt in
            if prompt.isMandatory {
                return Alert(
                    title: Text(prompt.title),
                    message: Text(prompt.message),
                    dismissButton: .default(Text(NSLocalizedString("update.prompt.update_now", comment: ""))) {
                        openStore(for: prompt)
                        updatePromptCoordinator.consumePrompt()
                    }
                )
            }

            return Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text(NSLocalizedString("update.prompt.update_now", comment: ""))) {
                    openStore(for: prompt)
                    updatePromptCoordinator.consumePrompt()
                },
                secondaryButton: .cancel(Text(NSLocalizedString("update.prompt.later", comment: ""))) {
                    updatePromptCoordinator.consumePrompt()
                }
            )
        }
    }

    private func processPendingContinueReadingRequestIfNeeded(isSceneActive: Bool) {
        guard isSceneActive else {
            DebugLogger.info("[LiveActivityFlow] Skipped continue reading handling because scene is not active.")
            return
        }
        let requestID = reminderCoordinator.continueReadingRequestID
        guard requestID > handledContinueReadingRequestID else {
            return
        }

        handledContinueReadingRequestID = requestID
        selectedPhoneTab = .library
        DebugLogger.info(
            "[LiveActivityFlow] Handled continue reading request and navigated to library. " +
            "requestID=\(requestID)"
        )
    }

    private func processPendingReminderTapIfNeeded(isSceneActive: Bool) {
        guard isSceneActive else {
            DebugLogger.info("[LiveActivityFlow] Skipped reminder tap handling because scene is not active.")
            return
        }
        let requestID = reminderCoordinator.reminderTapRequestID
        guard requestID > handledReminderTapRequestID else {
            return
        }

        handledReminderTapRequestID = requestID
        let minutesReadToday = ReadingDailyStatsStore.shared.todayReadingMinutes()
        DebugLogger.info(
            "[LiveActivityFlow] Reminder tap request accepted. Preparing to start Live Activity. " +
            "requestID=\(requestID), goalMinutes=\(appSettings.dailyReadingGoal), " +
            "minutesReadToday=\(minutesReadToday), " +
            "reminder=\(appSettings.readingReminderHour):\(String(format: "%02d", appSettings.readingReminderMinute))"
        )
        Task {
            await ReadingLiveActivityManager.shared.startForTonightIfNeeded(
                goalMinutes: appSettings.dailyReadingGoal,
                minutesReadToday: minutesReadToday,
                reminderHour: appSettings.readingReminderHour,
                reminderMinute: appSettings.readingReminderMinute,
                deepLink: ReadingReminderConstants.defaultDeepLink
            )
        }
    }

    private func openStore(for prompt: AppUpdatePrompt) {
        openURL(prompt.appStoreURL) { accepted in
            guard !accepted else { return }
            guard let fallbackURL = Self.makeStoreFallbackURL(from: prompt.appStoreURL) else { return }
            openURL(fallbackURL)
        }
    }

    private static func makeStoreFallbackURL(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == "itms-apps" else { return nil }
        let raw = url.absoluteString
        let fallbackRaw = raw.replacingOccurrences(of: "itms-apps://", with: "https://")
        return URL(string: fallbackRaw)
    }
}

struct SidebarView: View {
    @State private var selectedTab: SidebarTab = .library
    
    enum SidebarTab: String, CaseIterable {
        case library = "library"
        case progress = "progress"
        case settings = "settings"
        
        var titleKey: String {
            switch self {
            case .library:
                return NSLocalizedString("tab.library", comment: "")
            case .progress:
                return NSLocalizedString("tab.progress", comment: "")
            case .settings:
                return NSLocalizedString("tab.settings", comment: "")
            }
        }
        
        var icon: String {
            switch self {
            case .library:
                return "books.vertical"
            case .progress:
                return "chart.line.uptrend.xyaxis"
            case .settings:
                return "gearshape"
            }
        }
    }
    
    var body: some View {
        List(SidebarTab.allCases, id: \.rawValue) { tab in
            NavigationLink(destination: destinationView(for: tab)) {
                Label(tab.titleKey, systemImage: tab.icon)
            }
        }
        .navigationTitle(NSLocalizedString("app.name", comment: "App name"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
    
    @ViewBuilder
    private func destinationView(for tab: SidebarTab) -> some View {
        switch tab {
        case .library:
            LibraryView()
        case .progress:
            ReadingProgressView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(NotionSessionManager.shared)
}
