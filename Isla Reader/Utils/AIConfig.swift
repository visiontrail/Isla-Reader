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
            return "无法通过安全服务器获取 AI 配置：\(reason)"
        }
    }
}

enum AIConfig {
    static func current() async throws -> AIConfiguration {
        do {
            let serverConfig = try await SecureAPIKeyService.shared.fetchAIConfiguration()
            DebugLogger.success("AIConfig: 已通过安全服务器获取 AI 配置")
            DebugLogger.info("AIConfig: 服务器端点 = \(serverConfig.endpoint)")
            DebugLogger.info("AIConfig: 服务器模型 = \(serverConfig.model)")
            DebugLogger.info("AIConfig: 服务器 API Key = \(maskedKey(serverConfig.apiKey))")
            return AIConfiguration(endpoint: serverConfig.endpoint, apiKey: serverConfig.apiKey, model: serverConfig.model)
        } catch let error as SecureServerConfigError {
            DebugLogger.info("AIConfig: 安全服务器未配置或配置无效，将尝试使用本地配置。原因：\(error.localizedDescription)")
        } catch let error as SecureAPIKeyError {
            DebugLogger.warning("AIConfig: 无法通过安全服务器获取 AI 配置，将尝试使用本地配置。原因：\(error.localizedDescription)")
        } catch {
            DebugLogger.warning("AIConfig: 安全服务器请求失败，将尝试使用本地配置。原因：\(error.localizedDescription)")
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
            throw AIConfigError.missing(keys: missingKeys)
        }

        if apiKey.isEmpty {
            DebugLogger.error("AIConfig: 本地 API Key 为空且未能从安全服务器获取 AI 配置")
            throw AIConfigError.serverRequestFailed("安全服务器不可用且 AIAPIKey 未配置")
        }

        return AIConfiguration(endpoint: endpoint, apiKey: apiKey, model: model)
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
