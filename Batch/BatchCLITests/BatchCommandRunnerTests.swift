import BatchAI
import BatchCLI
import BatchCore
import BatchModels
import BatchSupport
import Foundation
import Testing

@Test("batch generate 在 input-dir 模式下单本失败不中断整批执行")
func runGenerateWithInputDirectoryContinuesAfterFailures() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("lanread-batch-cli-tests-\(UUID().uuidString)", isDirectory: true)
    let inputDir = tempRoot.appendingPathComponent("input", isDirectory: true)
    let outputDir = tempRoot.appendingPathComponent("output", isDirectory: true)
    try fileManager.createDirectory(at: inputDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let fixtureEPUB = repositoryRoot()
        .appendingPathComponent("Test Files/pg77090-images-3.epub")
    #expect(fileManager.fileExists(atPath: fixtureEPUB.path))

    let brokenEPUB = inputDir.appendingPathComponent("a-broken.epub")
    try "not an epub".write(to: brokenEPUB, atomically: true, encoding: .utf8)

    let validEPUB = inputDir.appendingPathComponent("z-valid.epub")
    try fileManager.copyItem(at: fixtureEPUB, to: validEPUB)

    let pipeline = BatchPipeline(
        fileManager: fileManager,
        logger: BatchLogger(sink: { _ in }),
        logWriter: BatchFileLogWriter(fileManager: fileManager),
        jsonlWriter: BatchJSONLWriter(fileManager: fileManager),
        jsonFileWriter: BatchJSONFileWriter(fileManager: fileManager),
        aiClient: makeStubAIClient(),
        epubParser: BatchEPubParser(fileManager: fileManager),
        excerptChunker: BatchExcerptChunker()
    )
    let runner = BatchCommandRunner(
        stdout: { _ in },
        stderr: { _ in },
        pipeline: pipeline,
        fileManager: fileManager
    )

    let exitCode = runner.run(arguments: [
        "generate",
        "--input-dir", inputDir.path,
        "--output", outputDir.path,
        "--overwrite-policy", "replace"
    ])
    #expect(exitCode == 1)

    let summaryPath = outputDir.appendingPathComponent("batch.summary.json")
    #expect(fileManager.fileExists(atPath: summaryPath.path))

    let summaryData = try Data(contentsOf: summaryPath)
    let summaryObject = try JSONSerialization.jsonObject(with: summaryData) as? [String: Any]
    let totalBooks = summaryObject?["total_books"] as? Int
    let succeededBooks = summaryObject?["succeeded_books"] as? Int
    let failedBooks = summaryObject?["failed_books"] as? Int
    #expect(totalBooks == 2)
    #expect(succeededBooks == 1)
    #expect(failedBooks == 1)

    let results = summaryObject?["results"] as? [[String: Any]] ?? []
    #expect(results.count == 2)

    let successRows = results.filter { ($0["status"] as? String) == "success" }
    let failureRows = results.filter { ($0["status"] as? String) == "failed" }
    #expect(successRows.count == 1)
    #expect(failureRows.count == 1)
}

@Test("captions 命令桩读取 manifest 并返回成功")
func runCaptionsStubCommand() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("lanread-batch-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let manifestPath = tempRoot.appendingPathComponent("manifest.json")
    let manifest = makeStubManifest(sourceFile: "/tmp/book.epub")
    let manifestData = try JSONEncoder().encode(manifest)
    try manifestData.write(to: manifestPath, options: .atomic)

    let stdoutBuffer = ThreadSafeStringBuffer()
    let stderrBuffer = ThreadSafeStringBuffer()
    let runner = BatchCommandRunner(
        stdout: { stdoutBuffer.append($0) },
        stderr: { stderrBuffer.append($0) },
        fileManager: fileManager
    )

    let exitCode = runner.run(arguments: [
        "captions",
        "--manifest", manifestPath.path
    ])

    #expect(exitCode == 0)
    let stdoutMessages = stdoutBuffer.snapshot()
    let stderrMessages = stderrBuffer.snapshot()
    #expect(stderrMessages.isEmpty)
    #expect(stdoutMessages.contains { $0 == "Captions stub completed." })
    #expect(stdoutMessages.contains { $0.contains("Planned captions output:") })
}

@Test("publish 命令桩读取 manifest 和 channel 并返回成功")
func runPublishStubCommand() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("lanread-batch-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let manifestPath = tempRoot.appendingPathComponent("manifest.json")
    let manifest = makeStubManifest(sourceFile: "/tmp/book.epub")
    let manifestData = try JSONEncoder().encode(manifest)
    try manifestData.write(to: manifestPath, options: .atomic)

    let stdoutBuffer = ThreadSafeStringBuffer()
    let stderrBuffer = ThreadSafeStringBuffer()
    let runner = BatchCommandRunner(
        stdout: { stdoutBuffer.append($0) },
        stderr: { stderrBuffer.append($0) },
        fileManager: fileManager
    )

    let exitCode = runner.run(arguments: [
        "publish",
        "--manifest", manifestPath.path,
        "--channel", "xiaohongshu"
    ])

    #expect(exitCode == 0)
    let stdoutMessages = stdoutBuffer.snapshot()
    let stderrMessages = stderrBuffer.snapshot()
    #expect(stderrMessages.isEmpty)
    #expect(stdoutMessages.contains { $0 == "Publish stub completed." })
    #expect(stdoutMessages.contains { $0 == "Channel: xiaohongshu" })
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeStubManifest(sourceFile: String) -> BatchManifest {
    BatchManifest(
        runId: UUID().uuidString.lowercased(),
        generatedAt: "2026-04-07T00:00:00.000Z",
        sourceFile: sourceFile,
        book: BatchManifestBook(
            title: "Stub Book",
            author: "Tester",
            language: "en"
        ),
        config: BatchManifestConfig(
            highlights: 1,
            language: "en",
            style: "white",
            model: "stub-model",
            overwritePolicy: "replace"
        ),
        stats: BatchManifestStats(
            chapters: 1,
            windows: 1,
            stage1Candidates: 1,
            deduplicatedCandidates: 1,
            stage2InputCandidates: 1,
            finalItems: 1,
            renderSuccessCount: 1,
            renderFailureCount: 0
        ),
        items: [
            BatchManifestItem(
                id: "item-001",
                rank: 1,
                chapterTitle: "Chapter 1",
                chapterOrder: 1,
                sourceExcerpt: "Example source excerpt",
                highlightText: "Example highlight",
                noteText: "Example note",
                imagePath: "images/001.png",
                score: 0.9,
                tags: ["test"],
                sourceLocator: BatchManifestSourceLocator(
                    chapterOrder: 1,
                    excerptIndex: 1,
                    excerptHash: "abc123"
                ),
                candidateId: "candidate-001",
                excerptId: "excerpt-001",
                selectionReason: "Test reason",
                renderError: nil
            )
        ],
        extensions: .reserved
    )
}

private final class ThreadSafeStringBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private enum StubPromptKind {
    case stage1
    case stage2
}

private func makeStubAIClient() -> BatchAIClient {
    BatchAIClient(
        environment: [
            "LANREAD_AI_ENDPOINT": "https://example.com/v1/chat/completions",
            "LANREAD_AI_KEY": "test-key-12345678",
            "LANREAD_AI_MODEL": "test-model",
            "LANREAD_AI_MAX_RETRIES": "1"
        ],
        requestExecutor: { request in
            guard let url = request.url else {
                throw BatchError.runtime("missing URL")
            }

            let prompt = try promptText(from: request.httpBody)
            let kind: StubPromptKind = isStage2Prompt(prompt) ? .stage2 : .stage1

            let responseData: Data
            switch kind {
            case .stage1:
                let highlight = extractHighlight(fromPrompt: prompt)
                responseData = try makeChatResponse(from: [
                    "candidates": [
                        [
                            "highlight_text": highlight,
                            "note_text": "适合分享的句子",
                            "tags": ["reading", "insight"],
                            "score": 0.9,
                            "reason": "表达清晰"
                        ]
                    ]
                ])
            case .stage2:
                let candidateIDs = extractStage2CandidateIDs(fromPrompt: prompt)
                let selected = candidateIDs.prefix(20).enumerated().map { index, id in
                    [
                        "candidate_id": id,
                        "rank": index + 1,
                        "score": 0.88,
                        "reason": "章节分布均衡"
                    ] as [String: Any]
                }
                responseData = try makeChatResponse(from: ["selected": selected])
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            guard let response else {
                throw BatchError.runtime("cannot build response")
            }
            return (responseData, response)
        }
    )
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
    return String(excerpt.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
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
