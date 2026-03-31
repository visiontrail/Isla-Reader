//
//  AppSettings.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import Foundation
import SwiftUI
import UIKit

enum AdDisplayPolicy {
    #if LANREAD_ADS_DISABLED
    static let isAdBuildEnabled = false
    #else
    static let isAdBuildEnabled = true
    #endif

    static func isAdsEnabled(adRemovalUnlocked: Bool) -> Bool {
        isAdBuildEnabled && !adRemovalUnlocked
    }
}

public enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .system:
            return NSLocalizedString("settings.theme.mode.system", comment: "Follow system theme")
        case .light:
            return NSLocalizedString("settings.theme.mode.always_light", comment: "Always use light theme")
        case .dark:
            return NSLocalizedString("settings.theme.mode.always_dark", comment: "Always use dark theme")
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
            return NSLocalizedString("settings.font.size.small", comment: "Small font size")
        case .medium:
            return NSLocalizedString("settings.font.size.medium", comment: "Medium font size")
        case .large:
            return NSLocalizedString("settings.font.size.large", comment: "Large font size")
        case .extraLarge:
            return NSLocalizedString("settings.font.size.extra_large", comment: "Extra large font size")
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
            return NSLocalizedString("settings.font.family.system", comment: "System font")
        case .serif:
            return NSLocalizedString("settings.font.family.serif", comment: "Serif font")
        case .monospace:
            return NSLocalizedString("settings.font.family.monospace", comment: "Monospace font")
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
            return NSLocalizedString("settings.language.follow_system", comment: "Follow system language")
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

    func resolved(
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        localeIdentifier: String = Locale.current.identifier
    ) -> AppLanguage {
        guard self == .system else { return self }

        if let preferredLocalization = preferredLocalizations.first,
           let matchedLanguage = AppLanguage.from(identifier: preferredLocalization) {
            return matchedLanguage
        }

        if let localeLanguage = AppLanguage.from(identifier: localeIdentifier) {
            return localeLanguage
        }

        return .en
    }

    func aiOutputLanguageName(
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        localeIdentifier: String = Locale.current.identifier
    ) -> String {
        switch resolved(
            preferredLocalizations: preferredLocalizations,
            localeIdentifier: localeIdentifier
        ) {
        case .system, .en:
            return "English"
        case .zhHans:
            return "Simplified Chinese"
        case .ja:
            return "Japanese"
        case .ko:
            return "Korean"
        }
    }

    func cacheIdentifier(
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        localeIdentifier: String = Locale.current.identifier
    ) -> String {
        resolved(
            preferredLocalizations: preferredLocalizations,
            localeIdentifier: localeIdentifier
        ).rawValue
    }

    private static func from(identifier: String) -> AppLanguage? {
        let normalized = identifier.lowercased()

        if normalized.hasPrefix("en") {
            return .en
        }

        if normalized.hasPrefix("zh") {
            return .zhHans
        }

        if normalized.hasPrefix("ja") {
            return .ja
        }

        if normalized.hasPrefix("ko") {
            return .ko
        }

        return nil
    }
}

public enum HighlightSortMode: String, CaseIterable {
    case chapter = "chapter"
    case modifiedTime = "modified_time"

    var displayName: String {
        switch self {
        case .chapter:
            return NSLocalizedString("settings.highlight_sort.by_chapter", comment: "Sort highlights by chapter")
        case .modifiedTime:
            return NSLocalizedString("settings.highlight_sort.by_modified_time", comment: "Sort highlights by modified time")
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let readingReminderEnabledKey = "readingReminderEnabled"
    private static let readingGoalMinutesKey = "readingGoalMinutes"
    private static let readingReminderTimeMinutesKey = "readingReminderTimeMinutes"
    private static let adRemovalUnlockedKey = "adRemovalUnlocked"
    private static let aiAdvanceAdNoticeEnabledKey = "aiAdvanceAdNoticeEnabled"
    private static let highlightSortModeKey = "highlightSortMode"
    private static let profileDisplayNameKey = "profileDisplayName"
    private static let profileAvatarDataKey = "profileAvatarData"
    private static let legacyReadingReminderEnabledKey = "reading_reminder_enabled"
    private static let legacyReadingGoalMinutesKey = "daily_reading_goal"
    private static let minutesPerDay = 24 * 60
    static let lineSpacingRange: ClosedRange<Double> = 0.6...2.4
    static let lineSpacingStep: Double = 0.1
    static let defaultLineSpacing: Double = 1.0
    static let pageMarginsRange: ClosedRange<Double> = 0...50
    static let pageMarginsStep: Double = 5
    static let defaultPageMargins: Double = 35
    static let defaultReadingReminderMinutesSinceMidnight =
        ReadingReminderConstants.defaultReminderHour * 60 + ReadingReminderConstants.defaultReminderMinute

    static let persistedKeys = [
        "app_language",
        "translation_language",
        "app_theme",
        "reading_font_size",
        "reading_font",
        "line_spacing",
        "page_margins",
        adRemovalUnlockedKey,
        highlightSortModeKey,
        profileDisplayNameKey,
        profileAvatarDataKey,
        aiAdvanceAdNoticeEnabledKey,
        readingReminderEnabledKey,
        readingGoalMinutesKey,
        readingReminderTimeMinutesKey,
        legacyReadingReminderEnabledKey,
        legacyReadingGoalMinutesKey
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

    @Published var isAdRemovalUnlocked: Bool {
        didSet {
            UserDefaults.standard.set(isAdRemovalUnlocked, forKey: AppSettings.adRemovalUnlockedKey)
        }
    }

    @Published var isAIAdvanceAdNoticeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAIAdvanceAdNoticeEnabled, forKey: AppSettings.aiAdvanceAdNoticeEnabledKey)
        }
    }

    var areAdsEnabled: Bool {
        AdDisplayPolicy.isAdsEnabled(adRemovalUnlocked: isAdRemovalUnlocked)
    }

    var shouldShowAIAdvanceAdNotice: Bool {
        areAdsEnabled && isAIAdvanceAdNoticeEnabled
    }

    @Published var highlightSortMode: HighlightSortMode {
        didSet {
            UserDefaults.standard.set(highlightSortMode.rawValue, forKey: AppSettings.highlightSortModeKey)
        }
    }

    @Published var profileDisplayName: String {
        didSet {
            UserDefaults.standard.set(profileDisplayName, forKey: AppSettings.profileDisplayNameKey)
        }
    }

    @Published var profileAvatarData: Data? {
        didSet {
            let defaults = UserDefaults.standard
            if let profileAvatarData {
                defaults.set(profileAvatarData, forKey: AppSettings.profileAvatarDataKey)
            } else {
                defaults.removeObject(forKey: AppSettings.profileAvatarDataKey)
            }
        }
    }
    
    @Published var isReadingReminderEnabled: Bool {
        didSet {
            let defaults = UserDefaults.standard
            defaults.set(isReadingReminderEnabled, forKey: AppSettings.readingReminderEnabledKey)
            defaults.set(isReadingReminderEnabled, forKey: AppSettings.legacyReadingReminderEnabledKey)
        }
    }
    
    @Published var dailyReadingGoal: Int {
        didSet {
            let defaults = UserDefaults.standard
            defaults.set(dailyReadingGoal, forKey: AppSettings.readingGoalMinutesKey)
            defaults.set(dailyReadingGoal, forKey: AppSettings.legacyReadingGoalMinutesKey)
        }
    }

    @Published var readingReminderMinutesSinceMidnight: Int {
        didSet {
            let normalizedValue = AppSettings.normalizedReminderMinutes(readingReminderMinutesSinceMidnight)
            if normalizedValue != readingReminderMinutesSinceMidnight {
                readingReminderMinutesSinceMidnight = normalizedValue
                return
            }
            UserDefaults.standard.set(
                readingReminderMinutesSinceMidnight,
                forKey: AppSettings.readingReminderTimeMinutesKey
            )
        }
    }

    var readingReminderHour: Int {
        readingReminderMinutesSinceMidnight / 60
    }

    var readingReminderMinute: Int {
        readingReminderMinutesSinceMidnight % 60
    }

    var readingReminderTime: Date {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = readingReminderHour
        components.minute = readingReminderMinute
        components.second = 0
        return Calendar.current.date(from: components) ?? now
    }

    func setReadingReminderTime(_ date: Date) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        readingReminderMinutesSinceMidnight = hour * 60 + minute
    }

    static func currentHighlightSortMode(defaults: UserDefaults = .standard) -> HighlightSortMode {
        HighlightSortMode(rawValue: defaults.string(forKey: AppSettings.highlightSortModeKey) ?? "") ?? .modifiedTime
    }

    @MainActor
    func applyAdRemovalEntitlement(unlocked: Bool) {
        guard isAdRemovalUnlocked != unlocked else { return }
        isAdRemovalUnlocked = unlocked
    }

    func resolvedProfileDisplayName(fallback: String) -> String {
        let trimmed = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func profileAvatarImage() -> UIImage? {
        guard let profileAvatarData, !profileAvatarData.isEmpty else {
            return nil
        }
        return UIImage(data: profileAvatarData)
    }

    @MainActor
    func updateProfileAvatar(withRawData rawData: Data?) {
        guard let rawData, !rawData.isEmpty else {
            DebugLogger.warning("AppSettings: 头像选择返回空数据，保持原头像")
            return
        }
        guard let image = UIImage(data: rawData) else {
            DebugLogger.warning("AppSettings: 无法解析头像图片数据，已忽略更新")
            return
        }
        setProfileAvatar(from: image)
    }

    @MainActor
    func setProfileAvatar(from image: UIImage?) {
        guard let image else {
            profileAvatarData = nil
            return
        }
        let resized = image.resizedForProfileAvatar(maxPixel: 512)
        if let jpegData = resized.jpegData(compressionQuality: 0.85) {
            profileAvatarData = jpegData
        } else {
            profileAvatarData = resized.pngData()
        }
    }
    
    private init() {
        let storedLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "app_language") ?? "") ?? .system
        let storedTranslationLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "translation_language") ?? "")
        
        self.language = storedLanguage
        self.translationLanguage = storedTranslationLanguage ?? storedLanguage
        self.theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "app_theme") ?? "") ?? .system
        self.readingFontSize = ReadingFontSize(rawValue: UserDefaults.standard.string(forKey: "reading_font_size") ?? "") ?? .medium
        self.readingFont = ReadingFont(rawValue: UserDefaults.standard.string(forKey: "reading_font") ?? "") ?? .system
        let storedLineSpacing = UserDefaults.standard.object(forKey: "line_spacing") as? Double ?? AppSettings.defaultLineSpacing
        self.lineSpacing = min(max(storedLineSpacing, AppSettings.lineSpacingRange.lowerBound), AppSettings.lineSpacingRange.upperBound)

        let storedPageMargins = UserDefaults.standard.object(forKey: "page_margins") as? Double ?? AppSettings.defaultPageMargins
        self.pageMargins = min(max(storedPageMargins, AppSettings.pageMarginsRange.lowerBound), AppSettings.pageMarginsRange.upperBound)
        let defaults = UserDefaults.standard
        self.isAdRemovalUnlocked = defaults.object(forKey: AppSettings.adRemovalUnlockedKey) as? Bool ?? false
        self.highlightSortMode = AppSettings.currentHighlightSortMode(defaults: defaults)
        self.profileDisplayName = defaults.string(forKey: AppSettings.profileDisplayNameKey) ?? ""
        self.profileAvatarData = defaults.data(forKey: AppSettings.profileAvatarDataKey)
        self.isAIAdvanceAdNoticeEnabled = defaults.object(forKey: AppSettings.aiAdvanceAdNoticeEnabledKey) as? Bool ?? true
        self.isReadingReminderEnabled = defaults.object(forKey: AppSettings.readingReminderEnabledKey) as? Bool
            ?? defaults.object(forKey: AppSettings.legacyReadingReminderEnabledKey) as? Bool
            ?? false
        self.dailyReadingGoal = defaults.object(forKey: AppSettings.readingGoalMinutesKey) as? Int
            ?? defaults.object(forKey: AppSettings.legacyReadingGoalMinutesKey) as? Int
            ?? 20
        self.readingReminderMinutesSinceMidnight = AppSettings.normalizedReminderMinutes(
            defaults.object(forKey: AppSettings.readingReminderTimeMinutesKey) as? Int
                ?? AppSettings.defaultReadingReminderMinutesSinceMidnight
        )
    }
    
    @MainActor
    func resetToDefaults() {
        let defaults = UserDefaults.standard
        for key in AppSettings.persistedKeys {
            defaults.removeObject(forKey: key)
        }
        
        language = .system
        translationLanguage = language
        theme = .system
        readingFontSize = .medium
        readingFont = .system
        lineSpacing = AppSettings.defaultLineSpacing
        pageMargins = AppSettings.defaultPageMargins
        isAdRemovalUnlocked = false
        highlightSortMode = .modifiedTime
        profileDisplayName = ""
        profileAvatarData = nil
        isAIAdvanceAdNoticeEnabled = true
        isReadingReminderEnabled = false
        dailyReadingGoal = 20
        readingReminderMinutesSinceMidnight = AppSettings.defaultReadingReminderMinutesSinceMidnight
    }

    private static func normalizedReminderMinutes(_ minutes: Int) -> Int {
        let normalized = minutes % minutesPerDay
        return normalized >= 0 ? normalized : normalized + minutesPerDay
    }
}

private extension UIImage {
    func resizedForProfileAvatar(maxPixel: CGFloat) -> UIImage {
        let maxDimension = max(size.width, size.height)
        guard maxDimension > maxPixel, maxPixel > 0 else {
            return self
        }

        let scale = maxPixel / maxDimension
        let targetSize = CGSize(
            width: floor(size.width * scale),
            height: floor(size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
