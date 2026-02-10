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
    @EnvironmentObject private var notionSessionManager: NotionSessionManager
    @State private var showingAbout = false
    @State private var showingDataManagement = false
    @State private var showingNotionAuth = false
    @State private var reminderAlert: DataAlert?
    
    var body: some View {
        NavigationStack {
            List {
                // Language
                Section(NSLocalizedString("语言", comment: "")) {
                    HStack {
                        Label("", systemImage: "globe")
                        Text(NSLocalizedString("语言", comment: ""))
                        Spacer()
                        Picker("", selection: $appSettings.language) {
                            ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    HStack {
                        Label("", systemImage: "character.bubble")
                        Text(NSLocalizedString("翻译目标语言", comment: ""))
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
                Section(NSLocalizedString("阅读设置", comment: "")) {
                    NavigationLink(destination: ReadingSettingsView()) {
                        Label(NSLocalizedString("阅读偏好", comment: ""), systemImage: "textformat")
                    }
                    
                    NavigationLink(destination: ThemeSettingsView()) {
                        Label(NSLocalizedString("主题外观", comment: ""), systemImage: "paintbrush")
                    }
                }
                
                // Data & Sync
                Section(NSLocalizedString("数据与同步", comment: "")) {
                    Button(action: { showingNotionAuth = true }) {
                        HStack(spacing: 12) {
                            NotionWorkspaceIconView(iconValue: notionSessionManager.workspaceIcon, size: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("连接 Notion", comment: ""))
                                    .foregroundColor(.primary)
                                notionConnectionSubtitle
                            }

                            Spacer()
                            notionConnectionAccessory
                        }
                    }

                    Button(action: { showingDataManagement = true }) {
                        Label(NSLocalizedString("数据管理", comment: ""), systemImage: "externaldrive")
                            .foregroundColor(.primary)
                    }
                }
                
                // Notifications
                Section(NSLocalizedString("通知提醒", comment: "")) {
                    HStack {
                        Label(NSLocalizedString("阅读提醒", comment: ""), systemImage: "bell")
                        Spacer()
                        Toggle("", isOn: $appSettings.isReadingReminderEnabled)
                    }
                    
                    if appSettings.isReadingReminderEnabled {
                        HStack {
                            Text(NSLocalizedString("每日目标", comment: ""))
                            Spacer()
                            Stepper("\(appSettings.dailyReadingGoal) \(NSLocalizedString("分钟", comment: ""))", 
                                   value: $appSettings.dailyReadingGoal, 
                                   in: 10...180, 
                                   step: 10)
                        }
                    }
                }
                
                // About
                Section(NSLocalizedString("关于", comment: "")) {
                    Button(action: { showingAbout = true }) {
                        Label(NSLocalizedString("app.about.title", comment: ""), systemImage: "info.circle")
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Label(NSLocalizedString("版本", comment: ""), systemImage: "number")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Support
                Section(NSLocalizedString("支持", comment: "")) {
                    Link(destination: URL(string: "mailto:guoliang88925@icloud.com")!) {
                        Label(NSLocalizedString("联系我们", comment: ""), systemImage: "envelope")
                    }
                    
                    Link(destination: URL(string: "https://isla-reader.top/privacy")!) {
                        Label(NSLocalizedString("隐私政策", comment: ""), systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle(NSLocalizedString("设置", comment: ""))
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
                    dismissButton: .default(Text(NSLocalizedString("完成", comment: "")))
                )
            }
            .onAppear {
                Task {
                    let hasPermission = await ReadingReminderService.shared.refreshReminderIfNeeded(
                        isEnabled: appSettings.isReadingReminderEnabled,
                        goalMinutes: appSettings.dailyReadingGoal
                    )
                    
                    if !hasPermission && appSettings.isReadingReminderEnabled {
                        await MainActor.run {
                            appSettings.isReadingReminderEnabled = false
                            reminderAlert = DataAlert(
                                title: NSLocalizedString("阅读提醒", comment: ""),
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
                            goalMinutes: appSettings.dailyReadingGoal
                        )
                        
                        if !granted {
                            await MainActor.run {
                                appSettings.isReadingReminderEnabled = false
                                reminderAlert = DataAlert(
                                    title: NSLocalizedString("阅读提醒", comment: ""),
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
                        goalMinutes: newGoal
                    )
                    
                    if !hasPermission && appSettings.isReadingReminderEnabled {
                        await MainActor.run {
                            appSettings.isReadingReminderEnabled = false
                            reminderAlert = DataAlert(
                                title: NSLocalizedString("阅读提醒", comment: ""),
                                message: NSLocalizedString("reading_reminder.permission_denied", comment: "")
                            )
                        }
                    }
                }
            }
        }
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
}

enum ExportCategory: String, Identifiable {
    case readingData
    case notesAndHighlights
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .readingData:
            return NSLocalizedString("导出阅读数据", comment: "")
        case .notesAndHighlights:
            return NSLocalizedString("导出笔记和高亮", comment: "")
        }
    }
    
    var description: String {
        switch self {
        case .readingData:
            return NSLocalizedString("export.reading_data.description", comment: "")
        case .notesAndHighlights:
            return NSLocalizedString("export.notes.description", comment: "")
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
            Section(NSLocalizedString("字体设置", comment: "")) {
                HStack {
                    Text(NSLocalizedString("字体大小", comment: ""))
                    Spacer()
                    Picker(NSLocalizedString("字体大小", comment: ""), selection: $appSettings.readingFontSize) {
                        ForEach(ReadingFontSize.allCases, id: \.rawValue) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                HStack {
                    Text(NSLocalizedString("字体类型", comment: ""))
                    Spacer()
                    Picker(NSLocalizedString("字体类型", comment: ""), selection: $appSettings.readingFont) {
                        ForEach(ReadingFont.allCases, id: \.rawValue) { font in
                            Text(font.displayName).tag(font)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            
            Section(NSLocalizedString("排版设置", comment: "")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("行间距", comment: ""))
                        Spacer()
                        Text(String(format: "%.1f", appSettings.lineSpacing))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $appSettings.lineSpacing, in: 1.0...2.0, step: 0.1)
                        .accentColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("页面边距", comment: ""))
                        Spacer()
                        Text("\(Int(appSettings.pageMargins))pt")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $appSettings.pageMargins, in: 10...40, step: 5)
                        .accentColor(.blue)
                }
            }
            
            Section(NSLocalizedString("预览", comment: "")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("示例文本", comment: ""))
                        .font(.headline)
                    
                    Text(NSLocalizedString("这是一段示例文本，用于预览当前的字体和排版设置效果。您可以调整上面的设置来获得最佳的阅读体验。", comment: ""))
                        .font(.system(size: appSettings.readingFontSize.fontSize))
                        .lineSpacing(appSettings.lineSpacing * 4)
                        .padding(.horizontal, appSettings.pageMargins / 2)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
        .navigationTitle(NSLocalizedString("阅读偏好", comment: ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct ThemeSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    
    var body: some View {
        List {
            Section(NSLocalizedString("主题选择", comment: "")) {
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
            
            Section(NSLocalizedString("主题预览", comment: "")) {
                VStack(spacing: 16) {
                    HStack {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 20, height: 20)
                        
                        Text(NSLocalizedString("主要文本颜色", comment: ""))
                            .font(.body)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 20, height: 20)
                        
                        Text(NSLocalizedString("次要文本颜色", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 20, height: 20)
                        
                        Text(NSLocalizedString("强调色", comment: ""))
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
        .navigationTitle(NSLocalizedString("主题外观", comment: ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    private func themeDescription(_ theme: AppTheme) -> String {
        switch theme {
        case .system:
            return NSLocalizedString("根据系统设置自动切换", comment: "")
        case .light:
            return NSLocalizedString("始终使用浅色主题", comment: "")
        case .dark:
            return NSLocalizedString("始终使用深色主题", comment: "")
        }
    }
}

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingClearDataAlert = false
    @State private var exportMode: ExportCategory?
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
                Section(NSLocalizedString("数据导出", comment: "")) {
                    Button(action: { exportMode = .readingData }) {
                        Label(NSLocalizedString("导出阅读数据", comment: ""), systemImage: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: { exportMode = .notesAndHighlights }) {
                        Label(NSLocalizedString("导出笔记和高亮", comment: ""), systemImage: "note.text")
                            .foregroundColor(.blue)
                    }
                    
                    Text(NSLocalizedString("export.notice.without_books", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Section(NSLocalizedString("数据导入", comment: "")) {
                    Button(action: { showingImportPicker = true }) {
                        Label(NSLocalizedString("导入阅读数据", comment: ""), systemImage: "square.and.arrow.down")
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
                
                Section(NSLocalizedString("存储管理", comment: "")) {
                    HStack {
                        Label(NSLocalizedString("缓存大小", comment: ""), systemImage: "internaldrive")
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
                            Label(NSLocalizedString("清理缓存", comment: ""), systemImage: "trash")
                                .foregroundColor(.orange)
                            if isClearingCache {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isClearingCache || isCalculatingCache)
                }
                
                Section(NSLocalizedString("危险操作", comment: "")) {
                    Button(action: { showingClearDataAlert = true }) {
                        HStack {
                            Label(NSLocalizedString("清除所有数据", comment: ""), systemImage: "exclamationmark.triangle")
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
            .navigationTitle(NSLocalizedString("数据管理", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                }
                #endif
            }
            .confirmationDialog(NSLocalizedString("清除所有数据", comment: ""), isPresented: $showingClearDataAlert, titleVisibility: .visible) {
                Button(NSLocalizedString("确认清除", comment: ""), role: .destructive) {
                    performClearAllData()
                }
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("此操作将删除所有书籍、阅读进度、笔记和设置。此操作不可撤销。", comment: ""))
            }
            .sheet(item: $exportMode) { mode in
                ExportDataView(mode: mode)
            }
            .alert(item: $alertItem) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(NSLocalizedString("确定", comment: "")))
                )
            }
            .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    handleImport(url)
                case .failure(let error):
                    alertItem = DataAlert(
                        title: NSLocalizedString("导入失败", comment: ""),
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
                        title: NSLocalizedString("导入结果", comment: ""),
                        message: summary
                    )
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    alertItem = DataAlert(
                        title: NSLocalizedString("导入失败", comment: ""),
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
                        title: NSLocalizedString("缓存已清理", comment: ""),
                        message: message
                    )
                    isClearingCache = false
                    isCalculatingCache = false
                }
            } catch {
                await MainActor.run {
                    alertItem = DataAlert(
                        title: NSLocalizedString("清理失败", comment: ""),
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
    
    let mode: ExportCategory
    
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
                    Text(mode.title)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(mode.description)
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
                    Text(NSLocalizedString("开始导出", comment: ""))
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
            .navigationTitle(mode.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(item: $exportAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(NSLocalizedString("确定", comment: "")))
                )
            }
        }
    }
    
    private func startExport() {
        isExporting = true
        exportURL = nil
        
        Task {
            do {
                let url: URL
                switch mode {
                case .readingData:
                    url = try await DataBackupService.shared.exportReadingData(context: viewContext)
                case .notesAndHighlights:
                    url = try await DataBackupService.shared.exportNotesAndHighlights(context: viewContext)
                }
                
                await MainActor.run {
                    exportURL = url
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    exportAlert = DataAlert(title: NSLocalizedString("导出失败", comment: ""), message: message)
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
                    
                    Text("\(NSLocalizedString("版本", comment: "")) 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(NSLocalizedString("把每本书变成一位可对话的导师：获取、阅读、理解与交流，一站式完成。", comment: ""))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 16) {
                    Text(NSLocalizedString("app.copyright", comment: "App copyright"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(NSLocalizedString("用心打造的阅读体验", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("关于", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(NSLocalizedString("完成", comment: "")) {
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
    @State private var alertItem: DataAlert?
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
                    Text(NSLocalizedString("连接到 Notion", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)

                    Text(NSLocalizedString("授权 LanRead 访问你的 Notion 工作区，以便同步你的阅读笔记和高亮。", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                statusContent

                Button(action: startAuthorization) {
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
                    Button(role: .destructive, action: disconnectNotion) {
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
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("Notion 同步", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        dismiss()
                    }
                }

                if notionSessionManager.isConnected {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("完成", comment: "")) {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .alert(item: $alertItem) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(NSLocalizedString("确定", comment: "")))
                )
            }
            .onChange(of: notionSessionManager.connectionState) { state in
                switch state {
                case .error(let message):
                    alertItem = DataAlert(
                        title: NSLocalizedString("授权失败", comment: ""),
                        message: message
                    )
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
            return NSLocalizedString("重新授权", comment: "")
        default:
            return NSLocalizedString("开始授权", comment: "")
        }
    }

    private var isAuthorizationButtonDisabled: Bool {
        notionSessionManager.isConnecting || isLoadingParentPages || isCreatingDatabase
    }

    private func startAuthorization() {
        hasAutoStartedInitialization = false
        parentPageOptions = []
        showingPagePicker = false
        notionSessionManager.startAuthorization()
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
                    alertItem = DataAlert(
                        title: NSLocalizedString("notion.init.error.title", comment: ""),
                        message: error.localizedDescription
                    )
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
                        alertItem = DataAlert(
                            title: NSLocalizedString("notion.init.error.permission_denied", comment: ""),
                            message: NSLocalizedString("notion.init.error.permission_denied.detail", comment: "")
                        )
                    } else {
                        alertItem = DataAlert(
                            title: NSLocalizedString("notion.init.error.title", comment: ""),
                            message: error.localizedDescription
                        )
                    }

                    showingPagePicker = true
                }
            } catch {
                await MainActor.run {
                    isCreatingDatabase = false
                    selectedParentPageID = nil
                    alertItem = DataAlert(
                        title: NSLocalizedString("notion.init.error.title", comment: ""),
                        message: error.localizedDescription
                    )
                    showingPagePicker = true
                }
            }
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
                    Button(NSLocalizedString("取消", comment: "")) {
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
