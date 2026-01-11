//
//  DebugLogger.swift
//  LanRead
//
//  Created by AI Assistant on 2025/1/20.
//

import Foundation
import os.log

class DebugLogger {
    static let shared = DebugLogger()
    
    private let logger = Logger(subsystem: "com.islareader.app", category: "FileImport")
    
    private init() {}
    
    func log(_ message: String, level: OSLogType = .default, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        
        logger.log(level: level, "\(logMessage)")
        
        // 同时输出到控制台以便在Xcode中查看
        print("🔍 [\(getCurrentTimestamp())] \(logMessage)")
    }
    
    func logError(_ message: String, error: Error? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log("❌ \(fullMessage)", level: .error, function: function, file: file, line: line)
    }
    
    func logWarning(_ message: String, function: String = #function, file: String = #file, line: Int = #line) {
        log("⚠️ \(message)", level: .info, function: function, file: file, line: line)
    }
    
    func logInfo(_ message: String, function: String = #function, file: String = #file, line: Int = #line) {
        log("ℹ️ \(message)", level: .info, function: function, file: file, line: line)
    }
    
    func logSuccess(_ message: String, function: String = #function, file: String = #file, line: Int = #line) {
        log("✅ \(message)", level: .info, function: function, file: file, line: line)
    }
    
    // 静态方法便于使用
    static func error(_ message: String, error: Error? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        shared.logError(message, error: error, function: function, file: file, line: line)
    }
    
    static func warning(_ message: String, function: String = #function, file: String = #file, line: Int = #line) {
        shared.logWarning(message, function: function, file: file, line: line)
    }
    
    static func info(_ message: String, function: String = #function, file: String = #file, line: Int = #line) {
        shared.logInfo(message, function: function, file: file, line: line)
    }
    
    static func success(_ message: String, function: String = #function, file: String = #file, line: Int = #line) {
        shared.logSuccess(message, function: function, file: file, line: line)
    }
    
    private func getCurrentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}