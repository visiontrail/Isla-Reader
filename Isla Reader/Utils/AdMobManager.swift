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

enum AdMobAdUnitIDs {
    static var fixedBanner: String? {
        resolvedID(for: "AdMobBannerAdUnitID")
    }

    static var rewardedInterstitial: String? {
        resolvedID(for: "AdMobRewardedInterstitialAdUnitID")
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
        }

        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: any Error) {
            DebugLogger.error("AdMob: Banner failed to load - \(error.localizedDescription)")
        }
    }
}

final class RewardedInterstitialAdManager: NSObject {
    static let shared = RewardedInterstitialAdManager()

    private var rewardedAd: GADRewardedInterstitialAd?
    private var isLoading = false
    private var pendingPresentation = false

    private override init() {
        super.init()
    }

    func loadAd() {
        guard let adUnitID = AdMobAdUnitIDs.rewardedInterstitial else {
            DebugLogger.warning("AdMob: 未配置奖励插屏广告位，跳过加载")
            pendingPresentation = false
            return
        }

        guard !isLoading else { return }
        isLoading = true
        DebugLogger.info("AdMob: Start loading rewarded interstitial")

        GADRewardedInterstitialAd.load(
            withAdUnitID: adUnitID,
            request: GADRequest()
        ) { [weak self] ad, error in
            guard let self else { return }
            self.isLoading = false
            if let error {
                DebugLogger.error("AdMob: Failed to load rewarded interstitial - \(error.localizedDescription)")
                self.rewardedAd = nil
                return
            }

            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            DebugLogger.success("AdMob: Rewarded interstitial is ready")

            if self.pendingPresentation {
                Task { @MainActor in
                    self.presentFromTopControllerIfAvailable()
                }
            }
        }
    }

    @MainActor
    func presentFromTopControllerIfAvailable() {
        guard let controller = UIViewController.topMostViewController() else {
            DebugLogger.warning("AdMob: Unable to find top view controller to present rewarded interstitial")
            return
        }
        present(from: controller, allowPending: true)
    }

    @MainActor
    private func present(from controller: UIViewController, allowPending: Bool = false) {
        guard let rewardedAd else {
            DebugLogger.warning("AdMob: Rewarded interstitial not ready, triggering reload")
            if allowPending {
                pendingPresentation = true
            }
            loadAd()
            return
        }

        pendingPresentation = false
        rewardedAd.present(fromRootViewController: controller) { [weak self] in
            DebugLogger.info("AdMob: User earned reward type=\(rewardedAd.adReward.type), amount=\(rewardedAd.adReward.amount)")
            self?.rewardedAd = nil
        }
    }
}

extension RewardedInterstitialAdManager: GADFullScreenContentDelegate {
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        DebugLogger.error("AdMob: Rewarded interstitial failed to present - \(error.localizedDescription)")
        rewardedAd = nil
        loadAd()
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        DebugLogger.info("AdMob: Rewarded interstitial dismissed, preparing next load")
        rewardedAd = nil
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
