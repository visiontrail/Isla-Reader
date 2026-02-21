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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedPhoneTab: PhoneTab = .library
    @State private var handledContinueReadingRequestID = 0
    @State private var handledReminderTapRequestID = 0
    
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
                            Text(NSLocalizedString("书架", comment: ""))
                        }
                    
                    ReadingProgressView()
                        .tag(PhoneTab.progress)
                        .tabItem {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text(NSLocalizedString("进度", comment: ""))
                        }
                    
                    SettingsView()
                        .tag(PhoneTab.settings)
                        .tabItem {
                            Image(systemName: "gearshape")
                            Text(NSLocalizedString("设置", comment: ""))
                        }
                }
            }
        }
        .tint(.blue)
        .preferredColorScheme(appSettings.theme.colorScheme)
        .onChange(of: reminderCoordinator.continueReadingRequestID) { _ in
            processPendingContinueReadingRequestIfNeeded()
        }
        .onChange(of: reminderCoordinator.reminderTapRequestID) { _ in
            processPendingReminderTapIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            processPendingContinueReadingRequestIfNeeded()
            processPendingReminderTapIfNeeded()
        }
        .onOpenURL { url in
            guard ReadingReminderService.shared.isContinueReadingURL(url) else {
                return
            }
            reminderCoordinator.requestContinueReading(triggeredByReminder: false)
        }
    }

    private func processPendingContinueReadingRequestIfNeeded() {
        guard scenePhase == .active else { return }
        let requestID = reminderCoordinator.continueReadingRequestID
        guard requestID > handledContinueReadingRequestID else { return }

        handledContinueReadingRequestID = requestID
        selectedPhoneTab = .library
        DebugLogger.info("MainTabView: Handled continue reading request and navigated to library.")
    }

    private func processPendingReminderTapIfNeeded() {
        guard scenePhase == .active else { return }
        let requestID = reminderCoordinator.reminderTapRequestID
        guard requestID > handledReminderTapRequestID else { return }

        handledReminderTapRequestID = requestID
        Task {
            await ReadingLiveActivityManager.shared.startForTonightIfNeeded(
                goalMinutes: appSettings.dailyReadingGoal,
                minutesReadToday: 0,
                reminderHour: appSettings.readingReminderHour,
                reminderMinute: appSettings.readingReminderMinute,
                deepLink: ReadingReminderConstants.defaultDeepLink
            )
        }
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
                return NSLocalizedString("书架", comment: "")
            case .progress:
                return NSLocalizedString("进度", comment: "")
            case .settings:
                return NSLocalizedString("设置", comment: "")
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
