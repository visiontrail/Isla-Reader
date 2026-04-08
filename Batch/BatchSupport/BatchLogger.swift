import Foundation

public enum BatchLogLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public struct BatchLogger: Sendable {
    private let sink: @Sendable (String) -> Void

    public init(sink: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.sink = sink
    }

    public func info(_ message: String) {
        write(level: .info, message: message)
    }

    public func warning(_ message: String) {
        write(level: .warning, message: message)
    }

    public func error(_ message: String) {
        write(level: .error, message: message)
    }

    public func write(level: BatchLogLevel, message: String) {
        sink(Self.render(level: level, message: message))
    }

    public func writeRaw(_ line: String) {
        sink(line)
    }

    public static func render(level: BatchLogLevel, message: String, date: Date = Date()) -> String {
        "[\(Self.iso8601.string(from: date))] [\(level.rawValue)] \(message)"
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

public struct BatchFileLogWriter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func prepareLogFile(at fileURL: URL) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            if !fileManager.fileExists(atPath: fileURL.path) {
                let created = fileManager.createFile(atPath: fileURL.path, contents: nil)
                if !created {
                    throw BatchError.ioFailure("Cannot create log file at \(fileURL.path).")
                }
            }
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.ioFailure("Cannot prepare log file at \(fileURL.path): \(error.localizedDescription)")
        }
    }

    public func append(_ line: String, to fileURL: URL) throws {
        do {
            try prepareLogFile(at: fileURL)
            guard let data = "\(line)\n".data(using: .utf8) else {
                throw BatchError.ioFailure("Cannot encode log line as UTF-8.")
            }

            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer { try? fileHandle.close() }
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: data)
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.ioFailure("Cannot append log file at \(fileURL.path): \(error.localizedDescription)")
        }
    }
}
