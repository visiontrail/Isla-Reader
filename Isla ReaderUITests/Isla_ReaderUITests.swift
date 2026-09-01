//
//  Isla_ReaderUITests.swift
//  LanReadUITests
//
//  Created by 郭亮 on 2025/9/10.
//

import XCTest

final class Isla_ReaderUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testFirstReadingUnlocksAchievementBadge() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        let declineConsent = app.buttons["ai.consent.decline"]
        if declineConsent.waitForExistence(timeout: 5) {
            declineConsent.tap()
        }

        let bookCard = app.buttons["library.book.card"]
        XCTAssertTrue(bookCard.waitForExistence(timeout: 30), "Bundled sample book should be seeded")
        bookCard.tap()

        let startReading = app.buttons["ai.summary.start_reading"]
        XCTAssertTrue(startReading.waitForExistence(timeout: 10), "Summary screen should expose Start Reading")
        startReading.tap()

        let celebration = app.staticTexts["achievement.celebration"]
        XCTAssertTrue(
            celebration.waitForExistence(timeout: 15),
            "First reading should unlock a badge immediately while the reader is still visible"
        )

        let continueButton = app.buttons["achievement.celebration.continue"].firstMatch
        XCTAssertTrue(continueButton.exists)
        continueButton.tap()

        app.terminate()
        app.launch()

        if declineConsent.waitForExistence(timeout: 5) {
            declineConsent.tap()
        }

        let progressTab = app.tabBars.buttons["进度"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 5), "Progress tab should be available")
        progressTab.tap()

        XCTAssertFalse(
            celebration.waitForExistence(timeout: 2),
            "The same badge should not be presented again after it has been acknowledged"
        )

        let viewAll = app.buttons["achievement.view_all"]
        XCTAssertTrue(viewAll.waitForExistence(timeout: 5), "Badge summary should be visible on Progress")
        viewAll.tap()

        let gallery = app.scrollViews["achievement.gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5), "Badge gallery should open")

        let firstSteps = app.buttons["achievement.badge.first_steps"]
        XCTAssertTrue(firstSteps.waitForExistence(timeout: 5), "First Steps badge should appear in the gallery")
        XCTAssertTrue(firstSteps.label.contains("已获得"), "First Steps badge should remain unlocked")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
