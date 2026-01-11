//
//  SecureServerConfig.swift
//  LanRead
//

import Foundation

struct SecureServerConfiguration {
    let baseURL: URL
    let clientId: String
    let clientSecret: String
    let requireTLS: Bool
}

enum SecureServerConfigError: LocalizedError {
    case missing(keys: [String])
    case invalidURL
    case insecureURL

    var errorDescription: String? {
        switch self {
        case .missing(let keys):
            let joined = keys.joined(separator: ", ")
            return "安全服务器配置缺失：\(joined)"
        case .invalidURL:
            return "安全服务器地址无效"
        case .insecureURL:
            return "安全服务器必须使用 HTTPS"
        }
    }
}

enum SecureServerConfig {
    static func current() throws -> SecureServerConfiguration {
        let baseURLString = trimmedValue(for: "SecureServerBaseURL")
        let clientId = trimmedValue(for: "SecureServerClientID")
        let clientSecret = trimmedValue(for: "SecureServerClientSecret")
        let requireTLSSource = trimmedValue(for: "SecureServerRequireTLS")

        var missing: [String] = []
        if baseURLString.isEmpty { missing.append("SecureServerBaseURL") }
        if clientId.isEmpty { missing.append("SecureServerClientID") }
        if clientSecret.isEmpty { missing.append("SecureServerClientSecret") }

        if !missing.isEmpty {
            DebugLogger.error("SecureServerConfig: 缺少配置 \(missing.joined(separator: ", "))")
            throw SecureServerConfigError.missing(keys: missing)
        }

        guard let baseURL = URL(string: baseURLString) else {
            DebugLogger.error("SecureServerConfig: 基础地址无效")
            throw SecureServerConfigError.invalidURL
        }

        let requireTLS = parseBool(requireTLSSource, defaultValue: true)
        if requireTLS && baseURL.scheme?.lowercased() != "https" {
            DebugLogger.error("SecureServerConfig: 仅允许 HTTPS 连接")
            throw SecureServerConfigError.insecureURL
        }

        return SecureServerConfiguration(
            baseURL: baseURL,
            clientId: clientId,
            clientSecret: clientSecret,
            requireTLS: requireTLS
        )
    }

    private static func parseBool(_ value: String, defaultValue: Bool) -> Bool {
        guard !value.isEmpty else { return defaultValue }
        let lowered = value.lowercased()
        return lowered == "1" || lowered == "true" || lowered == "yes"
    }

    private static func trimmedValue(for infoPlistKey: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            return ""
        }

        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("$(") {
            return ""
        }

        return value.replacingOccurrences(of: "\\/", with: "/")
    }
}
