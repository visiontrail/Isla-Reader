//
//  NetworkPermissionWarmup.swift
//  LanRead
//
//  Created by AI Assistant on 2025/2/26.
//

import Foundation

final class NetworkPermissionWarmup {
    static let shared = NetworkPermissionWarmup()
    
    private let lock = NSLock()
    private var hasTriggered = false
    
    private init() {}
    
    func triggerWarmupIfNeeded() {
        lock.lock()
        if hasTriggered {
            lock.unlock()
            return
        }
        hasTriggered = true
        lock.unlock()
        
        Task.detached(priority: .utility) { [weak self] in
            await self?.performWarmupRequest()
        }
    }
    
    @Sendable
    private func performWarmupRequest() async {
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else {
            DebugLogger.error("NetworkPermissionWarmup: 无法构建网络预热 URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        
        DebugLogger.info("NetworkPermissionWarmup: 启动时触发一次网络访问以提前弹出权限提示")
        
        do {
            _ = try await URLSession.shared.data(for: request)
            DebugLogger.success("NetworkPermissionWarmup: 预热请求完成")
        } catch {
            DebugLogger.warning("NetworkPermissionWarmup: 预热请求失败 \(error.localizedDescription)")
        }
    }
}
