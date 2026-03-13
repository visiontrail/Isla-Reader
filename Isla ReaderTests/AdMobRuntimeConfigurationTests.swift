import Foundation
import Testing
@testable import LanRead

struct AdMobRuntimeConfigurationTests {

    @Test func normalizesQuotedAndEscapedAdUnitID() {
        let rawValue = #"  "ca-app-pub-5587239366359667\/3116000923"  "#

        let normalized = AdMobRuntimeConfiguration.normalizedAdUnitID(from: rawValue)

        #expect(normalized == "ca-app-pub-5587239366359667/3116000923")
    }

    @Test func detectsAdMobAppID() {
        #expect(AdMobRuntimeConfiguration.isAdMobAppID("ca-app-pub-5587239366359667~6499097766"))
        #expect(!AdMobRuntimeConfiguration.isAdMobAppID("ca-app-pub-5587239366359667/3116000923"))
    }

    @Test func validatesWellFormedAdUnitIDs() {
        #expect(AdMobRuntimeConfiguration.isWellFormedAdUnitID("ca-app-pub-5587239366359667/3116000923"))
        #expect(!AdMobRuntimeConfiguration.isWellFormedAdUnitID("ca-app-pub-5587239366359667~6499097766"))
        #expect(!AdMobRuntimeConfiguration.isWellFormedAdUnitID("\"ca-app-pub-5587239366359667/3116000923\""))
    }

    @Test func parsesRewardedFallbackBooleanFlag() {
        #expect(AdMobRuntimeConfiguration.parseBooleanFlag("YES"))
        #expect(AdMobRuntimeConfiguration.parseBooleanFlag(" true "))
        #expect(!AdMobRuntimeConfiguration.parseBooleanFlag("NO"))
        #expect(!AdMobRuntimeConfiguration.parseBooleanFlag("$(ADMOB_ENABLE_REWARDED_INTERSTITIAL_FALLBACK)"))
        #expect(!AdMobRuntimeConfiguration.parseBooleanFlag(nil))
    }

    @Test func detectsRequestTypeMismatchError() {
        let mismatchError = NSError(
            domain: "com.google.admob",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Cannot determine request type. Is your ad unit id correct?"]
        )
        let noFillError = NSError(
            domain: "com.google.admob",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No ad to show."]
        )

        #expect(AdMobRuntimeConfiguration.isRequestTypeMismatch(mismatchError))
        #expect(!AdMobRuntimeConfiguration.isRequestTypeMismatch(noFillError))
    }
}
