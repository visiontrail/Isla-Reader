import BatchAI
import BatchModels
import BatchRender
import BatchSupport
import Foundation

private struct BatchPipelineMetrics: Codable, Equatable, Sendable {
    var runId: String
    var overwritePolicy: String
    var parseDurationMs: Int
    var chunkCount: Int
    var reusedExcerpts: Bool
    var stage1DurationMs: Int
    var stage1RequestCount: Int
    var stage1SuccessCount: Int
    var stage1CandidateCount: Int
    var stage1WindowFailureCount: Int
    var reusedStage1Candidates: Bool
    var deduplicatedCandidateCount: Int
    var stage2InputCandidateCount: Int
    var stage2DurationMs: Int
    var stage2RequestCount: Int
    var stage2SuccessCount: Int
    var stage2SelectedCount: Int
    var stage2UsedFallback: Bool
    var reusedStage2Selection: Bool
    var renderDurationMs: Int
    var renderSuccessCount: Int
    var renderFailureCount: Int
    var renderReuseCount: Int
}

private struct Stage1PromptSummary: Codable, Equatable, Sendable {
    var excerptId: String
    var status: String
    var attemptCount: Int
    var rawCandidateCount: Int
    var keptCandidateCount: Int
    var droppedCandidateCount: Int
    var errorMessage: String?
    var responsePreview: String?
}

private struct Stage2PromptSummary: Codable, Equatable, Sendable {
    var status: String
    var attemptCount: Int
    var rawSelectionCount: Int
    var keptSelectionCount: Int
    var usedFallback: Bool
    var errorMessage: String?
    var responsePreview: String?
}

private struct BatchRenderSummary: Equatable, Sendable {
    var items: [SelectedHighlightItem]
    var successCount: Int
    var failureCount: Int
    var reusedCount: Int
}

public struct BatchPipeline {
    private let fileManager: FileManager
    private let logger: BatchLogger
    private let logWriter: BatchFileLogWriter
    private let jsonlWriter: BatchJSONLWriter
    private let jsonFileWriter: BatchJSONFileWriter
    private let aiClient: BatchAIClient
    private let epubParser: BatchEPubParser
    private let excerptChunker: BatchExcerptChunker
    private let shareCardRenderer: ShareCardRenderer

    public init(
        fileManager: FileManager = .default,
        logger: BatchLogger = BatchLogger(),
        logWriter: BatchFileLogWriter = BatchFileLogWriter(),
        jsonlWriter: BatchJSONLWriter = BatchJSONLWriter(),
        jsonFileWriter: BatchJSONFileWriter = BatchJSONFileWriter(),
        aiClient: BatchAIClient = BatchAIClient(),
        epubParser: BatchEPubParser = BatchEPubParser(),
        excerptChunker: BatchExcerptChunker = BatchExcerptChunker(),
        shareCardRenderer: ShareCardRenderer = ShareCardRenderer()
    ) {
        self.fileManager = fileManager
        self.logger = logger
        self.logWriter = logWriter
        self.jsonlWriter = jsonlWriter
        self.jsonFileWriter = jsonFileWriter
        self.aiClient = aiClient
        self.epubParser = epubParser
        self.excerptChunker = excerptChunker
        self.shareCardRenderer = shareCardRenderer
    }

    public func runGenerate(config: BatchRunConfig) throws -> BatchGenerateResult {
        guard fileManager.fileExists(atPath: config.epubPath) else {
            throw BatchError.fileNotFound(config.epubPath)
        }

        let providerConfig = try aiClient.loadProviderConfiguration(path: config.providerConfigPath)
        let layout = BatchOutputLayout(outputRootPath: config.outputPath, sourceEPUBPath: config.epubPath)
        let runID = UUID().uuidString.lowercased()
        let generatedAt = Date()

        try prepareOutputDirectories(layout: layout, overwritePolicy: config.overwritePolicy)
        try logWriter.prepareLogFile(at: layout.runLogFile)
        let startLog = BatchLogger.render(
            level: .info,
            message: "phase=P5 event=generate_start run_id=\(runID) overwrite_policy=\(config.overwritePolicy.rawValue)"
        )
        logger.writeRaw(startLog)
        try logWriter.append(startLog, to: layout.runLogFile)

        let parseStart = Date()
        let parsedBook = try epubParser.parseBook(at: config.epubPath)
        let parseDurationMs = Int(Date().timeIntervalSince(parseStart) * 1_000)

        var reusedExcerpts = false
        var excerpts: [BookExcerpt] = []
        if config.overwritePolicy == .resume {
            do {
                if let cachedExcerpts = try loadJSONLIfExists(BookExcerpt.self, from: layout.excerptsFile),
                   !cachedExcerpts.isEmpty
                {
                    excerpts = cachedExcerpts
                    reusedExcerpts = true
                    let cacheLog = BatchLogger.render(
                        level: .info,
                        message: "phase=P5 event=cache_reuse file=excerpts.jsonl count=\(cachedExcerpts.count)"
                    )
                    logger.writeRaw(cacheLog)
                    try logWriter.append(cacheLog, to: layout.runLogFile)
                }
            } catch {
                let cacheLog = BatchLogger.render(
                    level: .warning,
                    message: "phase=P5 event=cache_invalid file=excerpts.jsonl error=\(error.localizedDescription)"
                )
                logger.writeRaw(cacheLog)
                try logWriter.append(cacheLog, to: layout.runLogFile)
            }
        }

        if excerpts.isEmpty {
            excerpts = excerptChunker.buildExcerpts(from: parsedBook, fallbackLanguage: config.language)
            if excerpts.isEmpty {
                throw BatchError.runtime("Chunking produced zero excerpts. Please inspect EPUB content quality.")
            }
            try jsonlWriter.writeRows(excerpts, to: layout.excerptsFile)
        }

        var stage1RequestCount = 0
        var stage1SuccessCount = 0
        var stage1WindowFailureCount = 0
        var allStage1Candidates: [Stage1Candidate] = []
        var reusedStage1Candidates = false
        var stage1DurationMs = 0

        if config.overwritePolicy == .resume {
            do {
                if let cachedCandidates = try loadJSONLIfExists(Stage1Candidate.self, from: layout.candidatesStage1File),
                   !cachedCandidates.isEmpty
                {
                    allStage1Candidates = cachedCandidates
                    reusedStage1Candidates = true
                    let cacheLog = BatchLogger.render(
                        level: .info,
                        message: "phase=P5 event=cache_reuse file=candidates.stage1.jsonl count=\(cachedCandidates.count)"
                    )
                    logger.writeRaw(cacheLog)
                    try logWriter.append(cacheLog, to: layout.runLogFile)
                }
            } catch {
                let cacheLog = BatchLogger.render(
                    level: .warning,
                    message: "phase=P5 event=cache_invalid file=candidates.stage1.jsonl error=\(error.localizedDescription)"
                )
                logger.writeRaw(cacheLog)
                try logWriter.append(cacheLog, to: layout.runLogFile)
            }
        }

        if !reusedStage1Candidates {
            let stage1Start = Date()
            for excerpt in excerpts {
                stage1RequestCount += 1
                let stage1Request = BatchStage1Request(
                    bookMetadata: parsedBook.metadata,
                    excerpt: excerpt,
                    outputLanguage: config.language
                )
                let prompt = aiClient.makeStage1Prompt(request: stage1Request)
                let promptFile = layout.stage1PromptsDirectory.appendingPathComponent("\(excerpt.id).prompt.txt")
                try writeString(prompt, to: promptFile)

                let summaryFile = layout.stage1PromptsDirectory.appendingPathComponent("\(excerpt.id).response.json")
                do {
                    let stage1Result = try aiClient.stage1ExtractCandidates(
                        request: stage1Request,
                        provider: providerConfig
                    )

                    let mapped = stage1Result.candidates.enumerated().compactMap { index, row in
                        toStage1Candidate(
                            row: row,
                            excerpt: excerpt,
                            candidateIndex: index + 1
                        )
                    }
                    let droppedCount = stage1Result.candidates.count - mapped.count
                    stage1SuccessCount += 1
                    allStage1Candidates.append(contentsOf: mapped)

                    let summary = Stage1PromptSummary(
                        excerptId: excerpt.id,
                        status: "success",
                        attemptCount: stage1Result.attemptCount,
                        rawCandidateCount: stage1Result.candidates.count,
                        keptCandidateCount: mapped.count,
                        droppedCandidateCount: droppedCount,
                        errorMessage: nil,
                        responsePreview: shorten(stage1Result.responseText, maxLength: 1_200)
                    )
                    try jsonFileWriter.writeObject(summary, to: summaryFile)

                    let successLog = BatchLogger.render(
                        level: .info,
                        message: "phase=P2 event=stage1_window_success excerpt.id=\(excerpt.id) attempts=\(stage1Result.attemptCount) kept=\(mapped.count) dropped=\(droppedCount)"
                    )
                    logger.writeRaw(successLog)
                    try logWriter.append(successLog, to: layout.runLogFile)
                } catch {
                    stage1WindowFailureCount += 1
                    let summary = Stage1PromptSummary(
                        excerptId: excerpt.id,
                        status: "failed",
                        attemptCount: providerConfig.maxRetryCount + 1,
                        rawCandidateCount: 0,
                        keptCandidateCount: 0,
                        droppedCandidateCount: 0,
                        errorMessage: error.localizedDescription,
                        responsePreview: nil
                    )
                    try jsonFileWriter.writeObject(summary, to: summaryFile)

                    let failedLog = BatchLogger.render(
                        level: .warning,
                        message: "phase=P2 event=stage1_window_failed excerpt.id=\(excerpt.id) error=\(error.localizedDescription)"
                    )
                    logger.writeRaw(failedLog)
                    try logWriter.append(failedLog, to: layout.runLogFile)
                }
            }
            stage1DurationMs = Int(Date().timeIntervalSince(stage1Start) * 1_000)
            try jsonlWriter.writeRows(allStage1Candidates, to: layout.candidatesStage1File)
        }

        let deduplicatedCandidates = deduplicateCandidates(allStage1Candidates)
        let stage2InputCandidates = buildStage2InputCandidates(
            from: deduplicatedCandidates,
            targetCount: config.targetHighlightCount
        )

        var stage2RequestCount = 0
        var stage2SuccessCount = 0
        var stage2UsedFallback = false
        var stage2DurationMs = 0
        var reusedStage2Selection = false
        var stage2Mode = "ai"
        var stage2TargetCount = config.targetHighlightCount
        var outputStage1CandidateCount = allStage1Candidates.count
        var outputDeduplicatedCandidateCount = deduplicatedCandidates.count
        var outputPrescreenCandidateCount = stage2InputCandidates.count

        let stage2PromptFile = layout.stage2PromptsDirectory.appendingPathComponent("selection.prompt.txt")
        let stage2SummaryFile = layout.stage2PromptsDirectory.appendingPathComponent("selection.response.json")

        var selectedItems: [SelectedHighlightItem] = []
        if config.overwritePolicy == .resume {
            do {
                if let cachedSelection = try loadJSONObjectIfExists(Stage2SelectionOutput.self, from: layout.selectedStage2File) {
                    selectedItems = cachedSelection.selected
                    stage2Mode = cachedSelection.mode
                    stage2TargetCount = cachedSelection.targetCount
                    outputStage1CandidateCount = cachedSelection.stage1CandidateCount
                    outputDeduplicatedCandidateCount = cachedSelection.deduplicatedCandidateCount
                    outputPrescreenCandidateCount = cachedSelection.prescreenCandidateCount
                    stage2UsedFallback = cachedSelection.mode != "ai"
                    reusedStage2Selection = true

                    let cacheLog = BatchLogger.render(
                        level: .info,
                        message: "phase=P5 event=cache_reuse file=selected.stage2.json count=\(cachedSelection.selected.count)"
                    )
                    logger.writeRaw(cacheLog)
                    try logWriter.append(cacheLog, to: layout.runLogFile)
                }
            } catch {
                let cacheLog = BatchLogger.render(
                    level: .warning,
                    message: "phase=P5 event=cache_invalid file=selected.stage2.json error=\(error.localizedDescription)"
                )
                logger.writeRaw(cacheLog)
                try logWriter.append(cacheLog, to: layout.runLogFile)
            }
        }

        if !reusedStage2Selection {
            let fallbackPool = deduplicatedCandidates.isEmpty ? allStage1Candidates : deduplicatedCandidates
            let fallbackSelected = makeLocalFallbackSelection(
                from: fallbackPool,
                targetCount: config.targetHighlightCount,
                reason: "local_fallback"
            )

            let stage2Start = Date()
            if stage2InputCandidates.isEmpty {
                stage2UsedFallback = true
                stage2Mode = "local_fallback"
                selectedItems = fallbackSelected

                let summary = Stage2PromptSummary(
                    status: "skipped_no_input",
                    attemptCount: 0,
                    rawSelectionCount: 0,
                    keptSelectionCount: selectedItems.count,
                    usedFallback: true,
                    errorMessage: "No candidates available after local dedup + prescreen.",
                    responsePreview: nil
                )
                try jsonFileWriter.writeObject(summary, to: stage2SummaryFile)
            } else {
                let stage2Request = BatchStage2Request(
                    bookMetadata: parsedBook.metadata,
                    candidates: stage2InputCandidates,
                    outputLanguage: config.language,
                    targetCount: config.targetHighlightCount
                )
                let prompt = aiClient.makeStage2Prompt(request: stage2Request)
                try writeString(prompt, to: stage2PromptFile)

                stage2RequestCount = 1
                do {
                    let stage2Result = try aiClient.stage2SelectCandidates(
                        request: stage2Request,
                        provider: providerConfig
                    )
                    stage2SuccessCount = 1
                    let stage2ResponsePreview = shorten(stage2Result.responseText, maxLength: 1_200)

                    let mapped = mapStage2Selections(
                        stage2Result.selections,
                        from: stage2InputCandidates,
                        targetCount: config.targetHighlightCount
                    )
                    let merged = mergeWithFallback(
                        selected: mapped,
                        fallbackPool: stage2InputCandidates,
                        targetCount: config.targetHighlightCount
                    )

                    if merged.isEmpty {
                        stage2UsedFallback = true
                        stage2Mode = "local_fallback"
                        selectedItems = fallbackSelected
                    } else {
                        stage2Mode = "ai"
                        selectedItems = merged
                    }

                    let summary = Stage2PromptSummary(
                        status: "success",
                        attemptCount: stage2Result.attemptCount,
                        rawSelectionCount: stage2Result.selections.count,
                        keptSelectionCount: selectedItems.count,
                        usedFallback: stage2UsedFallback,
                        errorMessage: nil,
                        responsePreview: stage2ResponsePreview
                    )
                    try jsonFileWriter.writeObject(summary, to: stage2SummaryFile)

                    let successLog = BatchLogger.render(
                        level: .info,
                        message: "phase=P3 event=stage2_success attempts=\(stage2Result.attemptCount) selected=\(selectedItems.count) fallback=\(stage2UsedFallback)"
                    )
                    logger.writeRaw(successLog)
                    try logWriter.append(successLog, to: layout.runLogFile)
                } catch {
                    stage2UsedFallback = true
                    stage2Mode = "local_fallback"
                    selectedItems = fallbackSelected

                    let summary = Stage2PromptSummary(
                        status: "failed",
                        attemptCount: providerConfig.maxRetryCount + 1,
                        rawSelectionCount: 0,
                        keptSelectionCount: selectedItems.count,
                        usedFallback: true,
                        errorMessage: error.localizedDescription,
                        responsePreview: nil
                    )
                    try jsonFileWriter.writeObject(summary, to: stage2SummaryFile)

                    let failedLog = BatchLogger.render(
                        level: .warning,
                        message: "phase=P3 event=stage2_failed error=\(error.localizedDescription) fallback=true selected=\(selectedItems.count)"
                    )
                    logger.writeRaw(failedLog)
                    try logWriter.append(failedLog, to: layout.runLogFile)
                }
            }
            stage2DurationMs = Int(Date().timeIntervalSince(stage2Start) * 1_000)
        }

        let profileAvatarData = try loadOptionalImageData(
            path: config.profileAvatarPath,
            optionName: "--profile-avatar"
        )

        let renderStart = Date()
        let renderResult = try renderSelectedItems(
            selectedItems,
            bookMetadata: parsedBook.metadata,
            outputDirectory: layout.bookDirectory,
            style: config.style,
            profileDisplayName: config.profileDisplayName,
            profileAvatarData: profileAvatarData,
            imagesDirectory: layout.imagesDirectory,
            runLogFile: layout.runLogFile,
            reuseExistingImages: config.overwritePolicy == .resume,
            generatedAt: generatedAt,
            timeZoneIdentifier: config.timeZoneIdentifier
        )
        let renderDurationMs = Int(Date().timeIntervalSince(renderStart) * 1_000)
        selectedItems = renderResult.items

        let selectedOutput = Stage2SelectionOutput(
            mode: stage2Mode,
            targetCount: stage2TargetCount,
            stage1CandidateCount: outputStage1CandidateCount,
            deduplicatedCandidateCount: outputDeduplicatedCandidateCount,
            prescreenCandidateCount: outputPrescreenCandidateCount,
            selected: selectedItems
        )
        try jsonFileWriter.writeObject(selectedOutput, to: layout.selectedStage2File)

        let excerptByID = Dictionary(uniqueKeysWithValues: excerpts.map { ($0.id, $0) })
        let manifest = buildManifest(
            runID: runID,
            generatedAt: generatedAt,
            config: config,
            provider: providerConfig,
            sourceFilePath: config.epubPath,
            book: parsedBook,
            excerpts: excerpts,
            excerptByID: excerptByID,
            selectedOutput: selectedOutput,
            stage1CandidateCount: allStage1Candidates.count,
            deduplicatedCandidateCount: deduplicatedCandidates.count,
            stage2InputCandidateCount: stage2InputCandidates.count,
            renderSummary: renderResult
        )
        try jsonFileWriter.writeObject(manifest, to: layout.manifestFile)

        let metrics = BatchPipelineMetrics(
            runId: runID,
            overwritePolicy: config.overwritePolicy.rawValue,
            parseDurationMs: parseDurationMs,
            chunkCount: excerpts.count,
            reusedExcerpts: reusedExcerpts,
            stage1DurationMs: stage1DurationMs,
            stage1RequestCount: stage1RequestCount,
            stage1SuccessCount: stage1SuccessCount,
            stage1CandidateCount: allStage1Candidates.count,
            stage1WindowFailureCount: stage1WindowFailureCount,
            reusedStage1Candidates: reusedStage1Candidates,
            deduplicatedCandidateCount: deduplicatedCandidates.count,
            stage2InputCandidateCount: stage2InputCandidates.count,
            stage2DurationMs: stage2DurationMs,
            stage2RequestCount: stage2RequestCount,
            stage2SuccessCount: stage2SuccessCount,
            stage2SelectedCount: selectedItems.count,
            stage2UsedFallback: stage2UsedFallback,
            reusedStage2Selection: reusedStage2Selection,
            renderDurationMs: renderDurationMs,
            renderSuccessCount: renderResult.successCount,
            renderFailureCount: renderResult.failureCount,
            renderReuseCount: renderResult.reusedCount
        )
        try jsonFileWriter.writeObject(metrics, to: layout.metricsFile)

        let logMessages = [
            "phase=P5 event=generate_summary run_id=\(runID)",
            "source.epub=\(config.epubPath)",
            "book.title=\(parsedBook.metadata.title)",
            "book.author=\(parsedBook.metadata.author ?? "unknown")",
            "book.language=\(parsedBook.metadata.language ?? "unknown")",
            "output.book_dir=\(layout.bookDirectory.path)",
            "output.manifest=\(layout.manifestFile.path)",
            "output.excerpts=\(layout.excerptsFile.path)",
            "output.stage1_candidates=\(layout.candidatesStage1File.path)",
            "output.selected_stage2=\(layout.selectedStage2File.path)",
            "output.captions=\(layout.captionsFile.path)",
            "output.images_dir=\(layout.imagesDirectory.path)",
            "output.stage1_prompts=\(layout.stage1PromptsDirectory.path)",
            "output.stage2_prompts=\(layout.stage2PromptsDirectory.path)",
            "output.logs_dir=\(layout.logsDirectory.path)",
            "output.metrics=\(layout.metricsFile.path)",
            "config.highlights=\(config.targetHighlightCount)",
            "config.language=\(config.language)",
            "config.style=\(config.style.rawValue)",
            "config.profile_display_name=\(config.profileDisplayName)",
            "config.profile_avatar=\(config.profileAvatarPath ?? "none")",
            "config.timezone=\(config.timeZoneIdentifier ?? "system")",
            "config.overwrite_policy=\(config.overwritePolicy.rawValue)",
            "config.ai.endpoint=\(providerConfig.endpoint)",
            "config.ai.model=\(providerConfig.model)",
            "config.ai.key=\(masked(providerConfig.apiKey))",
            "stats.chapters=\(parsedBook.chapters.count)",
            "stats.excerpts=\(excerpts.count)",
            "stats.stage1_candidates=\(allStage1Candidates.count)",
            "stats.deduplicated_candidates=\(deduplicatedCandidates.count)",
            "stats.stage2_input_candidates=\(stage2InputCandidates.count)",
            "stats.stage2_selected=\(selectedItems.count)",
            "metrics.parse_duration_ms=\(parseDurationMs)",
            "metrics.reused_excerpts=\(reusedExcerpts)",
            "metrics.stage1_duration_ms=\(stage1DurationMs)",
            "metrics.stage1_request_count=\(stage1RequestCount)",
            "metrics.stage1_success_count=\(stage1SuccessCount)",
            "metrics.reused_stage1_candidates=\(reusedStage1Candidates)",
            "metrics.stage2_duration_ms=\(stage2DurationMs)",
            "metrics.stage2_request_count=\(stage2RequestCount)",
            "metrics.stage2_success_count=\(stage2SuccessCount)",
            "metrics.stage2_used_fallback=\(stage2UsedFallback)",
            "metrics.reused_stage2_selection=\(reusedStage2Selection)",
            "metrics.render_duration_ms=\(renderDurationMs)",
            "metrics.render_success_count=\(renderResult.successCount)",
            "metrics.render_failure_count=\(renderResult.failureCount)",
            "metrics.render_reuse_count=\(renderResult.reusedCount)",
            "status=p5_completed note=manifest_and_rerun_ready"
        ]

        for message in logMessages {
            let line = BatchLogger.render(level: .info, message: message)
            logger.writeRaw(line)
            try logWriter.append(line, to: layout.runLogFile)
        }

        return BatchGenerateResult(
            phase: .p5ManifestAndRerun,
            outputDirectory: layout.bookDirectory.path,
            runLogPath: layout.runLogFile.path,
            excerptsPath: layout.excerptsFile.path,
            candidatesPath: layout.candidatesStage1File.path,
            selectedPath: layout.selectedStage2File.path,
            imagesDirectory: layout.imagesDirectory.path,
            manifestPath: layout.manifestFile.path
        )
    }

    private func prepareOutputDirectories(layout: BatchOutputLayout, overwritePolicy: BatchRunConfig.OverwritePolicy) throws {
        if overwritePolicy == .replace, fileManager.fileExists(atPath: layout.bookDirectory.path) {
            do {
                try fileManager.removeItem(at: layout.bookDirectory)
            } catch {
                throw BatchError.ioFailure("Failed removing output directory \(layout.bookDirectory.path): \(error.localizedDescription)")
            }
        }

        try fileManager.createDirectory(at: layout.bookDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.imagesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.stage1PromptsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.stage2PromptsDirectory, withIntermediateDirectories: true)
    }

    private func loadJSONLIfExists<T: Decodable>(_ type: T.Type, from fileURL: URL) throws -> [T]? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        return try lines.map { line in
            guard let lineData = line.data(using: .utf8) else {
                throw BatchError.runtime("Invalid UTF-8 line in \(fileURL.path).")
            }
            return try decoder.decode(T.self, from: lineData)
        }
    }

    private func loadJSONObjectIfExists<T: Decodable>(_ type: T.Type, from fileURL: URL) throws -> T? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func buildManifest(
        runID: String,
        generatedAt: Date,
        config: BatchRunConfig,
        provider: BatchAIProviderConfiguration,
        sourceFilePath: String,
        book: BatchBook,
        excerpts: [BookExcerpt],
        excerptByID: [String: BookExcerpt],
        selectedOutput: Stage2SelectionOutput,
        stage1CandidateCount: Int,
        deduplicatedCandidateCount: Int,
        stage2InputCandidateCount: Int,
        renderSummary: BatchRenderSummary
    ) -> BatchManifest {
        let items = selectedOutput.selected.map { item in
            BatchManifestItem(
                id: item.id,
                rank: item.rank,
                chapterTitle: item.chapterTitle,
                chapterOrder: item.chapterOrder,
                sourceExcerpt: sourceExcerpt(for: item, excerptByID: excerptByID),
                highlightText: item.highlightText,
                noteText: item.noteText.trimmingCharacters(in: .whitespacesAndNewlines),
                imagePath: item.imagePath,
                score: item.stage2Score ?? item.candidateScore,
                tags: item.tags,
                sourceLocator: BatchManifestSourceLocator(
                    chapterOrder: item.chapterOrder,
                    excerptIndex: item.windowIndex,
                    excerptHash: item.excerptHash
                ),
                candidateId: item.candidateId,
                excerptId: item.excerptId,
                selectionReason: item.selectionReason,
                renderError: item.renderError
            )
        }

        return BatchManifest(
            runId: runID,
            generatedAt: iso8601Timestamp(generatedAt),
            sourceFile: sourceFilePath,
            book: BatchManifestBook(
                title: book.metadata.title,
                author: book.metadata.author,
                language: book.metadata.language
            ),
            config: BatchManifestConfig(
                highlights: config.targetHighlightCount,
                language: config.language,
                style: config.style.rawValue,
                model: provider.model,
                overwritePolicy: config.overwritePolicy.rawValue,
                profileDisplayName: config.profileDisplayName,
                profileAvatarPath: config.profileAvatarPath,
                timeZoneIdentifier: config.timeZoneIdentifier
            ),
            stats: BatchManifestStats(
                chapters: book.chapters.count,
                windows: excerpts.count,
                stage1Candidates: stage1CandidateCount,
                deduplicatedCandidates: deduplicatedCandidateCount,
                stage2InputCandidates: stage2InputCandidateCount,
                finalItems: items.count,
                renderSuccessCount: renderSummary.successCount,
                renderFailureCount: renderSummary.failureCount
            ),
            items: items,
            extensions: .reserved
        )
    }

    private func sourceExcerpt(for item: SelectedHighlightItem, excerptByID: [String: BookExcerpt]) -> String {
        guard let excerpt = excerptByID[item.excerptId] else {
            return item.highlightText
        }
        let text = excerpt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return item.highlightText
        }

        let highlight = item.highlightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !highlight.isEmpty else {
            return shorten(text, maxLength: 320)
        }

        if let range = text.range(of: highlight) {
            let snippetStart = text.index(range.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
            let snippetEnd = text.index(range.upperBound, offsetBy: 120, limitedBy: text.endIndex) ?? text.endIndex
            return String(text[snippetStart..<snippetEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return shorten(text, maxLength: 320)
    }

    private func iso8601Timestamp(_ date: Date) -> String {
        Self.manifestISO8601.string(from: date)
    }

    private func toStage1Candidate(
        row: BatchStage1CandidateDraft,
        excerpt: BookExcerpt,
        candidateIndex: Int
    ) -> Stage1Candidate? {
        guard isHighlightCopiedFromExcerpt(row.highlightText, excerptText: excerpt.text) else {
            return nil
        }

        return Stage1Candidate(
            id: "\(excerpt.id)-c\(String(format: "%02d", candidateIndex))",
            excerptId: excerpt.id,
            chapterOrder: excerpt.chapterOrder,
            chapterTitle: excerpt.chapterTitle,
            windowIndex: excerpt.windowIndex,
            excerptHash: excerpt.textHash,
            highlightText: row.highlightText,
            noteText: row.noteText,
            tags: row.tags,
            score: row.score,
            reason: row.reason
        )
    }

    private func deduplicateCandidates(_ candidates: [Stage1Candidate]) -> [Stage1Candidate] {
        guard !candidates.isEmpty else {
            return []
        }

        var bestByKey: [String: Stage1Candidate] = [:]
        bestByKey.reserveCapacity(candidates.count)

        for candidate in candidates {
            let key = deduplicationKey(for: candidate)
            guard let existing = bestByKey[key] else {
                bestByKey[key] = candidate
                continue
            }
            if shouldReplace(existing: existing, with: candidate) {
                bestByKey[key] = candidate
            }
        }

        return bestByKey.values.sorted(by: compareForRanking(_:_:))
    }

    private func deduplicationKey(for candidate: Stage1Candidate) -> String {
        let normalizedHighlight = normalizeForDedup(candidate.highlightText)
        if !normalizedHighlight.isEmpty {
            return normalizedHighlight
        }
        return "\(candidate.excerptHash)-\(candidate.id)"
    }

    private func shouldReplace(existing: Stage1Candidate, with candidate: Stage1Candidate) -> Bool {
        if candidate.score != existing.score {
            return candidate.score > existing.score
        }
        if candidate.highlightText.count != existing.highlightText.count {
            return candidate.highlightText.count > existing.highlightText.count
        }
        return candidate.id < existing.id
    }

    private func buildStage2InputCandidates(
        from candidates: [Stage1Candidate],
        targetCount: Int
    ) -> [Stage1Candidate] {
        let valid = candidates.filter { isReasonableHighlightLength($0.highlightText) }
        guard !valid.isEmpty else {
            return []
        }

        let ranked = valid.sorted(by: compareForRanking(_:_:))
        let cap = min(max(targetCount * 6, 40), 160)
        let perChapterCap = max(2, targetCount / 2)
        return selectDiversifiedCandidates(
            from: ranked,
            targetCount: cap,
            maxPerChapter: perChapterCap
        )
    }

    private func makeLocalFallbackSelection(
        from candidates: [Stage1Candidate],
        targetCount: Int,
        reason: String
    ) -> [SelectedHighlightItem] {
        guard !candidates.isEmpty, targetCount > 0 else {
            return []
        }
        let ranked = candidates
            .filter { isReasonableHighlightLength($0.highlightText) }
            .sorted(by: compareForRanking(_:_:))
        let diversified = selectDiversifiedCandidates(
            from: ranked,
            targetCount: targetCount,
            maxPerChapter: max(2, targetCount / 2)
        )

        return diversified.enumerated().map { index, candidate in
            SelectedHighlightItem(
                id: "item-\(String(format: "%03d", index + 1))",
                rank: index + 1,
                candidateId: candidate.id,
                excerptId: candidate.excerptId,
                chapterOrder: candidate.chapterOrder,
                chapterTitle: candidate.chapterTitle,
                windowIndex: candidate.windowIndex,
                excerptHash: candidate.excerptHash,
                highlightText: candidate.highlightText,
                noteText: candidate.noteText,
                tags: candidate.tags,
                candidateScore: candidate.score,
                stage2Score: nil,
                selectionReason: reason
            )
        }
    }

    private func mapStage2Selections(
        _ selections: [BatchStage2SelectionDraft],
        from candidates: [Stage1Candidate],
        targetCount: Int
    ) -> [SelectedHighlightItem] {
        guard !selections.isEmpty, !candidates.isEmpty else {
            return []
        }

        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let sortedSelections = selections.enumerated().sorted { lhs, rhs in
            let leftRank = lhs.element.rank ?? (lhs.offset + 1)
            let rightRank = rhs.element.rank ?? (rhs.offset + 1)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return lhs.offset < rhs.offset
        }

        var selected: [SelectedHighlightItem] = []
        var seenIDs: Set<String> = []

        for entry in sortedSelections {
            let draft = entry.element
            guard let candidate = candidateByID[draft.candidateId] else { continue }
            if seenIDs.contains(candidate.id) {
                continue
            }
            seenIDs.insert(candidate.id)

            let rank = selected.count + 1
            selected.append(
                SelectedHighlightItem(
                    id: "item-\(String(format: "%03d", rank))",
                    rank: rank,
                    candidateId: candidate.id,
                    excerptId: candidate.excerptId,
                    chapterOrder: candidate.chapterOrder,
                    chapterTitle: candidate.chapterTitle,
                    windowIndex: candidate.windowIndex,
                    excerptHash: candidate.excerptHash,
                    highlightText: candidate.highlightText,
                    noteText: candidate.noteText,
                    tags: candidate.tags,
                    candidateScore: candidate.score,
                    stage2Score: draft.score,
                    selectionReason: draft.reason.isEmpty ? "selected_by_stage2" : draft.reason
                )
            )

            if selected.count >= targetCount {
                break
            }
        }

        return selected
    }

    private func mergeWithFallback(
        selected: [SelectedHighlightItem],
        fallbackPool: [Stage1Candidate],
        targetCount: Int
    ) -> [SelectedHighlightItem] {
        guard targetCount > 0 else {
            return []
        }

        var merged = Array(selected.prefix(targetCount))
        if merged.count >= targetCount {
            return reindexSelectedItems(merged)
        }

        let selectedIDs = Set(merged.map(\.candidateId))
        let fallbackCandidates = fallbackPool
            .filter { !selectedIDs.contains($0.id) }
            .filter { isReasonableHighlightLength($0.highlightText) }
            .sorted(by: compareForRanking(_:_:))

        for candidate in fallbackCandidates {
            if merged.count >= targetCount {
                break
            }
            merged.append(
                SelectedHighlightItem(
                    id: "",
                    rank: 0,
                    candidateId: candidate.id,
                    excerptId: candidate.excerptId,
                    chapterOrder: candidate.chapterOrder,
                    chapterTitle: candidate.chapterTitle,
                    windowIndex: candidate.windowIndex,
                    excerptHash: candidate.excerptHash,
                    highlightText: candidate.highlightText,
                    noteText: candidate.noteText,
                    tags: candidate.tags,
                    candidateScore: candidate.score,
                    stage2Score: nil,
                    selectionReason: "fallback_fill"
                )
            )
        }

        return reindexSelectedItems(merged)
    }

    private func reindexSelectedItems(_ items: [SelectedHighlightItem]) -> [SelectedHighlightItem] {
        items.enumerated().map { index, item in
            var updated = item
            let rank = index + 1
            updated.rank = rank
            updated.id = "item-\(String(format: "%03d", rank))"
            return updated
        }
    }

    private func renderSelectedItems(
        _ items: [SelectedHighlightItem],
        bookMetadata: BatchBookMetadata,
        outputDirectory: URL,
        style: ShareCardStyle,
        profileDisplayName: String,
        profileAvatarData: Data?,
        imagesDirectory: URL,
        runLogFile: URL,
        reuseExistingImages: Bool,
        generatedAt: Date,
        timeZoneIdentifier: String?
    ) throws -> BatchRenderSummary {
        guard !items.isEmpty else {
            return BatchRenderSummary(items: [], successCount: 0, failureCount: 0, reusedCount: 0)
        }

        var renderedItems: [SelectedHighlightItem] = []
        renderedItems.reserveCapacity(items.count)

        var successCount = 0
        var failureCount = 0
        var reusedCount = 0
        let footerTitle = "Shared from LanRead"
        let footerSubtitle = bookMetadata.author ?? bookMetadata.title

        for item in items {
            var updated = item
            let imageFileName: String
            if let relativeImagePath = updated.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !relativeImagePath.isEmpty
            {
                imageFileName = URL(fileURLWithPath: relativeImagePath).lastPathComponent
            } else {
                imageFileName = "\(String(format: "%03d", item.rank)).png"
            }

            let imageRelativePath = "images/\(imageFileName)"
            let imageURL = imagesDirectory.appendingPathComponent(imageFileName, isDirectory: false)

            if reuseExistingImages {
                let existingImagePath = outputDirectory
                    .appendingPathComponent(imageRelativePath, isDirectory: false)
                    .path
                if fileManager.fileExists(atPath: existingImagePath) {
                    updated.imagePath = imageRelativePath
                    updated.renderError = nil
                    successCount += 1
                    reusedCount += 1

                    let reusedLog = BatchLogger.render(
                        level: .info,
                        message: "phase=P5 event=render_item_reused item.id=\(item.id) image=\(imageRelativePath)"
                    )
                    logger.writeRaw(reusedLog)
                    try logWriter.append(reusedLog, to: runLogFile)
                    renderedItems.append(updated)
                    continue
                }
            }

            do {
                let payload = ShareCardRenderPayload(
                    highlightText: item.highlightText,
                    noteText: normalizedNoteText(item.noteText),
                    profileDisplayName: profileDisplayName,
                    profileAvatarData: profileAvatarData,
                    bookTitle: bookMetadata.title,
                    chapterTitle: item.chapterTitle,
                    footerText: footerTitle,
                    footerSubtitleText: footerSubtitle,
                    coverImageData: bookMetadata.coverImageData,
                    generatedAt: generatedAt,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                try shareCardRenderer.render(payload: payload, style: style, to: imageURL)
                updated.imagePath = imageRelativePath
                updated.renderError = nil
                successCount += 1

                let successLog = BatchLogger.render(
                    level: .info,
                    message: "phase=P4 event=render_item_success item.id=\(item.id) image=\(updated.imagePath ?? imageRelativePath)"
                )
                logger.writeRaw(successLog)
                try logWriter.append(successLog, to: runLogFile)
            } catch {
                updated.imagePath = nil
                updated.renderError = error.localizedDescription
                failureCount += 1

                let failedLog = BatchLogger.render(
                    level: .warning,
                    message: "phase=P4 event=render_item_failed item.id=\(item.id) error=\(error.localizedDescription)"
                )
                logger.writeRaw(failedLog)
                try logWriter.append(failedLog, to: runLogFile)
            }
            renderedItems.append(updated)
        }

        return BatchRenderSummary(
            items: renderedItems,
            successCount: successCount,
            failureCount: failureCount,
            reusedCount: reusedCount
        )
    }

    private func normalizedNoteText(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func selectDiversifiedCandidates(
        from ranked: [Stage1Candidate],
        targetCount: Int,
        maxPerChapter: Int
    ) -> [Stage1Candidate] {
        guard targetCount > 0 else {
            return []
        }

        var selected: [Stage1Candidate] = []
        var selectedIDs: Set<String> = []
        var chapterCounts: [Int: Int] = [:]

        for candidate in ranked {
            if selected.count >= targetCount {
                break
            }
            if chapterCounts[candidate.chapterOrder, default: 0] > 0 {
                continue
            }
            selected.append(candidate)
            selectedIDs.insert(candidate.id)
            chapterCounts[candidate.chapterOrder, default: 0] += 1
        }

        for candidate in ranked {
            if selected.count >= targetCount {
                break
            }
            if selectedIDs.contains(candidate.id) {
                continue
            }
            if chapterCounts[candidate.chapterOrder, default: 0] >= maxPerChapter {
                continue
            }
            selected.append(candidate)
            selectedIDs.insert(candidate.id)
            chapterCounts[candidate.chapterOrder, default: 0] += 1
        }

        for candidate in ranked {
            if selected.count >= targetCount {
                break
            }
            if selectedIDs.contains(candidate.id) {
                continue
            }
            selected.append(candidate)
            selectedIDs.insert(candidate.id)
        }

        return selected
    }

    private func compareForRanking(_ lhs: Stage1Candidate, _ rhs: Stage1Candidate) -> Bool {
        let leftScore = rankingScore(for: lhs)
        let rightScore = rankingScore(for: rhs)
        if leftScore != rightScore {
            return leftScore > rightScore
        }
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.chapterOrder != rhs.chapterOrder {
            return lhs.chapterOrder < rhs.chapterOrder
        }
        return lhs.id < rhs.id
    }

    private func rankingScore(for candidate: Stage1Candidate) -> Double {
        let length = candidate.highlightText.count
        let lengthBonus: Double
        if length >= 80 && length <= 240 {
            lengthBonus = 0.14
        } else if length >= 48 && length <= 320 {
            lengthBonus = 0.06
        } else {
            lengthBonus = -0.10
        }

        let tagBonus = min(Double(candidate.tags.count), 2) * 0.01
        let noteBonus = candidate.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 0.01
        return candidate.score + lengthBonus + tagBonus + noteBonus
    }

    private func isReasonableHighlightLength(_ highlight: String) -> Bool {
        let count = highlight.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count >= 20 && count <= 380
    }

    private func isHighlightCopiedFromExcerpt(_ highlight: String, excerptText: String) -> Bool {
        let cleanedHighlight = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHighlight.isEmpty else {
            return false
        }
        if excerptText.contains(cleanedHighlight) {
            return true
        }
        let normalizedExcerpt = normalizeForContainsCheck(excerptText)
        let normalizedHighlight = normalizeForContainsCheck(cleanedHighlight)
        return !normalizedHighlight.isEmpty && normalizedExcerpt.contains(normalizedHighlight)
    }

    private func normalizeForContainsCheck(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeForDedup(_ value: String) -> String {
        value.lowercased()
            .split(whereSeparator: isTokenSeparator(_:))
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTokenSeparator(_ character: Character) -> Bool {
        if character.isWhitespace || character.isNewline {
            return true
        }
        return character.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
    }

    private func shorten(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else {
            return value
        }
        let end = value.index(value.startIndex, offsetBy: maxLength)
        return String(value[..<end]) + "..."
    }

    private func masked(_ key: String) -> String {
        guard key.count > 8 else {
            return String(repeating: "*", count: key.count)
        }
        return "\(key.prefix(4))****\(key.suffix(4))"
    }

    private func loadOptionalImageData(path: String?, optionName: String) throws -> Data? {
        guard let path else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: trimmed, isDirectory: &isDirectory) else {
            throw BatchError.fileNotFound(trimmed)
        }
        guard !isDirectory.boolValue else {
            throw BatchError.invalidOption("\(optionName) expects an image file path")
        }

        do {
            return try Data(contentsOf: URL(fileURLWithPath: trimmed, isDirectory: false))
        } catch {
            throw BatchError.ioFailure(
                "Failed reading \(optionName) file at \(trimmed): \(error.localizedDescription)"
            )
        }
    }

    private func writeString(_ text: String, to fileURL: URL) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.ioFailure("Failed writing file at \(fileURL.path): \(error.localizedDescription)")
        }
    }

    private static let manifestISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
