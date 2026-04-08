import BatchAI
import BatchModels
import Testing

@Test("stage1 prompt 明确要求更饱满的 highlight")
func stage1PromptEncouragesLongerHighlights() {
    let client = BatchAIClient()
    let prompt = client.makeStage1Prompt(
        request: BatchStage1Request(
            bookMetadata: BatchBookMetadata(title: "Demo", author: "Author", language: "zh-Hans"),
            excerpt: BookExcerpt(
                id: "excerpt-1",
                chapterOrder: 1,
                chapterTitle: "Chapter 1",
                windowIndex: 1,
                text: "Example excerpt text.",
                textHash: "hash",
                wordCount: 3
            ),
            outputLanguage: "zh-Hans"
        )
    )

    #expect(prompt.contains("Prefer medium-to-long highlight_text passages"))
    #expect(prompt.contains("choose 2 to 4 connected sentences"))
}

@Test("stage2 prompt 明确规避过短 highlight")
func stage2PromptPrefersVisuallyFullCards() {
    let client = BatchAIClient()
    let prompt = client.makeStage2Prompt(
        request: BatchStage2Request(
            bookMetadata: BatchBookMetadata(title: "Demo", author: "Author", language: "zh-Hans"),
            candidates: [
                Stage1Candidate(
                    id: "candidate-1",
                    excerptId: "excerpt-1",
                    chapterOrder: 1,
                    chapterTitle: "Chapter 1",
                    windowIndex: 1,
                    excerptHash: "hash",
                    highlightText: "A longer quote that can fill a card more naturally.",
                    noteText: "Note",
                    tags: ["tag"],
                    score: 0.9,
                    reason: "shareable"
                )
            ],
            outputLanguage: "zh-Hans",
            targetCount: 3
        )
    )

    #expect(prompt.contains("look visually full on a share card"))
    #expect(prompt.contains("avoid overly short one-liners"))
}
