import Foundation

public struct BatchOutputLayout: Equatable, Sendable {
    public let outputRoot: URL
    public let bookSlug: String
    public let bookDirectory: URL
    public let manifestFile: URL
    public let excerptsFile: URL
    public let candidatesStage1File: URL
    public let selectedStage2File: URL
    public let captionsFile: URL
    public let imagesDirectory: URL
    public let promptsDirectory: URL
    public let stage1PromptsDirectory: URL
    public let stage2PromptsDirectory: URL
    public let logsDirectory: URL
    public let runLogFile: URL
    public let metricsFile: URL

    public init(outputRootPath: String, sourceEPUBPath: String) {
        outputRoot = URL(fileURLWithPath: outputRootPath, isDirectory: true)
        bookSlug = BatchSlug.make(fromEPUBPath: sourceEPUBPath)
        bookDirectory = outputRoot.appendingPathComponent(bookSlug, isDirectory: true)
        manifestFile = bookDirectory.appendingPathComponent("manifest.json", isDirectory: false)
        excerptsFile = bookDirectory.appendingPathComponent("excerpts.jsonl", isDirectory: false)
        candidatesStage1File = bookDirectory.appendingPathComponent("candidates.stage1.jsonl", isDirectory: false)
        selectedStage2File = bookDirectory.appendingPathComponent("selected.stage2.json", isDirectory: false)
        captionsFile = bookDirectory.appendingPathComponent("captions.jsonl", isDirectory: false)
        imagesDirectory = bookDirectory.appendingPathComponent("images", isDirectory: true)
        promptsDirectory = bookDirectory.appendingPathComponent("prompts", isDirectory: true)
        stage1PromptsDirectory = promptsDirectory.appendingPathComponent("stage1", isDirectory: true)
        stage2PromptsDirectory = promptsDirectory.appendingPathComponent("stage2", isDirectory: true)
        logsDirectory = bookDirectory.appendingPathComponent("logs", isDirectory: true)
        runLogFile = logsDirectory.appendingPathComponent("run.log", isDirectory: false)
        metricsFile = logsDirectory.appendingPathComponent("metrics.json", isDirectory: false)
    }
}

public enum BatchSlug {
    public static func make(fromEPUBPath path: String) -> String {
        let rawName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let base = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !base.isEmpty else {
            return "book"
        }

        var pieces: [String] = []
        var current = ""

        for scalar in base.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                pieces.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            pieces.append(current)
        }

        let slug = pieces.joined(separator: "-")
        return slug.isEmpty ? "book" : slug
    }
}
