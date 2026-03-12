//
//  AppLanguageTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct AppLanguageTests {
    @Test
    func systemLanguageFollowsResolvedBundleLocalization() {
        let resolved = AppLanguage.system.resolved(
            preferredLocalizations: ["en"],
            localeIdentifier: "zh_CN"
        )

        #expect(resolved == .en)
        #expect(
            AppLanguage.system.aiOutputLanguageName(
                preferredLocalizations: ["en"],
                localeIdentifier: "zh_CN"
            ) == "English"
        )
    }

    @Test
    func systemLanguageFallsBackToLocaleWhenBundleLocalizationIsUnavailable() {
        let resolved = AppLanguage.system.resolved(
            preferredLocalizations: ["Base"],
            localeIdentifier: "ko_KR"
        )

        #expect(resolved == .ko)
        #expect(
            AppLanguage.system.aiOutputLanguageName(
                preferredLocalizations: ["Base"],
                localeIdentifier: "ko_KR"
            ) == "Korean"
        )
    }

    @Test
    func skimmingCacheKeyIncludesEffectiveLanguage() {
        let bookID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        let englishKey = SkimmingModeService.cacheKey(
            bookID: bookID,
            chapterOrder: 4,
            language: .system,
            preferredLocalizations: ["en"],
            localeIdentifier: "zh_CN"
        )
        let chineseKey = SkimmingModeService.cacheKey(
            bookID: bookID,
            chapterOrder: 4,
            language: .system,
            preferredLocalizations: ["zh-Hans"],
            localeIdentifier: "en_US"
        )

        #expect(englishKey == "00000000-0000-0000-0000-000000000123-4-en")
        #expect(chineseKey == "00000000-0000-0000-0000-000000000123-4-zh-Hans")
        #expect(englishKey != chineseKey)
    }
}
