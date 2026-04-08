import BatchSupport
import Testing

@Test("slug 生成稳定且可读")
func slugGeneration() {
    let slug = BatchSlug.make(fromEPUBPath: "/tmp/The Pragmatic Programmer (20th Anniversary).epub")
    #expect(slug == "the-pragmatic-programmer-20th-anniversary")
}

@Test("输出目录遵循 book-slug/logs 规则")
func outputLayoutRule() {
    let layout = BatchOutputLayout(outputRootPath: "/tmp/out", sourceEPUBPath: "/books/My Sample Book.epub")

    #expect(layout.bookDirectory.path == "/tmp/out/my-sample-book")
    #expect(layout.manifestFile.path == "/tmp/out/my-sample-book/manifest.json")
    #expect(layout.excerptsFile.path == "/tmp/out/my-sample-book/excerpts.jsonl")
    #expect(layout.candidatesStage1File.path == "/tmp/out/my-sample-book/candidates.stage1.jsonl")
    #expect(layout.captionsFile.path == "/tmp/out/my-sample-book/captions.jsonl")
    #expect(layout.imagesDirectory.path == "/tmp/out/my-sample-book/images")
    #expect(layout.promptsDirectory.path == "/tmp/out/my-sample-book/prompts")
    #expect(layout.stage1PromptsDirectory.path == "/tmp/out/my-sample-book/prompts/stage1")
    #expect(layout.logsDirectory.path == "/tmp/out/my-sample-book/logs")
    #expect(layout.runLogFile.path == "/tmp/out/my-sample-book/logs/run.log")
    #expect(layout.metricsFile.path == "/tmp/out/my-sample-book/logs/metrics.json")
}
