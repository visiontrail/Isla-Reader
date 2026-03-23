//
//  ReaderWebViewCacheKeyTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct ReaderWebViewCacheKeyTests {
    @Test
    func contentIDIsNamespacedByBook() {
        let firstBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let secondBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

        let firstContentID = ReaderWebView.makeContentID(bookID: firstBookID, chapterOrder: 17)
        let secondContentID = ReaderWebView.makeContentID(bookID: secondBookID, chapterOrder: 17)

        #expect(firstContentID == "00000000-0000-0000-0000-000000000101-17")
        #expect(secondContentID == "00000000-0000-0000-0000-000000000202-17")
        #expect(firstContentID != secondContentID)
    }
}
