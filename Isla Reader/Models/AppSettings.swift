//
//  AppSettings.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import Foundation
import SwiftUI

public enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色模式"
        case .dark:
            return "深色模式"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

public enum ReadingFontSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extra_large"
    
    var displayName: String {
        switch self {
        case .small:
            return "小"
        case .medium:
            return "中"
        case .large:
            return "大"
        case .extraLarge:
            return "特大"
        }
    }
    
    var fontSize: CGFloat {
        switch self {
        case .small:
            return 14
        case .medium:
            return 16
        case .large:
            return 18
        case .extraLarge:
            return 20
        }
    }
}

public enum ReadingFont: String, CaseIterable {
    case system = "system"
    case serif = "serif"
    case monospace = "monospace"
    
    var displayName: String {
        switch self {
        case .system:
            return "系统字体"
        case .serif:
            return "衬线字体"
        case .monospace:
            return "等宽字体"
        }
    }
    
    var font: Font {
        switch self {
        case .system:
            return .system(.body)
        case .serif:
            return .custom("Times New Roman", size: 16)
        case .monospace:
            return .monospaced(.body)()
        }
    }
}

public enum AppLanguage: String, CaseIterable {
    case system = "system"
    case en = "en"
    case zhHans = "zh-Hans"
    case ja = "ja"
    case ko = "ko"
    
    var displayName: String {
        switch self {
        case .system:
            return NSLocalizedString("跟随系统", comment: "Follow system language")
        case .en:
            return "English"
        case .zhHans:
            return "中文"
        case .ja:
            return "日本語"
        case .ko:
            return "한국어"
        }
    }
    
    var locale: Locale {
        switch self {
        case .system:
            return Locale.current
        case .en:
            return Locale(identifier: "en")
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .ja:
            return Locale(identifier: "ja")
        case .ko:
            return Locale(identifier: "ko")
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "app_language")
        }
    }
    
    var locale: Locale { language.locale }
    
    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "app_theme")
        }
    }
    
    @Published var readingFontSize: ReadingFontSize {
        didSet {
            UserDefaults.standard.set(readingFontSize.rawValue, forKey: "reading_font_size")
        }
    }
    
    @Published var readingFont: ReadingFont {
        didSet {
            UserDefaults.standard.set(readingFont.rawValue, forKey: "reading_font")
        }
    }
    
    @Published var lineSpacing: Double {
        didSet {
            UserDefaults.standard.set(lineSpacing, forKey: "line_spacing")
        }
    }
    
    @Published var pageMargins: Double {
        didSet {
            UserDefaults.standard.set(pageMargins, forKey: "page_margins")
        }
    }
    
    @Published var isAutoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSyncEnabled, forKey: "auto_sync_enabled")
        }
    }
    
    @Published var isReadingReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isReadingReminderEnabled, forKey: "reading_reminder_enabled")
        }
    }
    
    @Published var dailyReadingGoal: Int {
        didSet {
            UserDefaults.standard.set(dailyReadingGoal, forKey: "daily_reading_goal")
        }
    }
    
    private init() {
        self.language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "app_language") ?? "") ?? .en
        self.theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "app_theme") ?? "") ?? .system
        self.readingFontSize = ReadingFontSize(rawValue: UserDefaults.standard.string(forKey: "reading_font_size") ?? "") ?? .medium
        self.readingFont = ReadingFont(rawValue: UserDefaults.standard.string(forKey: "reading_font") ?? "") ?? .system
        self.lineSpacing = UserDefaults.standard.object(forKey: "line_spacing") as? Double ?? 1.2
        self.pageMargins = UserDefaults.standard.object(forKey: "page_margins") as? Double ?? 20.0
        self.isAutoSyncEnabled = UserDefaults.standard.object(forKey: "auto_sync_enabled") as? Bool ?? true
        self.isReadingReminderEnabled = UserDefaults.standard.object(forKey: "reading_reminder_enabled") as? Bool ?? false
        self.dailyReadingGoal = UserDefaults.standard.object(forKey: "daily_reading_goal") as? Int ?? 30
    }
}