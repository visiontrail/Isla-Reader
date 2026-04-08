import BatchCore
import BatchModels
import Testing

@Test("相同输入下 excerpt hash 稳定")
func excerptHashIsStable() {
    let paragraph = "阅读不是追逐信息，而是把句子放回生活里，让它在某个时刻重新发光。"
    let chapterText = (1...48).map { index in
        "段落\(index)：\(paragraph)"
    }.joined(separator: "\n\n")

    let book = BatchBook(
        metadata: BatchBookMetadata(title: "Test Book", author: "Tester", language: "zh-Hans"),
        chapters: [
            BatchBookChapter(
                title: "Chapter 1",
                content: chapterText,
                order: 1,
                sourceHref: "chapter1.xhtml"
            )
        ]
    )

    let chunker = BatchExcerptChunker()
    let first = chunker.buildExcerpts(from: book, fallbackLanguage: "zh-Hans")
    let second = chunker.buildExcerpts(from: book, fallbackLanguage: "zh-Hans")

    #expect(!first.isEmpty)
    #expect(first.map(\.id) == second.map(\.id))
    #expect(first.map(\.textHash) == second.map(\.textHash))
}
