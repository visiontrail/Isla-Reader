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

enum AdMobAdUnitIDs {
    static var fixedBanner: String? {
        resolvedID(for: "AdMobBannerAdUnitID")
    }

    static var rewardedInterstitial: String? {
        resolvedID(for: "AdMobRewardedInterstitialAdUnitID")
    }

    static var interstitial: String? {
        resolvedID(for: "AdMobInterstitialAdUnitID")
    }

    private static func resolvedID(for infoPlistKey: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            DebugLogger.warning("AdMob: Info.plist 缺少键 \(infoPlistKey)，已跳过广告请求")
            return nil
        }

        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.isEmpty {
            DebugLogger.warning("AdMob: \(infoPlistKey) 为空，已跳过广告请求")
            return nil
        }

        if value.hasPrefix("$(") {
            DebugLogger.warning("AdMob: \(infoPlistKey) 未通过 xcconfig 替换，已跳过广告请求")
            return nil
        }

        // Google 官方测试广告位 ID，发布不可使用
        if value.contains("ca-app-pub-3940256099942544") {
            DebugLogger.warning("AdMob: \(infoPlistKey) 为测试广告位 ID，发布版禁用广告请求")
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

    private override init() {
        super.init()
    }

    func loadAd() {
        if rewardedAd != nil || interstitialAd != nil {
            return
        }

        loadPrimaryInterstitialIfNeeded(trigger: "initial")
    }

    func availabilityStatus() -> RewardedInterstitialAvailability {
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
            DebugLogger.info("AdMob: Presenting primary interstitial ad")
            interstitialAd.present(fromRootViewController: controller)
            return
        }

        if let rewardedAd {
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
        guard interstitialAd == nil else { return }
        guard !isInterstitialLoading else { return }
        guard let interstitialAdUnitID = AdMobAdUnitIDs.interstitial else {
            DebugLogger.warning("AdMob: 未配置插屏广告位，尝试奖励插屏兜底 (trigger=\(trigger))")
            loadFallbackRewardedIfNeeded(trigger: "interstitial_unconfigured")
            return
        }

        isInterstitialLoading = true
        DebugLogger.info("AdMob: Start loading primary interstitial (trigger=\(trigger))")

        GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: GADRequest()) { [weak self] ad, error in
            guard let self else { return }
            self.isInterstitialLoading = false

            if let error {
                DebugLogger.error("AdMob: Failed to load primary interstitial - \(error.localizedDescription)")
                self.interstitialAd = nil
                let nsError = error as NSError
                AdLoadMetricsRecorder.record(.interstitial, statusCode: nsError.code, error: nsError)

                if nsError.code == GADErrorCode.noFill.rawValue {
                    DebugLogger.info("AdMob: Interstitial no-fill, trying rewarded interstitial fallback")
                    self.loadFallbackRewardedIfNeeded(trigger: "interstitial_nofill")
                }
                return
            }

            self.interstitialAd = ad
            self.interstitialAd?.fullScreenContentDelegate = self
            self.rewardedAd = nil
            DebugLogger.success("AdMob: Primary interstitial is ready")
            AdLoadMetricsRecorder.record(.interstitial, statusCode: 200)
        }
    }

    private func loadFallbackRewardedIfNeeded(trigger: String) {
        guard rewardedAd == nil else { return }
        guard !isRewardedLoading else { return }
        guard let rewardedAdUnitID = AdMobAdUnitIDs.rewardedInterstitial else {
            DebugLogger.warning("AdMob: 未配置奖励插屏广告位，无法执行兜底 (trigger=\(trigger))")
            return
        }

        isRewardedLoading = true
        DebugLogger.info("AdMob: Start loading rewarded interstitial fallback (trigger=\(trigger))")

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
                AdLoadMetricsRecorder.record(.rewardedInterstitial, statusCode: nsError.code, error: nsError)
                return
            }

            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            DebugLogger.success("AdMob: Rewarded interstitial fallback is ready")
            AdLoadMetricsRecorder.record(.rewardedInterstitial, statusCode: 200)
        }
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
