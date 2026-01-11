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
            return "无法通过安全服务器获取 API Key：\(reason)"
        }
    }
}

enum AIConfig {
    static func current() async throws -> AIConfiguration {
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
            DebugLogger.error("AIConfig: 配置缺失 \(joinedKeys)")
            throw AIConfigError.missing(keys: missingKeys)
        }

        if !apiKey.isEmpty {
            return AIConfiguration(endpoint: endpoint, apiKey: apiKey, model: model)
        }

        DebugLogger.info("AIConfig: 未检测到本地 API Key，尝试通过安全服务器获取")

        do {
            let serverKey = try await SecureAPIKeyService.shared.fetchAPIKey()
            DebugLogger.success("AIConfig: 已通过安全服务器获取 API Key")
            return AIConfiguration(endpoint: endpoint, apiKey: serverKey, model: model)
        } catch let error as SecureServerConfigError {
            throw AIConfigError.serverConfig(error.localizedDescription)
        } catch let error as SecureAPIKeyError {
            throw AIConfigError.serverRequestFailed(error.localizedDescription)
        }
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
