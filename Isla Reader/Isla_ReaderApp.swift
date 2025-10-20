//
//  Isla_ReaderApp.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI

@main
struct Isla_ReaderApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var appSettings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.locale, appSettings.locale)
        }
    }
}
