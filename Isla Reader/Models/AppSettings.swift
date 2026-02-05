//
//  AppSettings.swift
//  LanRead
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
            return NSLocalizedString("跟随系统", comment: "Follow system theme")
        case .light:
            return NSLocalizedString("始终使用浅色主题", comment: "Always use light theme")
        case .dark:
            return NSLocalizedString("始终使用深色主题", comment: "Always use dark theme")
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
            return NSLocalizedString("小", comment: "Small font size")
        case .medium:
            return NSLocalizedString("中", comment: "Medium font size")
        case .large:
            return NSLocalizedString("大", comment: "Large font size")
        case .extraLarge:
            return NSLocalizedString("特大", comment: "Extra large font size")
        }
    }
    
    var fontSize: CGFloat {
        switch self {
        case .small:
            return 16
        case .medium:
            return 19
        case .large:
            return 22
        case .extraLarge:
            return 26
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
            return NSLocalizedString("系统字体", comment: "System font")
        case .serif:
            return NSLocalizedString("衬线字体", comment: "Serif font")
        case .monospace:
            return NSLocalizedString("等宽字体", comment: "Monospace font")
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
    static let persistedKeys = [
        "app_language",
        "translation_language",
        "app_theme",
        "reading_font_size",
        "reading_font",
        "line_spacing",
        "page_margins",
        "reading_reminder_enabled",
        "daily_reading_goal"
    ]
    
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "app_language")
        }
    }
    
    @Published var translationLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(translationLanguage.rawValue, forKey: "translation_language")
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
        let storedLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "app_language") ?? "") ?? .en
        let storedTranslationLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "translation_language") ?? "")
        
        self.language = storedLanguage
        self.translationLanguage = storedTranslationLanguage ?? storedLanguage
        self.theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "app_theme") ?? "") ?? .system
        self.readingFontSize = ReadingFontSize(rawValue: UserDefaults.standard.string(forKey: "reading_font_size") ?? "") ?? .medium
        self.readingFont = ReadingFont(rawValue: UserDefaults.standard.string(forKey: "reading_font") ?? "") ?? .system
        self.lineSpacing = UserDefaults.standard.object(forKey: "line_spacing") as? Double ?? 1.2
        self.pageMargins = UserDefaults.standard.object(forKey: "page_margins") as? Double ?? 20.0
        self.isReadingReminderEnabled = UserDefaults.standard.object(forKey: "reading_reminder_enabled") as? Bool ?? false
        self.dailyReadingGoal = UserDefaults.standard.object(forKey: "daily_reading_goal") as? Int ?? 30
    }
    
    @MainActor
    func resetToDefaults() {
        let defaults = UserDefaults.standard
        for key in AppSettings.persistedKeys {
            defaults.removeObject(forKey: key)
        }
        
        language = .en
        translationLanguage = language
        theme = .system
        readingFontSize = .medium
        readingFont = .system
        lineSpacing = 1.2
        pageMargins = 20.0
        isReadingReminderEnabled = false
        dailyReadingGoal = 30
    }
}
