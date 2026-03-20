//
//  AIConfig.swift
//  LanRead
//

import Foundation

struct AIConfiguration {
    let endpoint: String
    let apiKey: String
    let model: String
}

struct AIEndpointLocationDescriptor {
    let code: String
    let descriptionLocalizationKey: String
}

private struct AIEndpointLocationRule {
    let code: String
    let descriptionLocalizationKey: String
    let hostPatterns: [String]

    func matches(host: String) -> Bool {
        hostPatterns.contains { pattern in
            host == pattern || host.hasSuffix(".\(pattern)")
        }
    }
}

private enum AIEndpointLocationRegistry {
    // Extend this list when adding new endpoint regions.
    static let rules: [AIEndpointLocationRule] = [
        AIEndpointLocationRule(
            code: "us",
            descriptionLocalizationKey: "ai.provider.location.us",
            hostPatterns: ["dashscope-us.aliyuncs.com"]
        ),
        AIEndpointLocationRule(
            code: "intl",
            descriptionLocalizationKey: "ai.provider.location.intl",
            hostPatterns: ["dashscope-intl.aliyuncs.com"]
        )
    ]

    static func resolve(host: String) -> AIEndpointLocationDescriptor? {
        guard let matched = rules.first(where: { $0.matches(host: host) }) else {
            return nil
        }
        return AIEndpointLocationDescriptor(
            code: matched.code,
            descriptionLocalizationKey: matched.descriptionLocalizationKey
        )
    }
}

struct AIProviderDescriptor {
    let providerName: String
    let host: String
    let endpointLocation: AIEndpointLocationDescriptor?

    var displayNameWithHost: String {
        "\(providerName) (\(host))"
    }

    var isUnknown: Bool {
        providerName == AIProviderDescriptor.unknown.providerName &&
        host == AIProviderDescriptor.unknown.host
    }

    static var unknown: AIProviderDescriptor {
        AIProviderDescriptor(providerName: "Unknown Provider", host: "Unknown Host", endpointLocation: nil)
    }

    static func from(endpoint: String) -> AIProviderDescriptor? {
        guard let url = URL(string: endpoint), let host = url.host else {
            return nil
        }

        let normalizedHost = host.lowercased()
        let providerName = inferProviderName(from: normalizedHost)
        let endpointLocation = AIEndpointLocationRegistry.resolve(host: normalizedHost)
        return AIProviderDescriptor(providerName: providerName, host: host, endpointLocation: endpointLocation)
    }

    private static func inferProviderName(from host: String) -> String {
        if host.contains("azure") && host.contains("openai") {
            return "Microsoft Azure OpenAI"
        }
        if host.contains("openai") {
            return "OpenAI"
        }
        if host.contains("anthropic") {
            return "Anthropic"
        }
        if host.contains("googleapis") || host.contains("gemini") || host.contains("generativelanguage") {
            return "Google AI"
        }
        if host.contains("x.ai") || host.contains("xai") {
            return "xAI"
        }
        if host.contains("deepseek") {
            return "DeepSeek"
        }
        if host.contains("moonshot") || host.contains("kimi") {
            return "Moonshot AI"
        }
        if host.contains("zhipu") {
            return "Zhipu AI"
        }
        if host.contains("qianfan") || host.contains("wenxin") || host.contains("baidu") {
            return "Baidu AI"
        }
        if host.contains("dashscope") || host.contains("aliyun") || host.contains("tongyi") {
            return "Alibaba Cloud (DashScope)"
        }
        if host.contains("volcengine") || host.contains("doubao") {
            return "Volcengine (Doubao)"
        }
        return "Custom AI Provider"
    }
}

enum AIConfigError: LocalizedError {
    case missing(keys: [String])
    case serverConfig(String)
    case serverRequestFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missing(let keys):
            let joined = keys.joined(separator: ", ")
            return "AI API 配置缺失：\(joined)。请检查 Config/AISecrets.xcconfig。"
        case .serverConfig(let reason):
            return "AI 安全服务器配置错误：\(reason)"
        case .serverRequestFailed(let reason):
            return "无法通过安全服务器获取 AI 配置：\(reason)"
        }
    }
}

enum AIConfig {
    static func current() async throws -> AIConfiguration {
        var secureServerFailureReason: String?

        do {
            let serverConfig = try await SecureAPIKeyService.shared.fetchAIConfiguration()
            DebugLogger.success("AIConfig: 已通过安全服务器获取 AI 配置")
            DebugLogger.info("AIConfig: 服务器端点 = \(serverConfig.endpoint)")
            DebugLogger.info("AIConfig: 服务器模型 = \(serverConfig.model)")
            DebugLogger.info("AIConfig: 服务器 API Key = \(maskedKey(serverConfig.apiKey))")
            return AIConfiguration(endpoint: serverConfig.endpoint, apiKey: serverConfig.apiKey, model: serverConfig.model)
        } catch let error as SecureServerConfigError {
            let reason = error.localizedDescription
            secureServerFailureReason = reason
            DebugLogger.info("AIConfig: 安全服务器未配置或配置无效，将尝试使用本地配置。原因：\(reason)")
        } catch let error as SecureAPIKeyError {
            let reason = error.localizedDescription
            secureServerFailureReason = reason
            DebugLogger.warning("AIConfig: 无法通过安全服务器获取 AI 配置，将尝试使用本地配置。原因：\(reason)")
        } catch {
            let reason = error.localizedDescription
            secureServerFailureReason = reason
            DebugLogger.warning("AIConfig: 安全服务器请求失败，将尝试使用本地配置。原因：\(reason)")
        }

        let endpoint = trimmedValue(for: "AIAPIEndpoint")
        var apiKey = trimmedValue(for: "AIAPIKey")
        let model = trimmedValue(for: "AIModel")
        
        if apiKey == "replace-with-your-key" {
            DebugLogger.warning("AIConfig: API key 仍是占位符，请更新 Config/AISecrets.xcconfig。")
            apiKey = ""
        }
        
        var missingKeys: [String] = []
        if endpoint.isEmpty { missingKeys.append("AIAPIEndpoint") }
        if model.isEmpty { missingKeys.append("AIModel") }
        
        if !missingKeys.isEmpty {
            let joinedKeys = missingKeys.joined(separator: ", ")
            DebugLogger.error("AIConfig: 配置缺失 \(joinedKeys) 且未能从安全服务器获取 AI 配置")
            if let reason = secureServerFailureReason {
                throw AIConfigError.serverRequestFailed("\(reason)；并且本地配置缺少：\(joinedKeys)")
            }
            throw AIConfigError.missing(keys: missingKeys)
        }

        if apiKey.isEmpty {
            DebugLogger.error("AIConfig: 本地 API Key 为空且未能从安全服务器获取 AI 配置")
            if let reason = secureServerFailureReason {
                throw AIConfigError.serverRequestFailed("\(reason)；并且本地 AIAPIKey 未配置")
            }
            throw AIConfigError.serverRequestFailed("安全服务器不可用且 AIAPIKey 未配置")
        }

        return AIConfiguration(endpoint: endpoint, apiKey: apiKey, model: model)
    }

    static func endpointForDisclosure() async -> String? {
        do {
            let serverConfig = try await SecureAPIKeyService.shared.fetchAIConfiguration()
            let endpoint = serverConfig.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !endpoint.isEmpty {
                return endpoint
            }
        } catch {
            DebugLogger.info("AIConfig: provider disclosure fallback to local endpoint. reason=\(error.localizedDescription)")
        }

        let localEndpoint = trimmedValue(for: "AIAPIEndpoint")
        return localEndpoint.isEmpty ? nil : localEndpoint
    }

    static func currentProviderDescriptor() async -> AIProviderDescriptor {
        guard let endpoint = await endpointForDisclosure(),
              let descriptor = AIProviderDescriptor.from(endpoint: endpoint) else {
            return .unknown
        }
        return descriptor
    }
    
    private static func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "*", count: key.count) }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)****\(suffix)"
    }
    
    private static func trimmedValue(for infoPlistKey: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            DebugLogger.warning("AIConfig: Info.plist 缺少键 \(infoPlistKey)")
            return ""
        }
        
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the placeholder was not substituted by xcconfig, ignore it and ask user to configure.
        if value.hasPrefix("$(") {
            DebugLogger.warning("AIConfig: \(infoPlistKey) 未通过 xcconfig 替换，请检查 Config/AISecrets.xcconfig。")
            return ""
        }
        
        // Allow escaped forward slashes (e.g. https:\/\/host) in xcconfig values.
        return value.replacingOccurrences(of: "\\/", with: "/")
    }
}

enum AICompatibilityOptions {
    static func shouldExplicitlyDisableThinking(for endpoint: String) -> Bool {
        guard let host = URL(string: endpoint)?.host?.lowercased() else {
            return false
        }
        return host.contains("dashscope") || host.contains("aliyun") || host.contains("tongyi")
    }
}

final class AIConsentManager: ObservableObject {
    static let shared = AIConsentManager()

    @Published var isLaunchConsentPresented = false

    private enum Keys {
        static let permissionGranted = "aiPrivacyPermissionGranted"
        static let suppressLaunchPrompt = "aiPrivacySuppressLaunchPrompt"
        static let consentVersion = "aiPrivacyConsentVersion"
    }

    private let requiredConsentVersion = 2
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    @MainActor
    func presentLaunchConsentIfNeeded() {
        if needsConsentRefresh() {
            defaults.set(false, forKey: Keys.permissionGranted)
            defaults.set(false, forKey: Keys.suppressLaunchPrompt)
        }

        guard !defaults.bool(forKey: Keys.suppressLaunchPrompt) else {
            isLaunchConsentPresented = false
            return
        }
        isLaunchConsentPresented = true
    }

    @MainActor
    func presentLaunchConsentManually() {
        isLaunchConsentPresented = true
    }

    @MainActor
    func recordConsentDecision(granted: Bool, suppressFutureLaunchPrompt: Bool) {
        defaults.set(granted, forKey: Keys.permissionGranted)
        defaults.set(suppressFutureLaunchPrompt, forKey: Keys.suppressLaunchPrompt)
        defaults.set(requiredConsentVersion, forKey: Keys.consentVersion)
        isLaunchConsentPresented = false
        DebugLogger.info(
            "AIConsentManager: updated consent. granted=\(granted), suppressFutureLaunchPrompt=\(suppressFutureLaunchPrompt)"
        )
    }

    func isPermissionGranted() -> Bool {
        hasExplicitPermission()
    }

    func hasExplicitPermission() -> Bool {
        defaults.bool(forKey: Keys.permissionGranted) && !needsConsentRefresh()
    }

    private func needsConsentRefresh() -> Bool {
        defaults.integer(forKey: Keys.consentVersion) < requiredConsentVersion
    }
}
