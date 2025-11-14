//
//  SettingsView.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    @State private var showingAbout = false
    @State private var showingDataManagement = false
    
    var body: some View {
        NavigationView {
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
                    HStack {
                        Label(NSLocalizedString("iCloud 同步", comment: ""), systemImage: "icloud")
                        Spacer()
                        Toggle("", isOn: $appSettings.isAutoSyncEnabled)
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
                        Label(NSLocalizedString("关于 Isla Reader", comment: ""), systemImage: "info.circle")
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
                    Link(destination: URL(string: "mailto:support@islareader.com")!) {
                        Label(NSLocalizedString("联系我们", comment: ""), systemImage: "envelope")
                    }
                    
                    Link(destination: URL(string: "https://islareader.com/privacy")!) {
                        Label(NSLocalizedString("隐私政策", comment: ""), systemImage: "hand.raised")
                    }
                    
                    Link(destination: URL(string: "https://islareader.com/terms")!) {
                        Label(NSLocalizedString("服务条款", comment: ""), systemImage: "doc.text")
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
        }
    }
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
    @State private var showingClearDataAlert = false
    @State private var showingExportSheet = false
    
    var body: some View {
        NavigationView {
            List {
                Section(NSLocalizedString("数据导出", comment: "")) {
                    Button(action: { showingExportSheet = true }) {
                        Label(NSLocalizedString("导出阅读数据", comment: ""), systemImage: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {}) {
                        Label(NSLocalizedString("导出笔记和高亮", comment: ""), systemImage: "note.text")
                            .foregroundColor(.blue)
                    }
                }
                
                Section(NSLocalizedString("存储管理", comment: "")) {
                    HStack {
                        Label(NSLocalizedString("缓存大小", comment: ""), systemImage: "internaldrive")
                        Spacer()
                        Text("128 MB")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {}) {
                        Label(NSLocalizedString("清理缓存", comment: ""), systemImage: "trash")
                            .foregroundColor(.orange)
                    }
                }
                
                Section(NSLocalizedString("危险操作", comment: "")) {
                    Button(action: { showingClearDataAlert = true }) {
                        Label(NSLocalizedString("清除所有数据", comment: ""), systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
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
            .alert(NSLocalizedString("清除所有数据", comment: ""), isPresented: $showingClearDataAlert) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("确认清除", comment: ""), role: .destructive) {
                    // Clear all data
                }
            } message: {
                Text(NSLocalizedString("此操作将删除所有书籍、阅读进度、笔记和设置。此操作不可撤销。", comment: ""))
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportDataView()
            }
        }
    }
}

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "square.and.arrow.up.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text(NSLocalizedString("导出数据", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(NSLocalizedString("选择要导出的数据类型", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 12) {
                    ExportOptionRow(title: NSLocalizedString("阅读进度", comment: ""), description: NSLocalizedString("书籍阅读进度和统计", comment: ""), isSelected: true)
                    ExportOptionRow(title: NSLocalizedString("笔记和高亮", comment: ""), description: NSLocalizedString("所有笔记、高亮和注释", comment: ""), isSelected: true)
                    ExportOptionRow(title: NSLocalizedString("应用设置", comment: ""), description: NSLocalizedString("主题、字体等偏好设置", comment: ""), isSelected: false)
                }
                
                Button(action: {}) {
                    Text(NSLocalizedString("开始导出", comment: ""))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("导出数据", comment: ""))
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
        }
    }
}

struct ExportOptionRow: View {
    let title: String
    let description: String
    @State var isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isSelected)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                // App Icon
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    )
                
                VStack(spacing: 8) {
                    Text("Isla Reader")
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
                    Text("© 2025 Isla Reader")
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

#Preview {
    SettingsView()
}