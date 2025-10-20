//
//  MainTabView.swift
//  Isla Reader
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
                            Text("书架")
                        }
                    
                    ReadingProgressView()
                        .tabItem {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text("进度")
                        }
                    
                    SettingsView()
                        .tabItem {
                            Image(systemName: "gearshape")
                            Text("设置")
                        }
                }
                .accentColor(.primary)
            }
        }
        .preferredColorScheme(appSettings.theme.colorScheme)
    }
}

struct SidebarView: View {
    @State private var selectedTab: SidebarTab = .library
    
    enum SidebarTab: String, CaseIterable {
        case library = "library"
        case progress = "progress"
        case settings = "settings"
        
        var title: String {
            switch self {
            case .library:
                return "书架"
            case .progress:
                return "进度"
            case .settings:
                return "设置"
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
                Label(tab.title, systemImage: tab.icon)
            }
        }
        .navigationTitle("Isla Reader")
        .navigationBarTitleDisplayMode(.large)
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