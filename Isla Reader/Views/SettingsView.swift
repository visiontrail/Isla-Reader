//
//  SettingsView.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var aiConsentManager = AIConsentManager.shared
    @EnvironmentObject private var notionSessionManager: NotionSessionManager
    @State private var showingAbout = false
    @State private var showingDataManagement = false
    @State private var showingNotionAuth = false
    @State private var reminderAlert: DataAlert?
    @State private var aiProviderDisplayText = NSLocalizedString("settings.ai_privacy.provider_loading", comment: "")
    private let settingsRowIconSpacing: CGFloat = 12
    private let settingsRowIconWidth: CGFloat = 20
    
    var body: some View {
        NavigationStack {
            List {
                // Language
                Section(NSLocalizedString("settings.language", comment: "")) {
                    HStack {
                        settingsRowLabel(
                            NSLocalizedString("settings.language", comment: ""),
                            systemImage: "globe"
                        )
                        Spacer()
                        Picker("", selection: $appSettings.language) {
                            ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    HStack {
                        settingsRowLabel(
                            NSLocalizedString("settings.translation.target_language", comment: ""),
                            systemImage: "character.bubble"
                        )
                        Spacer()
                        Picker("", selection: $appSettings.translationLanguage) {
                            ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                // Reading Settings
                Section(NSLocalizedString("reading.settings.title", comment: "")) {
                    NavigationLink(destination: ReadingSettingsView()) {
                        settingsRowLabel(
                            NSLocalizedString("settings.reading_preferences", comment: ""),
                            systemImage: "textformat"
                        )
                    }
                    
                    NavigationLink(destination: ThemeSettingsView()) {
                        settingsRowLabel(
                            NSLocalizedString("settings.theme.appearance", comment: ""),
                            systemImage: "paintbrush"
                        )
                    }

                    NavigationLink(destination: HighlightSortSettingsView()) {
                        settingsRowLeading(systemImage: "arrow.up.arrow.down") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("settings.highlight_sort.title", comment: ""))
                                    .foregroundColor(.primary)
                                Text(highlightSortSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if appSettings.areAdsEnabled {
                        Toggle(isOn: $appSettings.isAIAdvanceAdNoticeEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("settings.ai_ad_notice", comment: ""))
                                Text(NSLocalizedString("settings.ai_ad_notice.description", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Data & Sync
                Section(NSLocalizedString("settings.data_and_sync", comment: "")) {
                    Button(action: { showingNotionAuth = true }) {
                        HStack(spacing: settingsRowIconSpacing) {
                            NotionWorkspaceIconView(iconValue: notionSessionManager.workspaceIcon, size: 20)
                                .frame(width: settingsRowIconWidth, alignment: .center)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("notion.connect", comment: ""))
                                    .foregroundColor(.primary)
                                notionConnectionSubtitle
                            }

                            Spacer()
                            notionConnectionAccessory
                        }
                    }

                    Button(action: { showingDataManagement = true }) {
                        settingsRowLabel(
                            NSLocalizedString("settings.data_management", comment: ""),
                            systemImage: "externaldrive"
                        )
                    }
                }

                Section(NSLocalizedString("settings.ai_privacy.section", comment: "")) {
                    Button(action: {
                        Task { @MainActor in
                            aiConsentManager.presentLaunchConsentManually()
                        }
                    }) {
                        settingsRowLeading(systemImage: "shield.lefthalf.filled") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("settings.ai_privacy.manage_title", comment: ""))
                                    .foregroundColor(.primary)
                                Text(aiPermissionStatusText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    HStack(spacing: settingsRowIconSpacing) {
                        Image(systemName: "building.2")
                            .foregroundColor(.secondary)
                            .frame(width: settingsRowIconWidth, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.ai_privacy.provider_label", comment: ""))
                            Text(aiProviderDisplayText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: privacyPolicyURL) {
                        settingsRowLabel(
                            NSLocalizedString("app.privacy_policy", comment: ""),
                            systemImage: "hand.raised"
                        )
                    }
                }
                
                // Notifications
                Section(NSLocalizedString("settings.notifications", comment: "")) {
                    HStack {
                        settingsRowLabel(
                            NSLocalizedString("reading_reminder.daily", comment: ""),
                            systemImage: "bell"
                        )
                        Spacer()
                        Toggle("", isOn: $appSettings.isReadingReminderEnabled)
                    }
                    
                    if appSettings.isReadingReminderEnabled {
                        HStack {
                            Text(NSLocalizedString("reading_reminder.time", comment: ""))
                            Spacer()
                            DatePicker(
                                "",
                                selection: reminderTimeBinding,
                                displayedComponents: [.hourAndMinute]
                            )
                            .labelsHidden()
                        }
                    }

                    Stepper(value: $appSettings.dailyReadingGoal, in: 10...180, step: 5) {
                        HStack {
                            Text(NSLocalizedString("settings.daily_goal", comment: ""))
                            Spacer()
                            Text("\(appSettings.dailyReadingGoal) \(NSLocalizedString("common.minutes", comment: ""))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // About
                Section(NSLocalizedString("settings.about", comment: "")) {
                    Button(action: { showingAbout = true }) {
                        settingsRowLabel(
                            NSLocalizedString("app.about.title", comment: ""),
                            systemImage: "info.circle"
                        )
                    }
                    
                    HStack {
                        settingsRowLabel(
                            NSLocalizedString("app.version", comment: ""),
                            systemImage: "number"
                        )
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Support
                Section(NSLocalizedString("settings.support", comment: "")) {
                    Link(destination: URL(string: "mailto:support@isla-reader.top")!) {
                        settingsRowLabel(
                            NSLocalizedString("app.contact_us", comment: ""),
                            systemImage: "envelope"
                        )
                    }
                    
                    Link(destination: URL(string: "https://isla-reader.top/privacy")!) {
                        settingsRowLabel(
                            NSLocalizedString("app.privacy_policy", comment: ""),
                            systemImage: "hand.raised"
                        )
                    }
                }
            }
            .navigationTitle(NSLocalizedString("tab.settings", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingDataManagement) {
                DataManagementView()
            }
            .sheet(isPresented: $showingNotionAuth) {
                NotionAuthView()
            }
            .alert(item: $reminderAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(NSLocalizedString("common.done", comment: "")))
                )
            }
            .onAppear {
                loadAIProviderDisclosure()
                Task {
                    let hasPermission = await ReadingReminderService.shared.refreshReminderIfNeeded(
                        isEnabled: appSettings.isReadingReminderEnabled,
                        goalMinutes: appSettings.dailyReadingGoal,
                        hour: appSettings.readingReminderHour,
                        minute: appSettings.readingReminderMinute
                    )
                    
                    if !hasPermission && appSettings.isReadingReminderEnabled {
                        await MainActor.run {
                            appSettings.isReadingReminderEnabled = false
                            reminderAlert = DataAlert(
                                title: NSLocalizedString("settings.reading_reminder", comment: ""),
                                message: NSLocalizedString("reading_reminder.permission_denied", comment: "")
                            )
                        }
                    }
                }
            }
            .onChange(of: appSettings.isReadingReminderEnabled) { isEnabled in
                Task {
                    if isEnabled {
                        let granted = await ReadingReminderService.shared.enableDailyReminder(
                            goalMinutes: appSettings.dailyReadingGoal,
                            hour: appSettings.readingReminderHour,
                            minute: appSettings.readingReminderMinute
                        )
                        
                        if !granted {
                            await MainActor.run {
                                appSettings.isReadingReminderEnabled = false
                                reminderAlert = DataAlert(
                                    title: NSLocalizedString("settings.reading_reminder", comment: ""),
                                    message: NSLocalizedString("reading_reminder.permission_denied", comment: "")
                                )
                            }
                        }
                    } else {
                        ReadingReminderService.shared.cancelReminder()
                    }
                }
            }
            .onChange(of: appSettings.dailyReadingGoal) { newGoal in
                Task {
                    let hasPermission = await ReadingReminderService.shared.refreshReminderIfNeeded(
                        isEnabled: appSettings.isReadingReminderEnabled,
                        goalMinutes: newGoal,
                        hour: appSettings.readingReminderHour,
                        minute: appSettings.readingReminderMinute
                    )
                    
                    if !hasPermission && appSettings.isReadingReminderEnabled {
                        await MainActor.run {
                            appSettings.isReadingReminderEnabled = false
                            reminderAlert = DataAlert(
                                title: NSLocalizedString("settings.reading_reminder", comment: ""),
                                message: NSLocalizedString("reading_reminder.permission_denied", comment: "")
                            )
                        }
                    }
                }
            }
            .onChange(of: appSettings.readingReminderMinutesSinceMidnight) { _ in
                Task {
                    let hasPermission = await ReadingReminderService.shared.refreshReminderIfNeeded(
                        isEnabled: appSettings.isReadingReminderEnabled,
                        goalMinutes: appSettings.dailyReadingGoal,
                        hour: appSettings.readingReminderHour,
                        minute: appSettings.readingReminderMinute
                    )

                    if !hasPermission && appSettings.isReadingReminderEnabled {
                        await MainActor.run {
                            appSettings.isReadingReminderEnabled = false
                            reminderAlert = DataAlert(
                                title: NSLocalizedString("settings.reading_reminder", comment: ""),
                                message: NSLocalizedString("reading_reminder.permission_denied", comment: "")
                            )
                        }
                    }
                }
            }
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { appSettings.readingReminderTime },
            set: { appSettings.setReadingReminderTime($0) }
        )
    }

    private func settingsRowLabel(_ title: String, systemImage: String) -> some View {
        settingsRowLeading(systemImage: systemImage) {
            Text(title)
                .foregroundColor(.primary)
        }
    }

    private func settingsRowLeading<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: settingsRowIconSpacing) {
            Image(systemName: systemImage)
                .foregroundColor(.accentColor)
                .frame(width: settingsRowIconWidth, alignment: .center)
            content()
        }
    }

    private var highlightSortSubtitle: String {
        let format = NSLocalizedString("settings.highlight_sort.subtitle_format", comment: "Highlight sort summary in settings")
        return String(format: format, appSettings.highlightSortMode.displayName)
    }

    @ViewBuilder
    private var notionConnectionSubtitle: some View {
        switch notionSessionManager.connectionState {
        case .connected(let workspaceName):
            Text(workspaceName)
                .font(.caption)
                .foregroundColor(.secondary)
        case .connecting:
            Text(NSLocalizedString("notion.connection.connecting", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        case .disconnected:
            Text(NSLocalizedString("notion.connection.disconnected", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var notionConnectionAccessory: some View {
        switch notionSessionManager.connectionState {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        case .disconnected:
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://isla-reader.top/privacy")!
    }

    private var aiPermissionStatusText: String {
        aiConsentManager.isPermissionGranted()
        ? NSLocalizedString("settings.ai_privacy.status_allowed", comment: "")
        : NSLocalizedString("settings.ai_privacy.status_not_allowed", comment: "")
    }

    private func loadAIProviderDisclosure() {
        Task {
            let descriptor = await AIConfig.currentProviderDescriptor()
            await MainActor.run {
                if descriptor.isUnknown {
                    aiProviderDisplayText = NSLocalizedString("settings.ai_privacy.provider_unknown", comment: "")
                } else {
                    var disclosureText = descriptor.displayNameWithHost
                    if let endpointLocation = descriptor.endpointLocation {
                        let locationDescription = NSLocalizedString(endpointLocation.descriptionLocalizationKey, comment: "")
                        let locationFormat = NSLocalizedString("settings.ai_privacy.provider_location_format", comment: "")
                        disclosureText += "\n" + String(format: locationFormat, locationDescription)
                    }
                    aiProviderDisplayText = disclosureText
                }
            }
        }
    }
}

private struct DataAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ReadingSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    
    var body: some View {
        List {
            Section(NSLocalizedString("settings.font.title", comment: "")) {
                HStack {
                    Text(NSLocalizedString("settings.font.size", comment: ""))
                    Spacer()
                    Picker(NSLocalizedString("settings.font.size", comment: ""), selection: $appSettings.readingFontSize) {
                        ForEach(ReadingFontSize.allCases, id: \.rawValue) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                HStack {
                    Text(NSLocalizedString("settings.font.type", comment: ""))
                    Spacer()
                    Picker(NSLocalizedString("settings.font.type", comment: ""), selection: $appSettings.readingFont) {
                        ForEach(ReadingFont.allCases, id: \.rawValue) { font in
                            Text(font.displayName).tag(font)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            
            Section(NSLocalizedString("settings.typography.title", comment: "")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("settings.typography.line_spacing", comment: ""))
                        Spacer()
                        Text(String(format: "%.1f", appSettings.lineSpacing))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: $appSettings.lineSpacing,
                        in: AppSettings.lineSpacingRange,
                        step: AppSettings.lineSpacingStep
                    )
                        .accentColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("settings.typography.page_margins", comment: ""))
                        Spacer()
                        Text("\(Int(appSettings.pageMargins))pt")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: $appSettings.pageMargins,
                        in: AppSettings.pageMarginsRange,
                        step: AppSettings.pageMarginsStep
                    )
                        .accentColor(.blue)
                }
            }
            
            Section(NSLocalizedString("settings.preview", comment: "")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("settings.sample_text.label", comment: ""))
                        .font(.headline)
                    
                    Text(NSLocalizedString("settings.sample_text.content", comment: ""))
                        .font(.system(size: appSettings.readingFontSize.fontSize))
                        .lineSpacing(appSettings.lineSpacing * 4)
                        .padding(.horizontal, appSettings.pageMargins / 2)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
        .navigationTitle(NSLocalizedString("settings.reading_preferences", comment: ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct ThemeSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    
    var body: some View {
        List {
            Section(NSLocalizedString("settings.theme.selection", comment: "")) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(theme.displayName)
                                .font(.body)
                            
                            Text(themeDescription(theme))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if appSettings.theme == theme {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appSettings.theme = theme
                    }
                }
            }
            
            Section(NSLocalizedString("settings.theme.preview", comment: "")) {
                VStack(spacing: 16) {
                    HStack {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 20, height: 20)
                        
                        Text(NSLocalizedString("settings.theme.primary_text_color", comment: ""))
                            .font(.body)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 20, height: 20)
                        
                        Text(NSLocalizedString("settings.theme.secondary_text_color", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 20, height: 20)
                        
                        Text(NSLocalizedString("settings.theme.accent_color", comment: ""))
                            .font(.body)
                            .foregroundColor(.accentColor)
                        
                        Spacer()
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .navigationTitle(NSLocalizedString("settings.theme.appearance", comment: ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    private func themeDescription(_ theme: AppTheme) -> String {
        switch theme {
        case .system:
            return NSLocalizedString("settings.theme.mode.follow_system", comment: "")
        case .light:
            return NSLocalizedString("settings.theme.mode.always_light", comment: "")
        case .dark:
            return NSLocalizedString("settings.theme.mode.always_dark", comment: "")
        }
    }
}

struct HighlightSortSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared

    var body: some View {
        List {
            Section(
                footer: Text(NSLocalizedString("settings.highlight_sort.sync_note", comment: ""))
            ) {
                ForEach(HighlightSortMode.allCases, id: \.rawValue) { mode in
                    HStack {
                        Text(mode.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                        if appSettings.highlightSortMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appSettings.highlightSortMode = mode
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("settings.highlight_sort.title", comment: ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingClearDataAlert = false
    @State private var showingExportView = false
    @State private var alertItem: DataAlert?
    @State private var showingImportPicker = false
    @State private var isImporting = false
    @State private var importSummary: String?
    @State private var cacheUsage: CacheUsage?
    @State private var isCalculatingCache = false
    @State private var isClearingCache = false
    @State private var isClearingAllData = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(NSLocalizedString("settings.data.export_section", comment: "")) {
                    Button(action: { showingExportView = true }) {
                        Label(NSLocalizedString("settings.export.all_data_button", comment: ""), systemImage: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }

                    Text(NSLocalizedString("export.all_data.description", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Section(NSLocalizedString("settings.data.import_section", comment: "")) {
                    Button(action: { showingImportPicker = true }) {
                        Label(NSLocalizedString("settings.import.reading_data", comment: ""), systemImage: "square.and.arrow.down")
                            .foregroundColor(.blue)
                    }
                    .disabled(isImporting)
                    
                    if let importSummary {
                        Text(importSummary)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    if isImporting {
                        ProgressView(NSLocalizedString("import.reading_data.in_progress", comment: ""))
                    }
                }
                
                Section(NSLocalizedString("settings.storage_management", comment: "")) {
                    HStack {
                        Label(NSLocalizedString("settings.cache.size", comment: ""), systemImage: "internaldrive")
                        Spacer()
                        if isClearingCache {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(NSLocalizedString("cache.status.clearing", comment: ""))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(cacheStatusText)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: clearCache) {
                        HStack {
                            Label(NSLocalizedString("settings.cache.clear", comment: ""), systemImage: "trash")
                                .foregroundColor(.orange)
                            if isClearingCache {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isClearingCache || isCalculatingCache)
                }
                
                Section(NSLocalizedString("settings.danger_zone", comment: "")) {
                    Button(action: { showingClearDataAlert = true }) {
                        HStack {
                            Label(NSLocalizedString("settings.data.clear_all", comment: ""), systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            if isClearingAllData {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isClearingAllData || isClearingCache || isCalculatingCache || isImporting)
                }
            }
            .navigationTitle(NSLocalizedString("settings.data_management", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
                #endif
            }
            .confirmationDialog(NSLocalizedString("settings.data.clear_all", comment: ""), isPresented: $showingClearDataAlert, titleVisibility: .visible) {
                Button(NSLocalizedString("settings.data.clear_confirm", comment: ""), role: .destructive) {
                    performClearAllData()
                }
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("settings.data.clear_warning", comment: ""))
            }
            .sheet(isPresented: $showingExportView) {
                ExportDataView()
            }
            .alert(item: $alertItem) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: "")))
                )
            }
            .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    handleImport(url)
                case .failure(let error):
                    alertItem = DataAlert(
                        title: NSLocalizedString("settings.import.failed", comment: ""),
                        message: error.localizedDescription
                    )
                }
            }
            .task {
                refreshCacheUsage()
            }
        }
    }
    
    private func handleImport(_ url: URL) {
        isImporting = true
        importSummary = nil
        
        Task {
            var needsStopAccessing = false
            #if os(iOS)
            needsStopAccessing = url.startAccessingSecurityScopedResource()
            #endif
            defer {
                #if os(iOS)
                if needsStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
                #endif
            }
            
            do {
                let result = try await DataBackupService.shared.importReadingData(from: url, context: viewContext)
                let summary = String(
                    format: NSLocalizedString("import.reading_data.result_format", comment: ""),
                    result.matchedBooks,
                    result.updatedProgress,
                    result.updatedBookmarks,
                    result.skippedBooks
                )
                
                await MainActor.run {
                    importSummary = summary
                    alertItem = DataAlert(
                        title: NSLocalizedString("library.import.result.title", comment: ""),
                        message: summary
                    )
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    alertItem = DataAlert(
                        title: NSLocalizedString("settings.import.failed", comment: ""),
                        message: error.localizedDescription
                    )
                    isImporting = false
                }
            }
        }
    }
    
    private func refreshCacheUsage() {
        isCalculatingCache = true
        
        Task {
            let usage = await CacheCleanupService.shared.currentUsage(context: viewContext)
            await MainActor.run {
                cacheUsage = usage
                isCalculatingCache = false
            }
        }
    }
    
    private func clearCache() {
        guard !isClearingCache else { return }
        isClearingCache = true
        let previousBytes = cacheUsage?.totalBytes ?? 0
        
        Task {
            do {
                let usage = try await CacheCleanupService.shared.clearCaches(context: viewContext)
                let freedBytes = max(0, previousBytes - usage.totalBytes)
                let message = String(
                    format: NSLocalizedString("cache.clear.success_message", comment: ""),
                    CacheCleanupService.formattedSize(from: freedBytes)
                )
                
                await MainActor.run {
                    cacheUsage = usage
                    alertItem = DataAlert(
                        title: NSLocalizedString("settings.cache.cleared", comment: ""),
                        message: message
                    )
                    isClearingCache = false
                    isCalculatingCache = false
                }
            } catch {
                await MainActor.run {
                    alertItem = DataAlert(
                        title: NSLocalizedString("settings.cache.clear_failed", comment: ""),
                        message: error.localizedDescription
                    )
                    isClearingCache = false
                    isCalculatingCache = false
                }
            }
        }
    }
    
    private func performClearAllData() {
        guard !isClearingAllData else { return }
        isClearingAllData = true
        showingClearDataAlert = false
        
        Task {
            do {
                let result = try await DataResetService.shared.wipeAllData(context: viewContext)
                let message = String(
                    format: NSLocalizedString("data.clear.success_message", comment: ""),
                    result.removedBookCount,
                    result.formattedFreedSize
                )
                
                await MainActor.run {
                    cacheUsage = CacheUsage(cacheDirectoryBytes: 0, aiSummaryBytes: 0, skimmingSummaryBytes: 0)
                    alertItem = DataAlert(
                        title: NSLocalizedString("data.clear.success_title", comment: ""),
                        message: message
                    )
                    importSummary = nil
                    isCalculatingCache = false
                    isClearingAllData = false
                }
            } catch {
                await MainActor.run {
                    alertItem = DataAlert(
                        title: NSLocalizedString("data.clear.failure_title", comment: ""),
                        message: error.localizedDescription
                    )
                    isCalculatingCache = false
                    isClearingAllData = false
                }
            }
        }
    }
    
    private var cacheStatusText: String {
        if isClearingCache {
            return NSLocalizedString("cache.status.clearing", comment: "")
        }
        if isCalculatingCache {
            return NSLocalizedString("cache.status.calculating", comment: "")
        }
        if let usage = cacheUsage {
            return CacheCleanupService.formattedSize(from: usage.totalBytes)
        }
        return "--"
    }
}

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportAlert: DataAlert?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "square.and.arrow.up.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text(NSLocalizedString("settings.export.all_data_button", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(NSLocalizedString("export.all_data.description", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Text(NSLocalizedString("export.notice.without_books", comment: ""))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if isExporting {
                    ProgressView(NSLocalizedString("export.in_progress", comment: ""))
                }
                
                if let exportURL {
                    VStack(spacing: 8) {
                        ShareLink(item: exportURL) {
                            Label(NSLocalizedString("export.share_file", comment: ""), systemImage: "square.and.arrow.up")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Text(exportURL.lastPathComponent)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Button(action: startExport) {
                    Text(NSLocalizedString("settings.export.start", comment: ""))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .disabled(isExporting)
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("settings.export.all_data_button", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(item: $exportAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: "")))
                )
            }
        }
    }
    
    private func startExport() {
        isExporting = true
        exportURL = nil
        
        Task {
            do {
                let url = try await DataBackupService.shared.exportAllDataExceptBooks(context: viewContext)
                
                await MainActor.run {
                    exportURL = url
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    exportAlert = DataAlert(title: NSLocalizedString("settings.export.failed", comment: ""), message: message)
                }
            }
            
            await MainActor.run {
                isExporting = false
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // App Icon
                Image("LanReadIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(radius: 6)
                
                VStack(spacing: 8) {
                    Text(NSLocalizedString("app.name", comment: "App name"))
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("\(NSLocalizedString("app.version", comment: "")) 1.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(NSLocalizedString("app.tagline", comment: ""))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 16) {
                    Text(NSLocalizedString("app.copyright", comment: "App copyright"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(NSLocalizedString("app.about.subtitle", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("settings.about", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
}

// MARK: - Notion Auth View

private struct NotionWorkspaceIconView: View {
    let iconValue: String?
    let size: CGFloat

    var body: some View {
        if let icon = normalizedIcon, icon.lowercased().hasPrefix("http"), let url = URL(string: icon) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                default:
                    fallbackIcon
                }
            }
        } else if let icon = normalizedIcon {
            Text(icon)
                .font(.system(size: size * 0.7))
                .frame(width: size, height: size)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        } else {
            fallbackIcon
        }
    }

    private var normalizedIcon: String? {
        let trimmed = iconValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var fallbackIcon: some View {
        Image("NotionIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct NotionAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notionSessionManager: NotionSessionManager
    @State private var alertContext: NotionAuthAlertContext?
    @State private var parentPageOptions: [NotionParentPageOption] = []
    @State private var showingPagePicker = false
    @State private var isLoadingParentPages = false
    @State private var isCreatingDatabase = false
    @State private var selectedParentPageID: String?
    @State private var hasAutoStartedInitialization = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                NotionWorkspaceIconView(iconValue: notionSessionManager.workspaceIcon, size: 60)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("notion.connect_to", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)

                    Text(NSLocalizedString("notion.auth.description", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                statusContent

                Button(action: requestAuthorizationConsent) {
                    HStack {
                        Image(systemName: "key.fill")
                        Text(authorizationButtonTitle)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isAuthorizationButtonDisabled ? Color.gray : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(isAuthorizationButtonDisabled)
                .padding(.horizontal)

                if notionSessionManager.isConnected {
                    Button(role: .destructive, action: requestDisconnectConfirmation) {
                        Text(NSLocalizedString("notion.connection.disconnect", comment: ""))
                            .font(.subheadline)
                    }
                }

                // 说明文本
                VStack(spacing: 8) {
                    Text(NSLocalizedString("notion.auth.privacy_notice", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Link(destination: privacyPolicyURL) {
                        Text(NSLocalizedString("app.privacy_policy", comment: ""))
                            .font(.footnote)
                            .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("notion.sync.title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }

                if notionSessionManager.isConnected {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("common.done", comment: "")) {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .alert(item: $alertContext) { context in
                switch context {
                case .info(let alert):
                    return Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text(NSLocalizedString("common.confirm", comment: "")))
                    )
                case .preAuthorizationNotice:
                    return Alert(
                        title: Text(NSLocalizedString("notion.auth.preflight.title", comment: "")),
                        message: Text(NSLocalizedString("notion.auth.preflight.message", comment: "")),
                        primaryButton: .default(Text(NSLocalizedString("notion.auth.preflight.confirm", comment: "")), action: startAuthorization),
                        secondaryButton: .cancel(Text(NSLocalizedString("notion.auth.preflight.cancel", comment: "")))
                    )
                case .disconnectConfirmation:
                    return Alert(
                        title: Text(NSLocalizedString("notion.disconnect.confirm.title", comment: "")),
                        message: Text(NSLocalizedString("notion.disconnect.confirm.message", comment: "")),
                        primaryButton: .destructive(Text(NSLocalizedString("notion.connection.disconnect", comment: "")), action: disconnectNotion),
                        secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "")))
                    )
                }
            }
            .onChange(of: notionSessionManager.connectionState) { state in
                switch state {
                case .error(let message):
                    alertContext = .info(DataAlert(
                        title: NSLocalizedString("notion.auth.failed", comment: ""),
                        message: message
                    ))
                case .connected:
                    triggerInitializationIfNeeded(force: true)
                case .connecting, .disconnected:
                    hasAutoStartedInitialization = false
                    showingPagePicker = false
                }
            }
            .onChange(of: notionSessionManager.isInitialized) { isInitialized in
                if isInitialized {
                    showingPagePicker = false
                }
            }
            .onAppear {
                triggerInitializationIfNeeded(force: false)
            }
            .sheet(isPresented: $showingPagePicker) {
                NotionParentPagePickerView(
                    pages: parentPageOptions,
                    isRefreshing: isLoadingParentPages,
                    isSubmitting: isCreatingDatabase,
                    selectedPageID: selectedParentPageID,
                    onRefresh: { fetchParentPages(force: true) },
                    onSelect: selectParentPage,
                    onClose: { showingPagePicker = false }
                )
                .interactiveDismissDisabled(isCreatingDatabase)
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch notionSessionManager.connectionState {
        case .connected(let workspaceName):
            if notionSessionManager.isInitialized {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)

                    Text(NSLocalizedString("notion.init.status.completed", comment: ""))
                        .font(.headline)
                        .foregroundColor(.green)

                    HStack(spacing: 8) {
                        NotionWorkspaceIconView(iconValue: notionSessionManager.workspaceIcon, size: 20)
                        Text(String(format: NSLocalizedString("notion.connection.current_workspace", comment: ""), workspaceName))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(spacing: 12) {
                    if isLoadingParentPages {
                        ProgressView()
                        Text(NSLocalizedString("notion.init.loading_pages", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if isCreatingDatabase {
                        ProgressView()
                        Text(NSLocalizedString("notion.init.creating_database", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)

                        Text(NSLocalizedString("notion.init.status.pending", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { fetchParentPages(force: true) }) {
                            Text(NSLocalizedString("notion.init.pick_page.button", comment: ""))
                                .font(.footnote)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(12)
            }
        case .connecting:
            VStack(spacing: 12) {
                ProgressView()
                Text(NSLocalizedString("notion.connection.connecting", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .error(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.orange)
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.red)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        case .disconnected:
            EmptyView()
        }
    }

    private var authorizationButtonTitle: String {
        switch notionSessionManager.connectionState {
        case .connected:
            return NSLocalizedString("notion.auth.reauthorize", comment: "")
        default:
            return NSLocalizedString("notion.auth.start", comment: "")
        }
    }

    private var isAuthorizationButtonDisabled: Bool {
        notionSessionManager.isConnecting || isLoadingParentPages || isCreatingDatabase
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://isla-reader.top/privacy")!
    }

    private func requestAuthorizationConsent() {
        guard !isAuthorizationButtonDisabled else {
            return
        }
        alertContext = .preAuthorizationNotice
    }

    private func startAuthorization() {
        hasAutoStartedInitialization = false
        parentPageOptions = []
        showingPagePicker = false
        notionSessionManager.startAuthorization()
    }

    private func requestDisconnectConfirmation() {
        alertContext = .disconnectConfirmation
    }

    private func disconnectNotion() {
        hasAutoStartedInitialization = false
        parentPageOptions = []
        selectedParentPageID = nil
        showingPagePicker = false
        notionSessionManager.disconnect()
    }

    private func triggerInitializationIfNeeded(force: Bool) {
        guard notionSessionManager.isConnected else {
            return
        }

        guard !notionSessionManager.isInitialized else {
            return
        }

        if !force && hasAutoStartedInitialization {
            return
        }

        hasAutoStartedInitialization = true
        fetchParentPages(force: force)
    }

    private func fetchParentPages(force: Bool) {
        guard notionSessionManager.isConnected else {
            return
        }

        guard !notionSessionManager.isInitialized else {
            showingPagePicker = false
            return
        }

        if isLoadingParentPages {
            return
        }

        if !force && !parentPageOptions.isEmpty {
            showingPagePicker = true
            return
        }

        isLoadingParentPages = true

        Task {
            do {
                let pages = try await notionSessionManager.fetchParentPagesForInitialization()
                await MainActor.run {
                    parentPageOptions = pages
                    showingPagePicker = true
                    isLoadingParentPages = false
                }
            } catch {
                await MainActor.run {
                    isLoadingParentPages = false
                    alertContext = .info(DataAlert(
                        title: NSLocalizedString("notion.init.error.title", comment: ""),
                        message: error.localizedDescription
                    ))
                }
            }
        }
    }

    private func selectParentPage(_ page: NotionParentPageOption) {
        guard !isCreatingDatabase else {
            return
        }

        isCreatingDatabase = true
        selectedParentPageID = page.id

        Task {
            do {
                try await notionSessionManager.initializeLibraryDatabase(parentPageID: page.id)
                await MainActor.run {
                    isCreatingDatabase = false
                    selectedParentPageID = nil
                    showingPagePicker = false
                }
            } catch let error as NotionInitializationError {
                await MainActor.run {
                    isCreatingDatabase = false
                    selectedParentPageID = nil

                    if error == .permissionDenied {
                        alertContext = .info(DataAlert(
                            title: NSLocalizedString("notion.init.error.permission_denied", comment: ""),
                            message: NSLocalizedString("notion.init.error.permission_denied.detail", comment: "")
                        ))
                    } else {
                        alertContext = .info(DataAlert(
                            title: NSLocalizedString("notion.init.error.title", comment: ""),
                            message: error.localizedDescription
                        ))
                    }

                    showingPagePicker = true
                }
            } catch {
                await MainActor.run {
                    isCreatingDatabase = false
                    selectedParentPageID = nil
                    alertContext = .info(DataAlert(
                        title: NSLocalizedString("notion.init.error.title", comment: ""),
                        message: error.localizedDescription
                    ))
                    showingPagePicker = true
                }
            }
        }
    }
}

private enum NotionAuthAlertContext: Identifiable {
    case info(DataAlert)
    case preAuthorizationNotice
    case disconnectConfirmation

    var id: String {
        switch self {
        case .info(let alert):
            return "info-\(alert.id.uuidString)"
        case .preAuthorizationNotice:
            return "pre-authorization-notice"
        case .disconnectConfirmation:
            return "disconnect-confirmation"
        }
    }
}

private struct NotionParentPagePickerView: View {
    let pages: [NotionParentPageOption]
    let isRefreshing: Bool
    let isSubmitting: Bool
    let selectedPageID: String?
    let onRefresh: () -> Void
    let onSelect: (NotionParentPageOption) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isRefreshing && pages.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(NSLocalizedString("notion.init.loading_pages", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("notion.init.page.empty", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(pages) { page in
                        Button(action: { onSelect(page) }) {
                            HStack(spacing: 10) {
                                NotionWorkspaceIconView(iconValue: page.icon, size: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    if let subtitle = page.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if isSubmitting && selectedPageID == page.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(isSubmitting)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("notion.init.pick_page.title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        onClose()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("notion.common.refresh", comment: "")) {
                        onRefresh()
                    }
                    .disabled(isRefreshing || isSubmitting)
                }
            }
            .safeAreaInset(edge: .top) {
                Text(NSLocalizedString("notion.init.pick_page.description", comment: ""))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(NotionSessionManager.shared)
}
