import BatchModels
import CryptoKit
import Foundation

public struct BatchExcerptChunker {
    private struct ChunkProfile {
        let target: Int
        let min: Int
        let max: Int
        let overlapRatio: Double
        let useWordMetric: Bool
    }

    public init() {}

    public func buildExcerpts(from book: BatchBook, fallbackLanguage: String) -> [BookExcerpt] {
        let preferredLanguage = normalizedLanguage(book.metadata.language) ?? normalizedLanguage(fallbackLanguage) ?? "en"
        let profile = chunkProfile(forLanguage: preferredLanguage)

        let orderedChapters = book.chapters.sorted { $0.order < $1.order }
        var excerpts: [BookExcerpt] = []

        for chapter in orderedChapters {
            let text = normalizedText(chapter.content)
            guard !text.isEmpty else { continue }

            let paragraphs = splitParagraphs(text)
            guard !paragraphs.isEmpty else { continue }

            let windows = buildWindows(from: paragraphs, profile: profile)
            for (windowIndex, windowText) in windows.enumerated() {
                guard !windowText.isEmpty else { continue }
                let excerpt = BookExcerpt(
                    id: makeExcerptID(chapterOrder: chapter.order, windowIndex: windowIndex + 1),
                    chapterOrder: chapter.order,
                    chapterTitle: chapter.title,
                    windowIndex: windowIndex + 1,
                    text: windowText,
                    textHash: sha256Hex(windowText),
                    wordCount: estimateWordCount(windowText)
                )
                excerpts.append(excerpt)
            }
        }

        return excerpts
    }

    private func chunkProfile(forLanguage language: String) -> ChunkProfile {
        if language.hasPrefix("zh") {
            return ChunkProfile(target: 1300, min: 800, max: 1800, overlapRatio: 0.18, useWordMetric: false)
        }
        return ChunkProfile(target: 850, min: 500, max: 1200, overlapRatio: 0.18, useWordMetric: true)
    }

    private func normalizedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let singleLine = trimmed.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let squashedWhitespace = Self.replacing(singleLine, pattern: #"[ \t]+"#, with: " ")
        let squashedBreaks = Self.replacing(squashedWhitespace, pattern: #"\n{3,}"#, with: "\n\n")
        return squashedBreaks.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func buildWindows(from paragraphs: [String], profile: ChunkProfile) -> [String] {
        var windows: [String] = []
        var start = 0

        while start < paragraphs.count {
            var end = start
            var metric = 0
            var parts: [String] = []

            while end < paragraphs.count {
                let paragraph = paragraphs[end]
                let nextMetric = metric + measure(paragraph, useWordMetric: profile.useWordMetric)
                if !parts.isEmpty && nextMetric > profile.max {
                    break
                }

                parts.append(paragraph)
                metric = nextMetric
                end += 1

                if metric >= profile.target && metric >= profile.min {
                    break
                }
            }

            if parts.isEmpty {
                let paragraph = paragraphs[start]
                parts = [paragraph]
                metric = measure(paragraph, useWordMetric: profile.useWordMetric)
                end = start + 1
            }

            let windowText = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !windowText.isEmpty {
                windows.append(windowText)
            }

            if end >= paragraphs.count {
                break
            }

            let overlapTarget = max(1, Int(Double(metric) * profile.overlapRatio))
            var overlap = 0
            var nextStart = end
            while nextStart > start {
                let previousParagraph = paragraphs[nextStart - 1]
                let nextOverlap = overlap + measure(previousParagraph, useWordMetric: profile.useWordMetric)
                if nextOverlap > overlapTarget {
                    break
                }
                nextStart -= 1
                overlap = nextOverlap
            }

            start = max(start + 1, nextStart)
        }

        return windows
    }

    private func measure(_ text: String, useWordMetric: Bool) -> Int {
        if useWordMetric {
            let words = text.split(whereSeparator: isSeparatorCharacter(_:))
            return max(words.count, 1)
        }
        return text.count
    }

    private func makeExcerptID(chapterOrder: Int, windowIndex: Int) -> String {
        "ch\(String(format: "%03d", chapterOrder))-ex\(String(format: "%03d", windowIndex))"
    }

    private func estimateWordCount(_ text: String) -> Int {
        let separated = text.split(whereSeparator: isSeparatorCharacter(_:))
        if separated.count > 1 {
            return separated.count
        }
        return text.filter { !isSeparatorCharacter($0) }.count
    }

    private func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func replacing(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private func isSeparatorCharacter(_ character: Character) -> Bool {
        if character.isWhitespace || character.isNewline {
            return true
        }
        return character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }
}
