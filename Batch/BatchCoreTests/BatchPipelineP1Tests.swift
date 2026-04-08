import BatchAI
import BatchCore
import BatchModels
import BatchSupport
import Foundation
import Testing

@Test("generate 在 P5 输出 manifest 与完整产物")
func generateOutputsStage2SelectedJSON() throws {
    let fileManager = FileManager.default
    let fixtureEPUB = repositoryRoot()
        .appendingPathComponent("Test Files/pg77090-images-3.epub")

    #expect(fileManager.fileExists(atPath: fixtureEPUB.path))

    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("lanread-batch-tests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let aiClient = makeStubAIClient()
    let pipeline = BatchPipeline(
        fileManager: fileManager,
        logger: BatchLogger(sink: { _ in }),
        logWriter: BatchFileLogWriter(fileManager: fileManager),
        jsonlWriter: BatchJSONLWriter(fileManager: fileManager),
        jsonFileWriter: BatchJSONFileWriter(fileManager: fileManager),
        aiClient: aiClient,
        epubParser: BatchEPubParser(fileManager: fileManager),
        excerptChunker: BatchExcerptChunker()
    )

    let result = try pipeline.runGenerate(
        config: BatchRunConfig(
            epubPath: fixtureEPUB.path,
            outputPath: tempRoot.path,
            targetHighlightCount: 20,
            language: "zh-Hans",
            style: .white,
            providerConfigPath: "",
            overwritePolicy: .replace
        )
    )

    #expect(result.phase == .p5ManifestAndRerun)

    guard let excerptsPath = result.excerptsPath else {
        Issue.record("expected excerpts path")
        return
    }
    guard let candidatesPath = result.candidatesPath else {
        Issue.record("expected candidates path")
        return
    }
    guard let selectedPath = result.selectedPath else {
        Issue.record("expected selected path")
        return
    }
    guard let imagesDirectory = result.imagesDirectory else {
        Issue.record("expected images directory")
        return
    }
    guard let manifestPath = result.manifestPath else {
        Issue.record("expected manifest path")
        return
    }

    #expect(fileManager.fileExists(atPath: excerptsPath))
    #expect(fileManager.fileExists(atPath: candidatesPath))
    #expect(fileManager.fileExists(atPath: selectedPath))
    #expect(fileManager.fileExists(atPath: imagesDirectory))
    #expect(fileManager.fileExists(atPath: manifestPath))
    #expect(fileManager.fileExists(atPath: result.runLogPath))

    let content = try String(contentsOfFile: excerptsPath, encoding: .utf8)
    let lines = content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    #expect(!lines.isEmpty)

    let firstLineData = Data(lines[0].utf8)
    let firstExcerpt = try JSONDecoder().decode(BookExcerpt.self, from: firstLineData)
    #expect(!firstExcerpt.text.isEmpty)
    #expect(!firstExcerpt.textHash.isEmpty)

    let candidatesContent = try String(contentsOfFile: candidatesPath, encoding: .utf8)
    let candidateLines = candidatesContent.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    #expect(!candidateLines.isEmpty)
    let firstCandidate = try JSONDecoder().decode(Stage1Candidate.self, from: Data(candidateLines[0].utf8))
    #expect(!firstCandidate.highlightText.isEmpty)

    let selectedData = try Data(contentsOf: URL(fileURLWithPath: selectedPath))
    let selectedOutput = try JSONDecoder().decode(Stage2SelectionOutput.self, from: selectedData)
    #expect(selectedOutput.mode == "ai")
    #expect(!selectedOutput.selected.isEmpty)
    #expect(selectedOutput.selected.count <= 20)
    #expect(selectedOutput.selected.allSatisfy { $0.imagePath != nil })

    if let firstImageRelativePath = selectedOutput.selected.first?.imagePath {
        let firstImagePath = URL(fileURLWithPath: result.outputDirectory)
            .appendingPathComponent(firstImageRelativePath)
            .path
        #expect(fileManager.fileExists(atPath: firstImagePath))
    } else {
        Issue.record("expected image path in selected output")
    }

    let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let manifest = try JSONDecoder().decode(BatchManifest.self, from: manifestData)
    #expect(manifest.sourceFile == fixtureEPUB.path)
    #expect(manifest.config.overwritePolicy == "replace")
    #expect(manifest.stats.finalItems == selectedOutput.selected.count)
    #expect(manifest.items.allSatisfy { !$0.sourceLocator.excerptHash.isEmpty })
    #expect(manifest.items.contains { ($0.imagePath ?? "").hasPrefix("images/") })
    #expect(manifest.config.profileDisplayName == "Reader")
    #expect(manifest.extensions?.captions.status == "reserved")
    #expect(manifest.extensions?.captions.outputFile == "captions.jsonl")
    #expect(manifest.extensions?.publish.status == "reserved")
}

@Test("stage1 单窗口失败不会中断整本任务")
func generateContinuesWhenSomeStage1WindowsFail() throws {
    let fileManager = FileManager.default
    let fixtureEPUB = repositoryRoot()
        .appendingPathComponent("Test Files/pg77090-images-3.epub")

    #expect(fileManager.fileExists(atPath: fixtureEPUB.path))

    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("lanread-batch-tests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let aiClient = makeStubAIClient(maxRetries: 0) { kind, index in
        kind == .stage1 && index % 2 == 1
    }

    let pipeline = BatchPipeline(
        fileManager: fileManager,
        logger: BatchLogger(sink: { _ in }),
        logWriter: BatchFileLogWriter(fileManager: fileManager),
        jsonlWriter: BatchJSONLWriter(fileManager: fileManager),
        jsonFileWriter: BatchJSONFileWriter(fileManager: fileManager),
        aiClient: aiClient,
        epubParser: BatchEPubParser(fileManager: fileManager),
        excerptChunker: BatchExcerptChunker()
    )

    let result = try pipeline.runGenerate(
        config: BatchRunConfig(
            epubPath: fixtureEPUB.path,
            outputPath: tempRoot.path,
            targetHighlightCount: 20,
            language: "zh-Hans",
            style: .white,
            providerConfigPath: nil
        )
    )

    #expect(result.phase == .p5ManifestAndRerun)
    guard let candidatesPath = result.candidatesPath else {
        Issue.record("expected candidates path")
        return
    }
    #expect(fileManager.fileExists(atPath: candidatesPath))

    let metricsPath = URL(fileURLWithPath: result.runLogPath)
        .deletingLastPathComponent()
        .appendingPathComponent("metrics.json")
    let metricsData = try Data(contentsOf: metricsPath)
    let metrics = try JSONSerialization.jsonObject(with: metricsData) as? [String: Any]
    let requestTotal = metrics?["stage1RequestCount"] as? Int ?? 0
    let successTotal = metrics?["stage1SuccessCount"] as? Int ?? 0
    let failureTotal = metrics?["stage1WindowFailureCount"] as? Int ?? 0

    #expect(requestTotal > 0)
    #expect(successTotal > 0)
    #expect(failureTotal > 0)
    #expect(requestTotal > successTotal)
}

@Test("stage2 失败时回退到本地排序")
func generateFallsBackWhenStage2Fails() throws {
    let fileManager = FileManager.default
    let fixtureEPUB = repositoryRoot()
        .appendingPathComponent("Test Files/pg77090-images-3.epub")

    #expect(fileManager.fileExists(atPath: fixtureEPUB.path))

    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("lanread-batch-tests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let aiClient = makeStubAIClient(maxRetries: 0) { kind, _ in
        kind == .stage2
    }

    let pipeline = BatchPipeline(
        fileManager: fileManager,
        logger: BatchLogger(sink: { _ in }),
        logWriter: BatchFileLogWriter(fileManager: fileManager),
        jsonlWriter: BatchJSONLWriter(fileManager: fileManager),
        jsonFileWriter: BatchJSONFileWriter(fileManager: fileManager),
        aiClient: aiClient,
        epubParser: BatchEPubParser(fileManager: fileManager),
        excerptChunker: BatchExcerptChunker()
    )

    let result = try pipeline.runGenerate(
        config: BatchRunConfig(
            epubPath: fixtureEPUB.path,
            outputPath: tempRoot.path,
            targetHighlightCount: 12,
            language: "zh-Hans",
            style: .white,
            providerConfigPath: nil
        )
    )

    #expect(result.phase == .p5ManifestAndRerun)
    guard let selectedPath = result.selectedPath else {
        Issue.record("expected selected path")
        return
    }
    let selectedData = try Data(contentsOf: URL(fileURLWithPath: selectedPath))
    let selectedOutput = try JSONDecoder().decode(Stage2SelectionOutput.self, from: selectedData)

    #expect(selectedOutput.mode == "local_fallback")
    #expect(!selectedOutput.selected.isEmpty)
    #expect(selectedOutput.selected.count <= 12)

    let metricsPath = URL(fileURLWithPath: result.runLogPath)
        .deletingLastPathComponent()
        .appendingPathComponent("metrics.json")
    let metricsData = try Data(contentsOf: metricsPath)
    let metrics = try JSONSerialization.jsonObject(with: metricsData) as? [String: Any]
    let stage2UsedFallback = metrics?["stage2UsedFallback"] as? Bool ?? false
    let stage2SuccessCount = metrics?["stage2SuccessCount"] as? Int ?? 0

    #expect(stage2UsedFallback)
    #expect(stage2SuccessCount == 0)
}

@Test("resume 重跑复用 stage1/stage2 与图片产物")
func generateResumesFromExistingArtifacts() throws {
    let fileManager = FileManager.default
    let fixtureEPUB = repositoryRoot()
        .appendingPathComponent("Test Files/pg77090-images-3.epub")

    #expect(fileManager.fileExists(atPath: fixtureEPUB.path))

    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("lanread-batch-tests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let firstPipeline = BatchPipeline(
        fileManager: fileManager,
        logger: BatchLogger(sink: { _ in }),
        logWriter: BatchFileLogWriter(fileManager: fileManager),
        jsonlWriter: BatchJSONLWriter(fileManager: fileManager),
        jsonFileWriter: BatchJSONFileWriter(fileManager: fileManager),
        aiClient: makeStubAIClient(),
        epubParser: BatchEPubParser(fileManager: fileManager),
        excerptChunker: BatchExcerptChunker()
    )

    _ = try firstPipeline.runGenerate(
        config: BatchRunConfig(
            epubPath: fixtureEPUB.path,
            outputPath: tempRoot.path,
            targetHighlightCount: 10,
            language: "zh-Hans",
            style: .white,
            providerConfigPath: nil,
            overwritePolicy: .replace
        )
    )

    let secondPipeline = BatchPipeline(
        fileManager: fileManager,
        logger: BatchLogger(sink: { _ in }),
        logWriter: BatchFileLogWriter(fileManager: fileManager),
        jsonlWriter: BatchJSONLWriter(fileManager: fileManager),
        jsonFileWriter: BatchJSONFileWriter(fileManager: fileManager),
        aiClient: makeStubAIClient(maxRetries: 0) { kind, _ in
            kind == .stage1 || kind == .stage2
        },
        epubParser: BatchEPubParser(fileManager: fileManager),
        excerptChunker: BatchExcerptChunker()
    )

    let resumedResult = try secondPipeline.runGenerate(
        config: BatchRunConfig(
            epubPath: fixtureEPUB.path,
            outputPath: tempRoot.path,
            targetHighlightCount: 10,
            language: "zh-Hans",
            style: .white,
            providerConfigPath: nil,
            overwritePolicy: .resume
        )
    )

    #expect(resumedResult.phase == .p5ManifestAndRerun)

    let metricsPath = URL(fileURLWithPath: resumedResult.runLogPath)
        .deletingLastPathComponent()
        .appendingPathComponent("metrics.json")
    let metricsData = try Data(contentsOf: metricsPath)
    let metrics = try JSONSerialization.jsonObject(with: metricsData) as? [String: Any]

    #expect((metrics?["reusedExcerpts"] as? Bool) == true)
    #expect((metrics?["reusedStage1Candidates"] as? Bool) == true)
    #expect((metrics?["reusedStage2Selection"] as? Bool) == true)
    #expect((metrics?["stage1RequestCount"] as? Int) == 0)
    #expect((metrics?["stage2RequestCount"] as? Int) == 0)
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private enum StubPromptKind {
    case stage1
    case stage2
}

private func makeStubAIClient(
    maxRetries: Int = 2,
    shouldFail: @escaping @Sendable (StubPromptKind, Int) -> Bool = { _, _ in false }
) -> BatchAIClient {
    let counter = SendableCounter()
    return BatchAIClient(
        environment: [
            "LANREAD_AI_ENDPOINT": "https://example.com/v1/chat/completions",
            "LANREAD_AI_KEY": "test-key-12345678",
            "LANREAD_AI_MODEL": "test-model",
            "LANREAD_AI_MAX_RETRIES": String(maxRetries)
        ],
        requestExecutor: { request in
            let callIndex = counter.next()

            guard let url = request.url else {
                throw BatchError.runtime("missing URL")
            }

            let prompt = try promptText(from: request.httpBody)
            let kind: StubPromptKind = isStage2Prompt(prompt) ? .stage2 : .stage1

            if shouldFail(kind, callIndex) {
                let failedData = Data("{\"error\":\"simulated\"}".utf8)
                let failedResponse = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)
                guard let failedResponse else {
                    throw BatchError.runtime("cannot build failed response")
                }
                return (failedData, failedResponse)
            }

            let responseData: Data
            switch kind {
            case .stage1:
                let highlight = extractHighlight(fromPrompt: prompt)
                let contentJSON = [
                    "candidates": [
                        [
                            "highlight_text": highlight,
                            "note_text": "适合分享的句子",
                            "tags": ["reading", "insight"],
                            "score": 0.92,
                            "reason": "表达清晰且有传播性"
                        ]
                    ]
                ] as [String: Any]
                responseData = try makeChatResponse(from: contentJSON)
            case .stage2:
                let candidateIDs = extractStage2CandidateIDs(fromPrompt: prompt)
                let selected = candidateIDs.prefix(20).enumerated().map { index, id in
                    [
                        "candidate_id": id,
                        "rank": index + 1,
                        "score": 0.88,
                        "reason": "章节分布均衡，适合传播"
                    ] as [String: Any]
                }
                let contentJSON = ["selected": selected]
                responseData = try makeChatResponse(from: contentJSON)
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            guard let response else {
                throw BatchError.runtime("cannot build response")
            }
            return (responseData, response)
        }
    )
}

private final class SendableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private func promptText(from httpBody: Data?) throws -> String {
    guard let httpBody else {
        throw BatchError.runtime("missing request body")
    }
    let payload = try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
    let messages = payload?["messages"] as? [[String: Any]]
    let prompt = messages?.last?["content"] as? String
    guard let prompt else {
        throw BatchError.runtime("missing prompt")
    }
    return prompt
}

private func makeChatResponse(from contentJSON: [String: Any]) throws -> Data {
    let contentData = try JSONSerialization.data(withJSONObject: contentJSON)
    let content = String(data: contentData, encoding: .utf8) ?? "{}"
    let responseJSON = [
        "choices": [
            ["message": ["content": content]]
        ]
    ] as [String: Any]
    return try JSONSerialization.data(withJSONObject: responseJSON)
}

private func isStage2Prompt(_ prompt: String) -> Bool {
    prompt.contains("Candidate list JSON")
}

private func extractHighlight(fromPrompt prompt: String) -> String {
    guard let startRange = prompt.range(of: "<excerpt>"),
          let endRange = prompt.range(of: "</excerpt>"),
          startRange.upperBound <= endRange.lowerBound
    else {
        return "无法提取 excerpt"
    }
    let excerpt = prompt[startRange.upperBound..<endRange.lowerBound]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if excerpt.isEmpty {
        return "无法提取 excerpt"
    }
    let piece = excerpt.prefix(80)
    return String(piece).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractStage2CandidateIDs(fromPrompt prompt: String) -> [String] {
    let pattern = #"\"id\"\s*:\s*\"([^\"]+)\""#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return []
    }

    let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
    let matches = regex.matches(in: prompt, options: [], range: range)

    var ids: [String] = []
    ids.reserveCapacity(matches.count)

    for match in matches {
        guard match.numberOfRanges > 1,
              let idRange = Range(match.range(at: 1), in: prompt)
        else {
            continue
        }
        ids.append(String(prompt[idRange]))
    }

    return ids
}
