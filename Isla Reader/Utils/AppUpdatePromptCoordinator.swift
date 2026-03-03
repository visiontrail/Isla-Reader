//
//  AppUpdatePromptCoordinator.swift
//  LanRead
//

import Foundation

private enum AppUpdatePromptDefaultsKey {
    static let softSignature = "app_update_soft_signature"
    static let softShownAt = "app_update_soft_shown_at"
}

private enum AppUpdatePolicyMode: String {
    case soft
    case hard
}

private struct AppUpdatePolicyPayload: Decodable {
    let enabled: Bool
    let mode: String
    let latestVersion: String
    let minimumSupportedVersion: String
    let title: String
    let message: String
    let appStoreURL: String
    let remindIntervalHours: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case latestVersion = "latest_version"
        case minimumSupportedVersion = "minimum_supported_version"
        case title
        case message
        case appStoreURL = "app_store_url"
        case remindIntervalHours = "remind_interval_hours"
    }
}

enum AppUpdateCheckTrigger {
    case launch
    case foreground
}

struct AppUpdatePrompt: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let appStoreURL: URL
    let isMandatory: Bool
}

@MainActor
final class AppUpdatePromptCoordinator: ObservableObject {
    static let shared = AppUpdatePromptCoordinator()

    @Published var activePrompt: AppUpdatePrompt?

    private let session: URLSession
    private let defaults: UserDefaults
    private var isChecking = false
    private var lastCheckAt: Date?
    private let foregroundThrottleSeconds: TimeInterval = 5 * 60

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    func checkForUpdateIfNeeded(trigger: AppUpdateCheckTrigger) {
        if trigger == .foreground,
           let lastCheckAt,
           Date().timeIntervalSince(lastCheckAt) < foregroundThrottleSeconds {
            return
        }
        guard !isChecking else { return }
        isChecking = true
        lastCheckAt = Date()

        Task {
            defer { isChecking = false }
            guard let prompt = await resolvePrompt() else { return }

            if let existing = activePrompt {
                if existing.isMandatory {
                    return
                }
                if prompt.isMandatory {
                    activePrompt = prompt
                }
                return
            }

            activePrompt = prompt
        }
    }

    func consumePrompt() {
        activePrompt = nil
    }

    private func resolvePrompt() async -> AppUpdatePrompt? {
        let policy: AppUpdatePolicyPayload
        do {
            policy = try await fetchPolicy()
        } catch {
            DebugLogger.warning("AppUpdatePromptCoordinator: 拉取更新策略失败 - \(error.localizedDescription)")
            return nil
        }

        guard policy.enabled else { return nil }

        let latest = policy.latestVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let minimum = policy.minimumSupportedVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        let currentVersion = Self.currentAppVersion()
        let isBelowMinimum = !minimum.isEmpty && Self.compareVersion(currentVersion, minimum) == .orderedAscending
        let isBehindLatest = !latest.isEmpty && Self.compareVersion(currentVersion, latest) == .orderedAscending

        guard isBelowMinimum || isBehindLatest else { return nil }

        let mode = AppUpdatePolicyMode(rawValue: policy.mode.lowercased()) ?? .soft
        let isMandatory = isBelowMinimum || mode == .hard

        let signature = "\(policy.mode)|\(latest)|\(minimum)|\(policy.title)|\(policy.message)|\(policy.appStoreURL)"
        if !isMandatory {
            let interval = max(1, policy.remindIntervalHours)
            guard shouldShowSoftPrompt(signature: signature, intervalHours: interval) else {
                return nil
            }
            recordSoftPromptShown(signature: signature)
        }

        guard let targetURL = Self.normalizedStoreURL(policy.appStoreURL) else {
            DebugLogger.warning("AppUpdatePromptCoordinator: 策略缺少有效 App Store 链接，跳过提示")
            return nil
        }

        let title = {
            let trimmed = policy.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            return NSLocalizedString("update.prompt.default_title", comment: "")
        }()

        let message = {
            let trimmed = policy.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            return isMandatory
                ? NSLocalizedString("update.prompt.default_message_hard", comment: "")
                : NSLocalizedString("update.prompt.default_message_soft", comment: "")
        }()

        let promptID = "\(signature)|mandatory=\(isMandatory)"
        return AppUpdatePrompt(
            id: promptID,
            title: title,
            message: message,
            appStoreURL: targetURL,
            isMandatory: isMandatory
        )
    }

    private func fetchPolicy() async throws -> AppUpdatePolicyPayload {
        let config = try SecureServerConfig.current()
        guard let endpointURL = URL(string: "/v1/app/update-policy", relativeTo: config.baseURL),
              var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: true) else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "current_version", value: Self.currentAppVersion()),
            URLQueryItem(name: "current_build", value: Self.currentBuildNumber())
        ]

        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AppUpdatePolicyPayload.self, from: data)
    }

    private func shouldShowSoftPrompt(signature: String, intervalHours: Int) -> Bool {
        let lastSignature = defaults.string(forKey: AppUpdatePromptDefaultsKey.softSignature)
        let lastShownAt = defaults.object(forKey: AppUpdatePromptDefaultsKey.softShownAt) as? Date

        guard lastSignature == signature, let lastShownAt else {
            return true
        }

        let requiredInterval = TimeInterval(intervalHours) * 3600
        return Date().timeIntervalSince(lastShownAt) >= requiredInterval
    }

    private func recordSoftPromptShown(signature: String) {
        defaults.set(signature, forKey: AppUpdatePromptDefaultsKey.softSignature)
        defaults.set(Date(), forKey: AppUpdatePromptDefaultsKey.softShownAt)
    }

    private static func currentAppVersion() -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return (value ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func currentBuildNumber() -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return (value ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedStoreURL(_ rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        let allowedSchemes = ["itms-apps", "https", "http"]
        guard allowedSchemes.contains(scheme) else { return nil }
        return url
    }

    private static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let maxCount = max(left.count, right.count)

        for index in 0..<maxCount {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionComponents(_ value: String) -> [Int] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [0] }
        let separators = CharacterSet(charactersIn: ".-_")
        return trimmed
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .map { segment in
                let digits = segment.prefix { $0.isNumber }
                if digits.isEmpty {
                    return 0
                }
                return Int(digits) ?? 0
            }
    }
}
