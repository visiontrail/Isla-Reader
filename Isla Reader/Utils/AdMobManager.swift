//
//  AdMobManager.swift
//  LanRead
//
//  Created by AI Assistant on 2025/3/4.
//

import Foundation
import GoogleMobileAds
import SwiftUI
import UIKit

private enum AdMobDiagnostics {
    static func log(responseInfo: GADResponseInfo?, context: String) {
        guard let responseInfo else {
            DebugLogger.info("AdMob: \(context) responseInfo=nil")
            return
        }

        var summary: [String] = []
        summary.append("responseId=\(responseInfo.responseIdentifier ?? "nil")")
        if let loaded = responseInfo.loadedAdNetworkResponseInfo {
            summary.append("loadedAdapter=\(loaded.adNetworkClassName)")
            let latencyMs = Int(loaded.latency * 1000)
            summary.append("latencyMs=\(latencyMs)")
            if let adSource = loaded.adSourceName {
                summary.append("adSourceName=\(adSource)")
            }
            if let adSourceId = loaded.adSourceID {
                summary.append("adSourceID=\(adSourceId)")
            }
        }
        DebugLogger.info("AdMob: \(context) summary \(summary.joined(separator: ", "))")

        DebugLogger.info("AdMob: \(context) raw responseInfo=\(prettify(responseInfo.dictionaryRepresentation))")

        let extras = responseInfo.extrasDictionary
        if !extras.isEmpty {
            DebugLogger.info("AdMob: \(context) extras=\(prettify(extras))")
        }

        let networkInfos = responseInfo.adNetworkInfoArray.map { info in
            info.dictionaryRepresentation
        }
        if !networkInfos.isEmpty {
            DebugLogger.info("AdMob: \(context) adNetworkInfoArray=\(prettify(networkInfos))")
        }
    }

    static func log(error: NSError, context: String) {
        var parts: [String] = []
        parts.append("domain=\(error.domain)")
        parts.append("code=\(error.code)")
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            parts.append("message=\(message)")
        }
        if let reason = error.localizedFailureReason, !reason.isEmpty {
            parts.append("reason=\(reason)")
        }
        if let suggestion = error.localizedRecoverySuggestion, !suggestion.isEmpty {
            parts.append("suggestion=\(suggestion)")
        }

        DebugLogger.error("AdMob: \(context) \(parts.joined(separator: ", "))")

        if !error.userInfo.isEmpty {
            DebugLogger.info("AdMob: \(context) error.userInfo=\(prettify(error.userInfo))")
        }
    }

    private static func prettify(_ object: Any) -> String {
        let normalized = normalize(object)
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return json
    }

    private static func normalize(_ object: Any) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                result[String(describing: key)] = normalize(value)
            }
            return result
        }

        if let array = object as? [Any] {
            return array.map { normalize($0) }
        }

        switch object {
        case let number as NSNumber:
            return number
        case let string as String:
            return string
        default:
            return String(describing: object)
        }
    }
}

private enum AdLoadPlacement: String {
    case banner = "admob_banner_load"
    case rewardedInterstitial = "admob_rewarded_interstitial_load"
    case interstitial = "admob_interstitial_load"
}

private enum AdLoadMetricsRecorder {
    static func record(
        _ placement: AdLoadPlacement,
        statusCode: Int,
        error: Error? = nil,
        responseId: String? = nil
    ) {
        let reason: String?
        if let error {
            reason = summarize(error)
        } else {
            reason = nil
        }

        UsageMetricsReporter.shared.record(
            interface: placement.rawValue,
            statusCode: statusCode,
            latencyMs: 0,
            requestBytes: 0,
            tokens: nil,
            retryCount: 0,
            source: .ads,
            requestId: responseId,
            errorReason: reason
        )
    }

    private static func summarize(_ error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = []
        if !nsError.domain.isEmpty {
            parts.append(nsError.domain)
        }
        parts.append("code=\(nsError.code)")
        let message = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            parts.append(message)
        }
        return parts.joined(separator: " | ")
    }
}

private enum AdMobInfoPlistKey: String {
    case banner = "AdMobBannerAdUnitID"
    case interstitial = "AdMobInterstitialAdUnitID"
    case rewardedInterstitial = "AdMobRewardedInterstitialAdUnitID"
    case rewardedInterstitialFallbackEnabled = "AdMobEnableRewardedInterstitialFallback"
}

enum AdMobRuntimeConfiguration {
    static func normalizedAdUnitID(from rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        while let quote = value.first, value.last == quote, (quote == "\"" || quote == "'") {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value.replacingOccurrences(of: "\\/", with: "/")
    }

    static func isAdMobAppID(_ value: String) -> Bool {
        value.range(of: #"^ca-app-pub-\d{16}~\d+$"#, options: .regularExpression) != nil
    }

    static func isWellFormedAdUnitID(_ value: String) -> Bool {
        value.range(of: #"^ca-app-pub-\d{16}/\d{10}$"#, options: .regularExpression) != nil
    }

    static func parseBooleanFlag(_ rawValue: String?) -> Bool {
        guard let rawValue else { return false }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value.hasPrefix("$(") {
            return false
        }

        switch value {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            DebugLogger.warning("AdMob: 无法解析布尔开关值 \(rawValue)，将按 false 处理")
            return false
        }
    }

    static func isRequestTypeMismatch(_ error: NSError) -> Bool {
        error.domain == "com.google.admob"
            && error.code == 0
            && error.localizedDescription.localizedCaseInsensitiveContains("Cannot determine request type")
    }

    static func redactedAdUnitID(_ value: String) -> String {
        guard let slashIndex = value.lastIndex(of: "/") else {
            return value
        }

        let publisherPrefix = value[..<value.index(after: slashIndex)]
        let suffix = value.suffix(4)
        return "\(publisherPrefix)****\(suffix)"
    }
}

private enum AdMobFeatureFlags {
    static let isRewardedInterstitialFallbackEnabled: Bool = {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: AdMobInfoPlistKey.rewardedInterstitialFallbackEnabled.rawValue) as? String
        let isEnabled = AdMobRuntimeConfiguration.parseBooleanFlag(rawValue)
        if isEnabled {
            DebugLogger.info("AdMob: Rewarded interstitial fallback enabled")
        }
        return isEnabled
    }()
}

enum AdMobAdUnitIDs {
    static var fixedBanner: String? {
        resolvedID(for: .banner)
    }

    static var rewardedInterstitial: String? {
        resolvedID(for: .rewardedInterstitial)
    }

    static var interstitial: String? {
        resolvedID(for: .interstitial)
    }

    private static func resolvedID(for infoPlistKey: AdMobInfoPlistKey) -> String? {
        guard AppSettings.shared.areAdsEnabled else {
            DebugLogger.info("AdMob: 广告已关闭，跳过读取广告位 \(infoPlistKey.rawValue)")
            return nil
        }

        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey.rawValue) as? String else {
            DebugLogger.warning("AdMob: Info.plist 缺少键 \(infoPlistKey.rawValue)，已跳过广告请求")
            return nil
        }

        let value = AdMobRuntimeConfiguration.normalizedAdUnitID(from: raw)

        if value.isEmpty {
            DebugLogger.warning("AdMob: \(infoPlistKey.rawValue) 为空，已跳过广告请求")
            return nil
        }

        if value.hasPrefix("$(") {
            DebugLogger.warning("AdMob: \(infoPlistKey.rawValue) 未通过 xcconfig 替换，已跳过广告请求")
            return nil
        }

        if AdMobRuntimeConfiguration.isAdMobAppID(value) {
            DebugLogger.warning("AdMob: \(infoPlistKey.rawValue) 看起来是 App ID 而不是广告位 ID，已跳过广告请求")
            return nil
        }

        if !AdMobRuntimeConfiguration.isWellFormedAdUnitID(value) {
            DebugLogger.warning("AdMob: \(infoPlistKey.rawValue) 格式非法 (\(value))，已跳过广告请求")
            return nil
        }

        // Google 官方测试广告位 ID，发布不可使用
        if value.contains("ca-app-pub-3940256099942544") {
            DebugLogger.warning("AdMob: \(infoPlistKey.rawValue) 为测试广告位 ID，发布版禁用广告请求")
            return nil
        }

        return value
    }
}

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GADBannerView {
        let bannerView = GADBannerView(adSize: GADAdSizeBanner)
        bannerView.adUnitID = adUnitID
        bannerView.delegate = context.coordinator
        bannerView.rootViewController = UIViewController.topMostViewController()
        DebugLogger.info("AdMob: Start loading banner adUnitID=\(AdMobRuntimeConfiguration.redactedAdUnitID(adUnitID))")
        bannerView.load(GADRequest())
        return bannerView
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        uiView.rootViewController = UIViewController.topMostViewController()
    }

    final class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            DebugLogger.success("AdMob: Banner ad loaded")
            let responseInfo = bannerView.responseInfo
            AdMobDiagnostics.log(responseInfo: responseInfo, context: "Banner load success")
            AdLoadMetricsRecorder.record(.banner, statusCode: 200, responseId: responseInfo?.responseIdentifier)
        }

        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: any Error) {
            let nsError = error as NSError
            DebugLogger.error("AdMob: Banner failed to load - adUnitID=\(bannerView.adUnitID ?? "nil") adSize=\(bannerView.adSize.size), message=\(nsError.localizedDescription)")

            AdMobDiagnostics.log(error: nsError, context: "Banner load failure")
            if AdMobRuntimeConfiguration.isRequestTypeMismatch(nsError) {
                DebugLogger.warning("AdMob: Banner 广告位与 banner 请求类型不匹配，请检查 Xcode Cloud 中的 AdMobBannerAdUnitID")
            }

            let responseInfo = (nsError.userInfo[GADErrorUserInfoKeyResponseInfo] as? GADResponseInfo) ?? bannerView.responseInfo
            AdMobDiagnostics.log(responseInfo: responseInfo, context: "Banner load failure")

            AdLoadMetricsRecorder.record(.banner, statusCode: nsError.code, error: nsError, responseId: responseInfo?.responseIdentifier)
        }
    }
}

enum RewardedInterstitialAvailability {
    case ready
    case loading
    case notReady
}

enum RewardedInterstitialPresentationResult {
    case presented
    case skippedNotReady
    case skippedNoTopViewController
}

final class RewardedInterstitialAdManager: NSObject {
    static let shared = RewardedInterstitialAdManager()

    private var rewardedAd: GADRewardedInterstitialAd?
    private var interstitialAd: GADInterstitialAd?
    private var isRewardedLoading = false
    private var isInterstitialLoading = false
    private var isRewardedFallbackSuppressedForCurrentLaunch = false

    private override init() {
        super.init()
    }

    func loadAd() {
        guard AppSettings.shared.areAdsEnabled else {
            resetLoadedAds()
            return
        }

        if rewardedAd != nil || interstitialAd != nil {
            return
        }

        loadPrimaryInterstitialIfNeeded(trigger: "initial")
    }

    func availabilityStatus() -> RewardedInterstitialAvailability {
        guard AppSettings.shared.areAdsEnabled else {
            return .notReady
        }

        if rewardedAd != nil || interstitialAd != nil {
            return .ready
        }
        if isRewardedLoading || isInterstitialLoading {
            return .loading
        }
        return .notReady
    }

    @MainActor
    @discardableResult
    func presentFromTopControllerIfAvailable() -> RewardedInterstitialPresentationResult {
        guard AppSettings.shared.areAdsEnabled else {
            resetLoadedAds()
            return .skippedNotReady
        }

        switch availabilityStatus() {
        case .loading:
            DebugLogger.info("AdMob: Fullscreen ad is loading, skip current presentation")
            return .skippedNotReady
        case .notReady:
            DebugLogger.warning("AdMob: Fullscreen ad not ready, skip current presentation and reload")
            loadAd()
            return .skippedNotReady
        case .ready:
            break
        }

        guard let controller = UIViewController.topMostViewController() else {
            DebugLogger.warning("AdMob: Unable to find top view controller to present fullscreen ad")
            return .skippedNoTopViewController
        }
        present(from: controller)
        return .presented
    }

    @MainActor
    private func present(from controller: UIViewController) {
        if let interstitialAd {
            do {
                try interstitialAd.canPresent(fromRootViewController: controller)
            } catch {
                let nsError = error as NSError
                DebugLogger.error("AdMob: Primary interstitial failed canPresent check - \(nsError.localizedDescription)")
                self.interstitialAd = nil
                loadAd()
                return
            }

            DebugLogger.info("AdMob: Presenting primary interstitial ad")
            interstitialAd.present(fromRootViewController: controller)
            return
        }

        if let rewardedAd {
            do {
                try rewardedAd.canPresent(fromRootViewController: controller)
            } catch {
                let nsError = error as NSError
                DebugLogger.error("AdMob: Rewarded interstitial failed canPresent check - \(nsError.localizedDescription)")
                self.rewardedAd = nil
                loadAd()
                return
            }

            rewardedAd.present(fromRootViewController: controller) { [weak self] in
                DebugLogger.info("AdMob: User earned reward type=\(rewardedAd.adReward.type), amount=\(rewardedAd.adReward.amount)")
                self?.rewardedAd = nil
            }
            return
        }

        DebugLogger.warning("AdMob: Fullscreen ad unexpectedly unavailable before presenting, triggering reload")
        loadAd()
    }

    private func loadPrimaryInterstitialIfNeeded(trigger: String) {
        guard AppSettings.shared.areAdsEnabled else { return }
        guard interstitialAd == nil else { return }
        guard !isInterstitialLoading else { return }
        guard let interstitialAdUnitID = AdMobAdUnitIDs.interstitial else {
            if canUseRewardedFallback {
                DebugLogger.warning("AdMob: 未配置插屏广告位，尝试奖励插屏兜底 (trigger=\(trigger))")
                loadFallbackRewardedIfNeeded(trigger: "interstitial_unconfigured")
            } else {
                DebugLogger.warning("AdMob: 未配置插屏广告位，且奖励插屏兜底已关闭，跳过全屏广告请求 (trigger=\(trigger))")
            }
            return
        }

        isInterstitialLoading = true
        DebugLogger.info(
            "AdMob: Start loading primary interstitial (trigger=\(trigger), adUnitID=\(AdMobRuntimeConfiguration.redactedAdUnitID(interstitialAdUnitID)))"
        )

        GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: GADRequest()) { [weak self] ad, error in
            guard let self else { return }
            self.isInterstitialLoading = false

            if let error {
                DebugLogger.error("AdMob: Failed to load primary interstitial - \(error.localizedDescription)")
                self.interstitialAd = nil
                let nsError = error as NSError
                AdMobDiagnostics.log(error: nsError, context: "Primary interstitial load failure")
                let responseInfo = nsError.userInfo[GADErrorUserInfoKeyResponseInfo] as? GADResponseInfo
                AdMobDiagnostics.log(responseInfo: responseInfo, context: "Primary interstitial load failure")
                AdLoadMetricsRecorder.record(.interstitial, statusCode: nsError.code, error: nsError)

                if AdMobRuntimeConfiguration.isRequestTypeMismatch(nsError) {
                    DebugLogger.warning("AdMob: AdMobInterstitialAdUnitID 与 interstitial 请求类型不匹配，请检查 Xcode Cloud 配置")
                    return
                }

                if nsError.code == GADErrorCode.noFill.rawValue {
                    if self.canUseRewardedFallback {
                        DebugLogger.info("AdMob: Interstitial no-fill, trying rewarded interstitial fallback")
                        self.loadFallbackRewardedIfNeeded(trigger: "interstitial_nofill")
                    } else {
                        DebugLogger.info("AdMob: Interstitial no-fill, rewarded interstitial fallback disabled")
                    }
                }
                return
            }

            self.interstitialAd = ad
            self.interstitialAd?.fullScreenContentDelegate = self
            self.rewardedAd = nil
            DebugLogger.success("AdMob: Primary interstitial is ready")
            let responseInfo = ad?.responseInfo
            AdMobDiagnostics.log(responseInfo: responseInfo, context: "Primary interstitial load success")
            AdLoadMetricsRecorder.record(.interstitial, statusCode: 200, responseId: responseInfo?.responseIdentifier)
        }
    }

    private func loadFallbackRewardedIfNeeded(trigger: String) {
        guard AppSettings.shared.areAdsEnabled else { return }
        guard canUseRewardedFallback else { return }
        guard rewardedAd == nil else { return }
        guard !isRewardedLoading else { return }
        guard let rewardedAdUnitID = AdMobAdUnitIDs.rewardedInterstitial else {
            DebugLogger.warning("AdMob: 未配置奖励插屏广告位，无法执行兜底 (trigger=\(trigger))")
            return
        }

        isRewardedLoading = true
        DebugLogger.info(
            "AdMob: Start loading rewarded interstitial fallback (trigger=\(trigger), adUnitID=\(AdMobRuntimeConfiguration.redactedAdUnitID(rewardedAdUnitID)))"
        )

        GADRewardedInterstitialAd.load(
            withAdUnitID: rewardedAdUnitID,
            request: GADRequest()
        ) { [weak self] ad, error in
            guard let self else { return }
            self.isRewardedLoading = false
            if let error {
                DebugLogger.error("AdMob: Failed to load rewarded interstitial fallback - \(error.localizedDescription)")
                self.rewardedAd = nil
                let nsError = error as NSError
                AdMobDiagnostics.log(error: nsError, context: "Rewarded interstitial fallback load failure")
                let responseInfo = nsError.userInfo[GADErrorUserInfoKeyResponseInfo] as? GADResponseInfo
                AdMobDiagnostics.log(responseInfo: responseInfo, context: "Rewarded interstitial fallback load failure")
                AdLoadMetricsRecorder.record(.rewardedInterstitial, statusCode: nsError.code, error: nsError)

                if AdMobRuntimeConfiguration.isRequestTypeMismatch(nsError) {
                    self.isRewardedFallbackSuppressedForCurrentLaunch = true
                    DebugLogger.warning(
                        "AdMob: AdMobRewardedInterstitialAdUnitID 与 rewarded interstitial 请求类型不匹配，已在本次启动中停用兜底。请检查 Xcode Cloud 配置。"
                    )
                }
                return
            }

            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            DebugLogger.success("AdMob: Rewarded interstitial fallback is ready")
            let responseInfo = ad?.responseInfo
            AdMobDiagnostics.log(responseInfo: responseInfo, context: "Rewarded interstitial fallback load success")
            AdLoadMetricsRecorder.record(.rewardedInterstitial, statusCode: 200, responseId: responseInfo?.responseIdentifier)
        }
    }

    private var canUseRewardedFallback: Bool {
        AdMobFeatureFlags.isRewardedInterstitialFallbackEnabled && !isRewardedFallbackSuppressedForCurrentLaunch
    }

    private static func adTypeDescription(for ad: GADFullScreenPresentingAd) -> String {
        if ad is GADRewardedInterstitialAd {
            return "rewarded interstitial fallback"
        }
        if ad is GADInterstitialAd {
            return "interstitial primary"
        }
        return "full screen ad"
    }

    private func resetLoadedAds() {
        rewardedAd = nil
        interstitialAd = nil
        isRewardedLoading = false
        isInterstitialLoading = false
    }
}

extension RewardedInterstitialAdManager: GADFullScreenContentDelegate {
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        let adType = Self.adTypeDescription(for: ad)
        DebugLogger.error("AdMob: \(adType) failed to present - \(error.localizedDescription)")
        rewardedAd = nil
        interstitialAd = nil
        loadAd()
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        let adType = Self.adTypeDescription(for: ad)
        DebugLogger.info("AdMob: \(adType) dismissed, preparing next load")
        rewardedAd = nil
        interstitialAd = nil
        loadAd()
    }
}

extension UIViewController {
    static func topMostViewController(base: UIViewController? = UIViewController.activeRootViewController()) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return topMostViewController(base: navigationController.visibleViewController)
        }
        if let tabController = base as? UITabBarController {
            return topMostViewController(base: tabController.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }

    private static func activeRootViewController() -> UIViewController? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        for scene in foregroundScenes {
            if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                return root
            }
        }
        return nil
    }
}
