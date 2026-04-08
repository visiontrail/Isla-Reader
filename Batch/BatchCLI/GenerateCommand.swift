import BatchModels
import BatchSupport
import Foundation

public struct GenerateCommandOptions: Equatable, Sendable {
    public var epubPath: String?
    public var inputDirectoryPath: String?
    public var outputPath: String
    public var targetHighlightCount: Int
    public var language: String
    public var style: ShareCardStyle
    public var providerConfigPath: String?
    public var overwritePolicy: BatchRunConfig.OverwritePolicy
    public var profileDisplayName: String
    public var profileAvatarPath: String?
    public var timeZoneIdentifier: String?
    public var showHelp: Bool

    public init(
        epubPath: String?,
        inputDirectoryPath: String?,
        outputPath: String,
        targetHighlightCount: Int,
        language: String,
        style: ShareCardStyle,
        providerConfigPath: String?,
        overwritePolicy: BatchRunConfig.OverwritePolicy,
        profileDisplayName: String,
        profileAvatarPath: String?,
        timeZoneIdentifier: String?,
        showHelp: Bool
    ) {
        self.epubPath = epubPath
        self.inputDirectoryPath = inputDirectoryPath
        self.outputPath = outputPath
        self.targetHighlightCount = targetHighlightCount
        self.language = language
        self.style = style
        self.providerConfigPath = providerConfigPath
        self.overwritePolicy = overwritePolicy
        self.profileDisplayName = profileDisplayName
        self.profileAvatarPath = profileAvatarPath
        self.timeZoneIdentifier = timeZoneIdentifier
        self.showHelp = showHelp
    }

    public static var defaults: GenerateCommandOptions {
        GenerateCommandOptions(
            epubPath: nil,
            inputDirectoryPath: nil,
            outputPath: "",
            targetHighlightCount: 20,
            language: "zh-Hans",
            style: .white,
            providerConfigPath: nil,
            overwritePolicy: .resume,
            profileDisplayName: "Reader",
            profileAvatarPath: nil,
            timeZoneIdentifier: nil,
            showHelp: false
        )
    }

    public static func parse(arguments: [String]) throws -> GenerateCommandOptions {
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
            case "epub":
                options.epubPath = value
            case "input-dir":
                options.inputDirectoryPath = value
            case "output":
                options.outputPath = value
            case "highlights":
                guard let parsed = Int(value), parsed > 0 else {
                    throw BatchError.invalidIntegerOption(name: "--highlights", value: value)
                }
                options.targetHighlightCount = parsed
            case "language":
                options.language = value
            case "style":
                guard let style = ShareCardStyle(rawValue: value) else {
                    throw BatchError.invalidOption("--style=\(value)")
                }
                options.style = style
            case "provider-config":
                options.providerConfigPath = value
            case "overwrite-policy":
                guard let overwritePolicy = BatchRunConfig.OverwritePolicy(rawValue: value) else {
                    throw BatchError.invalidOption("--overwrite-policy=\(value)")
                }
                options.overwritePolicy = overwritePolicy
            case "profile-name":
                options.profileDisplayName = value
            case "profile-avatar":
                options.profileAvatarPath = value
            case "timezone":
                options.timeZoneIdentifier = value
            default:
                throw BatchError.invalidOption("--\(optionName)")
            }
        }

        if !options.showHelp {
            guard !options.outputPath.isEmpty else {
                throw BatchError.missingRequiredOption("--output")
            }

            let hasEPUB = !(options.epubPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasInputDirectory = !(options.inputDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            if hasEPUB == hasInputDirectory {
                if hasEPUB {
                    throw BatchError.invalidOption("--epub and --input-dir cannot be used together")
                }
                throw BatchError.missingRequiredOption("--epub or --input-dir")
            }
        }

        return options
    }

    public func toRunConfig(epubPath overrideEPUBPath: String? = nil) throws -> BatchRunConfig {
        let resolvedEPUBPath = (overrideEPUBPath ?? epubPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedEPUBPath.isEmpty else {
            throw BatchError.missingRequiredOption("--epub")
        }
        let normalizedProfileDisplayName = Self.normalizedProfileDisplayName(profileDisplayName)
        let trimmedProfileAvatarPath = profileAvatarPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTimeZoneIdentifier = try Self.normalizedTimeZoneIdentifier(timeZoneIdentifier)

        return BatchRunConfig(
            epubPath: resolvedEPUBPath,
            outputPath: outputPath,
            targetHighlightCount: targetHighlightCount,
            language: language,
            style: style,
            providerConfigPath: providerConfigPath,
            overwritePolicy: overwritePolicy,
            profileDisplayName: normalizedProfileDisplayName,
            profileAvatarPath: (trimmedProfileAvatarPath?.isEmpty == true) ? nil : trimmedProfileAvatarPath,
            timeZoneIdentifier: normalizedTimeZoneIdentifier
        )
    }

    private static func normalizedProfileDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Reader" : trimmed
    }

    private static func normalizedTimeZoneIdentifier(_ value: String?) throws -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard TimeZone(identifier: trimmed) != nil else {
            throw BatchError.invalidOption("--timezone=\(value)")
        }
        return trimmed
    }
}
