import BatchCore
import BatchModels
import BatchSupport
import Foundation

private struct BatchDirectoryBookSummary: Codable, Sendable {
    var index: Int
    var epubPath: String
    var bookSlug: String
    var status: String
    var phase: String?
    var outputDirectory: String?
    var manifestPath: String?
    var runLogPath: String?
    var durationMs: Int
    var error: String?

    private enum CodingKeys: String, CodingKey {
        case index
        case epubPath = "epub_path"
        case bookSlug = "book_slug"
        case status
        case phase
        case outputDirectory = "output_directory"
        case manifestPath = "manifest_path"
        case runLogPath = "run_log_path"
        case durationMs = "duration_ms"
        case error
    }
}

private struct BatchDirectorySummary: Codable, Sendable {
    var runId: String
    var generatedAt: String
    var inputDirectory: String
    var outputDirectory: String
    var totalBooks: Int
    var succeededBooks: Int
    var failedBooks: Int
    var results: [BatchDirectoryBookSummary]

    private enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case generatedAt = "generated_at"
        case inputDirectory = "input_directory"
        case outputDirectory = "output_directory"
        case totalBooks = "total_books"
        case succeededBooks = "succeeded_books"
        case failedBooks = "failed_books"
        case results
    }
}

private struct BatchDirectoryExecutionResult: Sendable {
    var summaryFilePath: String
    var totalBooks: Int
    var succeededBooks: Int
    var failedBooks: Int
    var failedItems: [BatchDirectoryBookSummary]
}

public struct BatchCommandRunner {
    private let stdout: @Sendable (String) -> Void
    private let stderr: @Sendable (String) -> Void
    private let pipeline: BatchPipeline
    private let fileManager: FileManager

    public init(
        stdout: @escaping @Sendable (String) -> Void = { print($0) },
        stderr: @escaping @Sendable (String) -> Void = { message in
            FileHandle.standardError.write(Data("\(message)\n".utf8))
        },
        pipeline: BatchPipeline = BatchPipeline(),
        fileManager: FileManager = .default
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.pipeline = pipeline
        self.fileManager = fileManager
    }

    public func run(arguments: [String]) -> Int {
        do {
            return try execute(arguments: arguments)
        } catch let error as BatchError {
            stderr("error: \(error.description)")
            return error.exitCode
        } catch {
            stderr("error: \(error.localizedDescription)")
            return 1
        }
    }

    private func execute(arguments: [String]) throws -> Int {
        guard let command = arguments.first else {
            stdout(Self.rootHelpText)
            return 0
        }

        switch command {
        case "-h", "--help", "help":
            stdout(Self.rootHelpText)
            return 0
        case "generate":
            let options = try GenerateCommandOptions.parse(arguments: Array(arguments.dropFirst()))
            if options.showHelp {
                stdout(Self.generateHelpText)
                return 0
            }

            if let inputDirectoryPath = options.inputDirectoryPath,
               !inputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                let batchResult = try runDirectoryGenerate(
                    options: options,
                    inputDirectoryPath: inputDirectoryPath
                )
                stdout("Batch generate completed.")
                stdout("Input directory: \(inputDirectoryPath)")
                stdout("Total books: \(batchResult.totalBooks)")
                stdout("Succeeded: \(batchResult.succeededBooks)")
                stdout("Failed: \(batchResult.failedBooks)")
                stdout("Summary file: \(batchResult.summaryFilePath)")

                if !batchResult.failedItems.isEmpty {
                    stdout("Failed books:")
                    for failedItem in batchResult.failedItems {
                        stdout("  [\(failedItem.index)] \(failedItem.epubPath)")
                        if let error = failedItem.error {
                            stdout("    error: \(error)")
                        }
                    }
                }

                return batchResult.failedBooks == 0 ? 0 : 1
            }

            let result = try pipeline.runGenerate(config: try options.toRunConfig())
            reportSingleGenerateResult(result)
            return 0
        case "captions":
            let options = try CaptionsCommandOptions.parse(arguments: Array(arguments.dropFirst()))
            if options.showHelp {
                stdout(Self.captionsHelpText)
                return 0
            }
            let manifest = try loadManifest(at: options.manifestPath)
            reportCaptionsStubResult(manifestPath: options.manifestPath, manifest: manifest)
            return 0
        case "publish":
            let options = try PublishCommandOptions.parse(arguments: Array(arguments.dropFirst()))
            if options.showHelp {
                stdout(Self.publishHelpText)
                return 0
            }
            let manifest = try loadManifest(at: options.manifestPath)
            reportPublishStubResult(manifestPath: options.manifestPath, manifest: manifest, channel: options.channel)
            return 0
        case "review":
            throw BatchError.unsupportedCommand(command)
        default:
            throw BatchError.invalidCommand(command)
        }
    }

    private func reportSingleGenerateResult(_ result: BatchGenerateResult) {
        stdout("Generate pipeline completed.")
        stdout("Phase: \(result.phase.rawValue)")
        stdout("Output directory: \(result.outputDirectory)")
        if let excerptsPath = result.excerptsPath {
            stdout("Excerpts file: \(excerptsPath)")
        }
        if let candidatesPath = result.candidatesPath {
            stdout("Stage1 candidates file: \(candidatesPath)")
        }
        if let selectedPath = result.selectedPath {
            stdout("Stage2 selected file: \(selectedPath)")
        }
        if let imagesDirectory = result.imagesDirectory {
            stdout("Images directory: \(imagesDirectory)")
        }
        if let manifestPath = result.manifestPath {
            stdout("Manifest file: \(manifestPath)")
        }
        stdout("Run log: \(result.runLogPath)")
    }

    private func reportCaptionsStubResult(manifestPath: String, manifest: BatchManifest) {
        let captionsOutputPath = resolveCaptionsOutputPath(manifest: manifest, manifestPath: manifestPath)
        stdout("Captions stub completed.")
        stdout("Manifest file: \(manifestPath)")
        stdout("Run ID: \(manifest.runId)")
        stdout("Planned captions output: \(captionsOutputPath)")
        stdout("Status: reserved (P7). No captions generation performed.")
    }

    private func reportPublishStubResult(
        manifestPath: String,
        manifest: BatchManifest,
        channel: String
    ) {
        stdout("Publish stub completed.")
        stdout("Manifest file: \(manifestPath)")
        stdout("Run ID: \(manifest.runId)")
        stdout("Channel: \(channel)")
        stdout("Status: reserved (P7). No external publish performed.")
    }

    private func runDirectoryGenerate(
        options: GenerateCommandOptions,
        inputDirectoryPath: String
    ) throws -> BatchDirectoryExecutionResult {
        let discoveredEPUBs = try discoverEPUBFiles(in: inputDirectoryPath)
        let outputDirectoryURL = URL(fileURLWithPath: options.outputPath, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        let pathsBySlug = Dictionary(grouping: discoveredEPUBs, by: { BatchSlug.make(fromEPUBPath: $0) })
        let conflictingSlugs = Set(
            pathsBySlug.compactMap { key, value in
                value.count > 1 ? key : nil
            }
        )

        var summaryRows: [BatchDirectoryBookSummary] = []
        summaryRows.reserveCapacity(discoveredEPUBs.count)
        var succeededBooks = 0
        var failedBooks = 0

        for (index, epubPath) in discoveredEPUBs.enumerated() {
            let order = index + 1
            let slug = BatchSlug.make(fromEPUBPath: epubPath)
            let start = Date()

            if conflictingSlugs.contains(slug) {
                failedBooks += 1
                let conflictNames = pathsBySlug[slug, default: []]
                    .map { URL(fileURLWithPath: $0).lastPathComponent }
                    .sorted()
                    .joined(separator: ", ")
                summaryRows.append(
                    BatchDirectoryBookSummary(
                        index: order,
                        epubPath: epubPath,
                        bookSlug: slug,
                        status: "failed",
                        phase: nil,
                        outputDirectory: nil,
                        manifestPath: nil,
                        runLogPath: nil,
                        durationMs: Int(Date().timeIntervalSince(start) * 1_000),
                        error: "Duplicate output slug '\(slug)' in batch input: \(conflictNames)."
                    )
                )
                continue
            }

            do {
                let runConfig = try options.toRunConfig(epubPath: epubPath)
                let result = try pipeline.runGenerate(config: runConfig)
                succeededBooks += 1
                summaryRows.append(
                    BatchDirectoryBookSummary(
                        index: order,
                        epubPath: epubPath,
                        bookSlug: slug,
                        status: "success",
                        phase: result.phase.rawValue,
                        outputDirectory: result.outputDirectory,
                        manifestPath: result.manifestPath,
                        runLogPath: result.runLogPath,
                        durationMs: Int(Date().timeIntervalSince(start) * 1_000),
                        error: nil
                    )
                )
            } catch let error as BatchError {
                failedBooks += 1
                summaryRows.append(
                    BatchDirectoryBookSummary(
                        index: order,
                        epubPath: epubPath,
                        bookSlug: slug,
                        status: "failed",
                        phase: nil,
                        outputDirectory: nil,
                        manifestPath: nil,
                        runLogPath: nil,
                        durationMs: Int(Date().timeIntervalSince(start) * 1_000),
                        error: error.description
                    )
                )
            } catch {
                failedBooks += 1
                summaryRows.append(
                    BatchDirectoryBookSummary(
                        index: order,
                        epubPath: epubPath,
                        bookSlug: slug,
                        status: "failed",
                        phase: nil,
                        outputDirectory: nil,
                        manifestPath: nil,
                        runLogPath: nil,
                        durationMs: Int(Date().timeIntervalSince(start) * 1_000),
                        error: error.localizedDescription
                    )
                )
            }
        }

        let summary = BatchDirectorySummary(
            runId: UUID().uuidString.lowercased(),
            generatedAt: Self.batchSummaryISO8601.string(from: Date()),
            inputDirectory: inputDirectoryPath,
            outputDirectory: outputDirectoryURL.path,
            totalBooks: discoveredEPUBs.count,
            succeededBooks: succeededBooks,
            failedBooks: failedBooks,
            results: summaryRows
        )

        let summaryFileURL = outputDirectoryURL.appendingPathComponent("batch.summary.json", isDirectory: false)
        try writeBatchSummary(summary, to: summaryFileURL)

        return BatchDirectoryExecutionResult(
            summaryFilePath: summaryFileURL.path,
            totalBooks: discoveredEPUBs.count,
            succeededBooks: succeededBooks,
            failedBooks: failedBooks,
            failedItems: summaryRows.filter { $0.status == "failed" }
        )
    }

    private func discoverEPUBFiles(in inputDirectoryPath: String) throws -> [String] {
        let trimmedPath = inputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw BatchError.missingRequiredOption("--input-dir")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: trimmedPath, isDirectory: &isDirectory) else {
            throw BatchError.fileNotFound(trimmedPath)
        }
        guard isDirectory.boolValue else {
            throw BatchError.invalidOption("--input-dir expects a directory path")
        }

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: trimmedPath, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw BatchError.ioFailure("Failed to enumerate input directory: \(trimmedPath)")
        }

        var epubFiles: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "epub" else {
                continue
            }
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == false {
                continue
            }
            epubFiles.append(fileURL.standardizedFileURL.path)
        }

        epubFiles.sort()

        if epubFiles.isEmpty {
            throw BatchError.runtime("No EPUB files found under input directory: \(trimmedPath).")
        }

        return epubFiles
    }

    private func writeBatchSummary(_ summary: BatchDirectorySummary, to fileURL: URL) throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(summary)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.ioFailure(
                "Failed writing batch summary at \(fileURL.path): \(error.localizedDescription)"
            )
        }
    }

    private func loadManifest(at manifestPath: String) throws -> BatchManifest {
        let trimmedPath = manifestPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw BatchError.missingRequiredOption("--manifest")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: trimmedPath, isDirectory: &isDirectory) else {
            throw BatchError.fileNotFound(trimmedPath)
        }
        guard !isDirectory.boolValue else {
            throw BatchError.invalidOption("--manifest expects a file path")
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: trimmedPath, isDirectory: false))
            return try JSONDecoder().decode(BatchManifest.self, from: data)
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.runtime("Failed to decode manifest at \(trimmedPath): \(error.localizedDescription)")
        }
    }

    private func resolveCaptionsOutputPath(manifest: BatchManifest, manifestPath: String) -> String {
        let defaultRelativePath = "captions.jsonl"
        let configuredPath = manifest.extensions?.captions.outputFile.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let relativePath = configuredPath.isEmpty ? defaultRelativePath : configuredPath

        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath, isDirectory: false).standardizedFileURL.path
        }

        let manifestURL = URL(fileURLWithPath: manifestPath, isDirectory: false)
        return manifestURL
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL.path
    }

    public static let rootHelpText = """
    OVERVIEW: LanRead batch automation CLI.

    USAGE: lanread-batch <command> [options]

    COMMANDS:
      generate    Run generation pipeline (P6 single EPUB or input directory batch mode).
      review      Reserved for future phase.
      captions    Reserved P7 stub for caption generation workflow.
      publish     Reserved P7 stub for social publish workflow.

    GLOBAL OPTIONS:
      -h, --help  Show help information.

    Use `lanread-batch <command> --help` for command details.
    """

    public static let generateHelpText = """
    OVERVIEW: Generate sharing artifacts from one EPUB or a directory of EPUB files.

    USAGE: lanread-batch generate (--epub <path> | --input-dir <path>) --output <path> [options]

    REQUIRED OPTIONS:
      --epub <path>             Input single EPUB file path.
      --input-dir <path>        Input directory for recursive EPUB scan.
      --output <path>           Output directory root.

    OPTIONAL OPTIONS:
      --highlights <count>      Target highlight count. Default: 20.
      --language <code>         Output language. Default: zh-Hans.
      --style <value>           Share card style: none, white, black. Default: white.
      --profile-name <name>     Share card user name. Default: Reader.
      --profile-avatar <path>   Avatar image path (png/jpg/webp) for note bubble.
      --timezone <IANA id>      Footer timestamp timezone, e.g. Asia/Shanghai.
      --provider-config <path>  AI provider config json path.
      --overwrite-policy <mode> Rerun strategy: resume or replace. Default: resume.
      -h, --help                Show help information.
    """

    public static let captionsHelpText = """
    OVERVIEW: Reserved command stub for future captions generation.

    USAGE: lanread-batch captions --manifest <path> [options]

    REQUIRED OPTIONS:
      --manifest <path>         Input manifest.json generated by `generate`.

    OPTIONAL OPTIONS:
      -h, --help                Show help information.

    NOTE:
      This command validates the manifest interface only in P7.
    """

    public static let publishHelpText = """
    OVERVIEW: Reserved command stub for future publish workflow.

    USAGE: lanread-batch publish --manifest <path> --channel <name> [options]

    REQUIRED OPTIONS:
      --manifest <path>         Input manifest.json generated by `generate`.
      --channel <name>          Target publish channel identifier.

    OPTIONAL OPTIONS:
      -h, --help                Show help information.

    NOTE:
      This command validates publish parameters only in P7.
    """

    private static let batchSummaryISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
