//
//  AIConfig.swift
//  Isla Reader
//

import Foundation

struct AIConfiguration {
    let endpoint: String
    let apiKey: String
    let model: String
}

enum AIConfigError: LocalizedError {
    case missing(keys: [String])
    
    var errorDescription: String? {
        switch self {
        case .missing(let keys):
            let joined = keys.joined(separator: ", ")
            return "AI API 配置缺失：\(joined)。请检查 Config/AISecrets.xcconfig。"
        }
    }
}

enum AIConfig {
    static func current() throws -> AIConfiguration {
        let endpoint = trimmedValue(for: "AIAPIEndpoint")
        var apiKey = trimmedValue(for: "AIAPIKey")
        let model = trimmedValue(for: "AIModel")
        
        if apiKey == "replace-with-your-key" {
            DebugLogger.warning("AIConfig: API key 仍是占位符，请更新 Config/AISecrets.xcconfig。")
            apiKey = ""
        }
        
        var missingKeys: [String] = []
        if endpoint.isEmpty { missingKeys.append("AIAPIEndpoint") }
        if apiKey.isEmpty { missingKeys.append("AIAPIKey") }
        if model.isEmpty { missingKeys.append("AIModel") }
        
        if !missingKeys.isEmpty {
            let joinedKeys = missingKeys.joined(separator: ", ")
            DebugLogger.error("AIConfig: 配置缺失 \(joinedKeys)")
            throw AIConfigError.missing(keys: missingKeys)
        }
        
        return AIConfiguration(endpoint: endpoint, apiKey: apiKey, model: model)
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
