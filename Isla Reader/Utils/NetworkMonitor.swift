//
//  NetworkMonitor.swift
//  LanRead
//

import Foundation
import Network

final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.islareader.network.monitor")
    private let stateQueue = DispatchQueue(label: "com.islareader.network.state")

    private var _isConnected = true
    private var started = false

    var onConnectivityChanged: (@Sendable (Bool) -> Void)?

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    var isConnected: Bool {
        stateQueue.sync { _isConnected }
    }

    func start() {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard !started else { return false }
            started = true
            return true
        }

        guard shouldStart else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            self?.updateConnectivity(path.status == .satisfied)
        }
        monitor.start(queue: monitorQueue)
    }

    private func updateConnectivity(_ isConnected: Bool) {
        let hasChanged = stateQueue.sync { () -> Bool in
            guard _isConnected != isConnected else { return false }
            _isConnected = isConnected
            return true
        }

        guard hasChanged else { return }
        DebugLogger.info("NetworkMonitor connectivity changed isConnected=\(isConnected)")
        onConnectivityChanged?(isConnected)
    }

    deinit {
        monitor.cancel()
    }
}
