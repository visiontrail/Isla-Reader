import BatchSupport
import Foundation

public struct CaptionsCommandOptions: Equatable, Sendable {
    public var manifestPath: String
    public var showHelp: Bool

    public init(manifestPath: String, showHelp: Bool) {
        self.manifestPath = manifestPath
        self.showHelp = showHelp
    }

    public static var defaults: CaptionsCommandOptions {
        CaptionsCommandOptions(manifestPath: "", showHelp: false)
    }

    public static func parse(arguments: [String]) throws -> CaptionsCommandOptions {
        var options = Self.defaults
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            if argument == "-h" || argument == "--help" {
                options.showHelp = true
                index += 1
                continue
            }

            guard argument.hasPrefix("--") else {
                throw BatchError.invalidOption(argument)
            }

            let token = String(argument.dropFirst(2))
            let optionName: String
            let inlineValue: String?
            if let equalIndex = token.firstIndex(of: "=") {
                optionName = String(token[..<equalIndex])
                inlineValue = String(token[token.index(after: equalIndex)...])
            } else {
                optionName = token
                inlineValue = nil
            }

            let value: String
            if let inlineValue {
                value = inlineValue
                index += 1
            } else {
                guard index + 1 < arguments.count else {
                    throw BatchError.missingOptionValue("--\(optionName)")
                }
                value = arguments[index + 1]
                index += 2
            }

            switch optionName {
            case "manifest":
                options.manifestPath = value
            default:
                throw BatchError.invalidOption("--\(optionName)")
            }
        }

        if !options.showHelp {
            let manifestPath = options.manifestPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if manifestPath.isEmpty {
                throw BatchError.missingRequiredOption("--manifest")
            }
        }

        return options
    }
}
