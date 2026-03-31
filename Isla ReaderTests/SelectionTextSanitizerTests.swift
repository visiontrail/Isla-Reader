//
//  SelectionTextSanitizerTests.swift
//  LanReadTests
//

import Testing
@testable import LanRead

struct SelectionTextSanitizerTests {
    @Test
    func removesTrailingFootnoteCitationList() {
        let input = "goals to learn and get better and to adjust their path.3,4,5,6,7,8,9"
        let output = SelectionTextSanitizer.sanitizedForHighlightAndAI(input)

        #expect(output == "goals to learn and get better and to adjust their path.")
    }

    @Test
    func removesSingleTrailingCitationAfterSentencePunctuation() {
        let input = "Keep moving forward.12"
        let output = SelectionTextSanitizer.sanitizedForHighlightAndAI(input)

        #expect(output == "Keep moving forward.")
    }

    @Test
    func removesAttachedBracketAndSuperscriptCitations() {
        let input = "Learning[12] compounds¹² over time"
        let output = SelectionTextSanitizer.sanitizedForHighlightAndAI(input)

        #expect(output == "Learning compounds over time")
    }

    @Test
    func keepsRegularNumbersAndDecimals() {
        let input = "Version 2.0 improves 30% throughput in 2024."
        let output = SelectionTextSanitizer.sanitizedForHighlightAndAI(input)

        #expect(output == input)
    }
}
