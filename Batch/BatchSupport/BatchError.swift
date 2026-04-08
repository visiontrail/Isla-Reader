import Foundation

public enum BatchError: LocalizedError, CustomStringConvertible, Equatable {
    case invalidCommand(String)
    case unsupportedCommand(String)
    case invalidOption(String)
    case missingOptionValue(String)
    case missingRequiredOption(String)
    case invalidIntegerOption(name: String, value: String)
    case fileNotFound(String)
    case ioFailure(String)
    case runtime(String)

    public var exitCode: Int {
        switch self {
        case .invalidCommand, .unsupportedCommand, .invalidOption, .missingOptionValue, .missingRequiredOption, .invalidIntegerOption:
            return 64
        case .fileNotFound:
            return 66
        case .ioFailure, .runtime:
            return 1
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidCommand(let command):
            return "Unknown command: \(command). Run `lanread-batch --help`."
        case .unsupportedCommand(let command):
            return "Command `\(command)` is reserved but not implemented in this phase."
        case .invalidOption(let option):
            return "Unknown or invalid option: \(option)."
        case .missingOptionValue(let option):
            return "Missing value for option: \(option)."
        case .missingRequiredOption(let option):
            return "Missing required option: \(option)."
        case let .invalidIntegerOption(name, value):
            return "Option \(name) expects a positive integer, received: \(value)."
        case .fileNotFound(let path):
            return "File not found: \(path)."
        case .ioFailure(let message):
            return "I/O failure: \(message)"
        case .runtime(let message):
            return message
        }
    }

    public var description: String {
        errorDescription ?? "Unknown batch error."
    }
}
