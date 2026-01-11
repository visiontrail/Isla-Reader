//
//  MainTabView.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
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
                TabView {
                    LibraryView()
                        .tabItem {
                            Image(systemName: "books.vertical")
                            Text(NSLocalizedString("书架", comment: ""))
                        }
                    
                    ReadingProgressView()
                        .tabItem {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text(NSLocalizedString("进度", comment: ""))
                        }
                    
                    SettingsView()
                        .tabItem {
                            Image(systemName: "gearshape")
                            Text(NSLocalizedString("设置", comment: ""))
                        }
                }
            }
        }
        .tint(.blue)
        .preferredColorScheme(appSettings.theme.colorScheme)
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
}
