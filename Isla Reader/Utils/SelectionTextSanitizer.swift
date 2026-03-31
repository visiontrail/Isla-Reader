//
//  SelectionTextSanitizer.swift
//  LanRead
//
//  Created by AI Assistant on 2026/3/31.
//

import Foundation

enum SelectionTextSanitizer {
    static func sanitizedForHighlightAndAI(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        // Remove superscript citation digits (e.g. ¹²³) attached to text.
        text = text.replacingOccurrences(
            of: #"(\S)[⁰¹²³⁴⁵⁶⁷⁸⁹]+"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove bracket citation markers attached to text, e.g. word[12], word(12).
        text = text.replacingOccurrences(
            of: #"(\S)(?:\[\s*\d{1,3}\s*\]|\(\s*\d{1,3}\s*\))"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove attached citation lists, e.g. path.3,4,5,6
        text = text.replacingOccurrences(
            of: #"(\S)(?:\d{1,3}\s*[,，]\s*)+\d{1,3}(?=\s|$|[)\]}\"'”’.,;:!?。！？；：])"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove a single trailing citation marker when it follows sentence punctuation.
        text = text.replacingOccurrences(
            of: #"([^\d][.!?。！？:;；])\s*\d{1,3}(?=\s|$|[)\]}\"'”’.,;:!?。！？；：])"#,
            with: "$1",
            options: .regularExpression
        )

        // Clean separators that can be left behind after stripping citation markers.
        text = text.replacingOccurrences(
            of: #"(?:\s*[,，]\s*){2,}"#,
            with: ", ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(^|[\s(\[{])[,，\s]+(?=\s|$|[)\]}.,;:!?。！？；：])"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
