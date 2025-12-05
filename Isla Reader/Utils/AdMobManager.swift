//
//  AdMobManager.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/3/4.
//

import Foundation
import GoogleMobileAds
import SwiftUI
import UIKit

enum AdMobAdUnitIDs {
    static let fixedBanner = "ca-app-pub-3940256099942544/2934735716"
    static let rewardedInterstitial = "ca-app-pub-3940256099942544/6978759866"
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

    private override init() {
        super.init()
    }

    func loadAd() {
        guard !isLoading else { return }
        isLoading = true
        DebugLogger.info("AdMob: Start loading rewarded interstitial")

        GADRewardedInterstitialAd.load(
            withAdUnitID: AdMobAdUnitIDs.rewardedInterstitial,
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
        }
    }

    @MainActor
    func presentFromTopControllerIfAvailable() {
        guard let controller = UIViewController.topMostViewController() else {
            DebugLogger.warning("AdMob: Unable to find top view controller to present rewarded interstitial")
            return
        }
        present(from: controller)
    }

    @MainActor
    private func present(from controller: UIViewController) {
        guard let rewardedAd else {
            DebugLogger.warning("AdMob: Rewarded interstitial not ready, triggering reload")
            loadAd()
            return
        }

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
