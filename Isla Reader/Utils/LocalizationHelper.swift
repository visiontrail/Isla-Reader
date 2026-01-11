//
//  LocalizationHelper.swift
//  LanRead
//
//  Created by AI Assistant on 2025/1/20.
//

import Foundation

/// Helper class for dynamic localization based on app settings
class LocalizationHelper {
    
    /// Get localized string based on current app language setting
    /// - Parameters:
    ///   - key: The localization key
    ///   - comment: Optional comment for the localization
    /// - Returns: Localized string in the user's selected language
    static func localizedString(_ key: String, comment: String = "") -> String {
        let appLanguage = AppSettings.shared.language
        
        // If system language is selected, use default NSLocalizedString
        if appLanguage == .system {
            return NSLocalizedString(key, comment: comment)
        }
        
        // Get the bundle for the specific language
        guard let bundlePath = Bundle.main.path(forResource: languageCode(for: appLanguage), ofType: "lproj"),
              let bundle = Bundle(path: bundlePath) else {
            // Fallback to default localization
            return NSLocalizedString(key, comment: comment)
        }
        
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    
    /// Convert AppLanguage to language code used in .lproj directories
    private static func languageCode(for language: AppLanguage) -> String {
        switch language {
        case .system:
            return Locale.current.language.languageCode?.identifier ?? "en"
        case .en:
            return "en"
        case .zhHans:
            return "zh-Hans"
        case .ja:
            return "ja"
        case .ko:
            return "ko"
        }
    }
}

