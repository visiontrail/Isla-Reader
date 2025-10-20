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
                // Reading Settings
                Section("阅读设置") {
                    NavigationLink(destination: ReadingSettingsView()) {
                        Label("阅读偏好", systemImage: "textformat")
                    }
                    
                    NavigationLink(destination: ThemeSettingsView()) {
                        Label("主题外观", systemImage: "paintbrush")
                    }
                }
                
                // Data & Sync
                Section("数据与同步") {
                    HStack {
                        Label("iCloud 同步", systemImage: "icloud")
                        Spacer()
                        Toggle("", isOn: $appSettings.isAutoSyncEnabled)
                    }
                    
                    Button(action: { showingDataManagement = true }) {
                        Label("数据管理", systemImage: "externaldrive")
                            .foregroundColor(.primary)
                    }
                }
                
                // Notifications
                Section("通知提醒") {
                    HStack {
                        Label("阅读提醒", systemImage: "bell")
                        Spacer()
                        Toggle("", isOn: $appSettings.isReadingReminderEnabled)
                    }
                    
                    if appSettings.isReadingReminderEnabled {
                        HStack {
                            Text("每日目标")
                            Spacer()
                            Stepper("\(appSettings.dailyReadingGoal) 分钟", 
                                   value: $appSettings.dailyReadingGoal, 
                                   in: 10...180, 
                                   step: 10)
                        }
                    }
                }
                
                // About
                Section("关于") {
                    Button(action: { showingAbout = true }) {
                        Label("关于 Isla Reader", systemImage: "info.circle")
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Label("版本", systemImage: "number")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Support
                Section("支持") {
                    Link(destination: URL(string: "mailto:support@islareader.com")!) {
                        Label("联系我们", systemImage: "envelope")
                    }
                    
                    Link(destination: URL(string: "https://islareader.com/privacy")!) {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                    
                    Link(destination: URL(string: "https://islareader.com/terms")!) {
                        Label("服务条款", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
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
            Section("字体设置") {
                HStack {
                    Text("字体大小")
                    Spacer()
                    Picker("字体大小", selection: $appSettings.readingFontSize) {
                        ForEach(ReadingFontSize.allCases, id: \.rawValue) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                HStack {
                    Text("字体类型")
                    Spacer()
                    Picker("字体类型", selection: $appSettings.readingFont) {
                        ForEach(ReadingFont.allCases, id: \.rawValue) { font in
                            Text(font.displayName).tag(font)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            
            Section("排版设置") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("行间距")
                        Spacer()
                        Text(String(format: "%.1f", appSettings.lineSpacing))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $appSettings.lineSpacing, in: 1.0...2.0, step: 0.1)
                        .accentColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("页面边距")
                        Spacer()
                        Text("\(Int(appSettings.pageMargins))pt")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $appSettings.pageMargins, in: 10...40, step: 5)
                        .accentColor(.blue)
                }
            }
            
            Section("预览") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("示例文本")
                        .font(.headline)
                    
                    Text("这是一段示例文本，用于预览当前的字体和排版设置效果。您可以调整上面的设置来获得最佳的阅读体验。")
                        .font(.system(size: appSettings.readingFontSize.fontSize))
                        .lineSpacing(appSettings.lineSpacing * 4)
                        .padding(.horizontal, appSettings.pageMargins / 2)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
        .navigationTitle("阅读偏好")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ThemeSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared
    
    var body: some View {
        List {
            Section("主题选择") {
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
            
            Section("主题预览") {
                VStack(spacing: 16) {
                    HStack {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 20, height: 20)
                        
                        Text("主要文本颜色")
                            .font(.body)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 20, height: 20)
                        
                        Text("次要文本颜色")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 20, height: 20)
                        
                        Text("强调色")
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
        .navigationTitle("主题外观")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func themeDescription(_ theme: AppTheme) -> String {
        switch theme {
        case .system:
            return "根据系统设置自动切换"
        case .light:
            return "始终使用浅色主题"
        case .dark:
            return "始终使用深色主题"
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
                Section("数据导出") {
                    Button(action: { showingExportSheet = true }) {
                        Label("导出阅读数据", systemImage: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {}) {
                        Label("导出笔记和高亮", systemImage: "note.text")
                            .foregroundColor(.blue)
                    }
                }
                
                Section("存储管理") {
                    HStack {
                        Label("缓存大小", systemImage: "internaldrive")
                        Spacer()
                        Text("128 MB")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {}) {
                        Label("清理缓存", systemImage: "trash")
                            .foregroundColor(.orange)
                    }
                }
                
                Section("危险操作") {
                    Button(action: { showingClearDataAlert = true }) {
                        Label("清除所有数据", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("数据管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("清除所有数据", isPresented: $showingClearDataAlert) {
                Button("取消", role: .cancel) { }
                Button("确认清除", role: .destructive) {
                    // Clear all data
                }
            } message: {
                Text("此操作将删除所有书籍、阅读进度、笔记和设置。此操作不可撤销。")
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
                    Text("导出数据")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("选择要导出的数据类型")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 12) {
                    ExportOptionRow(title: "阅读进度", description: "书籍阅读进度和统计", isSelected: true)
                    ExportOptionRow(title: "笔记和高亮", description: "所有笔记、高亮和注释", isSelected: true)
                    ExportOptionRow(title: "应用设置", description: "主题、字体等偏好设置", isSelected: false)
                }
                
                Button(action: {}) {
                    Text("开始导出")
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
            .navigationTitle("导出数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
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
                    
                    Text("版本 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("把每本书变成一位可对话的导师：获取、阅读、理解与交流，一站式完成。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 16) {
                    Text("© 2025 Isla Reader")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("用心打造的阅读体验")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}