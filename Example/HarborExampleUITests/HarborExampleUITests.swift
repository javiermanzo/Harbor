//
//  HarborExampleUITests.swift
//  HarborExampleUITests
//
//  Created by Javier Manzo on 21/02/2023.
//

import XCTest

@MainActor
final class HarborExampleUITests: XCTestCase {

    override func setUpWithError() throws {
        // Stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    func testLaunchShowsDemoScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Harbor Examples"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["> Ready"].exists)
        XCTAssertTrue(button(titled: "GET - Simple Request", in: app).exists)
    }

    func testSettingsSheetOpensAndDismisses() throws {
        let app = XCUIApplication()
        app.launch()

        let navigationBar = app.navigationBars["Harbor Examples"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        navigationBar.buttons.firstMatch.tap()

        let settings = app.navigationBars["Global Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.buttons["Done"].tap()
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
    }

    /// The row labels also include the icon and chevron names, so match on a substring.
    private func button(titled title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
}
