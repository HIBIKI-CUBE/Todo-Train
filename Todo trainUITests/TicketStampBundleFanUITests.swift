//
//  TicketStampBundleFanUITests.swift
//  Todo trainUITests
//
//  扇は離したあと、日を変えたあと、裏へ回したあとに畳んでいる。
//

import XCTest

final class TicketStampBundleFanUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiPreviewState", "historyBundle"]
    }

    @MainActor
    func testReleaseAndDayChangeAndBackgroundLeaveTheFanClosed() throws {
        app.launch()
        let folded = app.otherElements["ticket-stamp-bundle"]
        XCTAssertTrue(folded.waitForExistence(timeout: 8))

        dragBundle(dx: -140, dy: 8)
        XCTAssertTrue(folded.waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["ticket-stamp-bundle-open"].exists)
        XCTAssertTrue(app.navigationBars["履歴"].exists)

        dragBundle(dx: 6, dy: -90)
        XCTAssertTrue(folded.waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["ticket-stamp-bundle-open"].exists)
        XCTAssertTrue(app.navigationBars["履歴"].exists)

        app.buttons["今日"].tap()
        XCTAssertFalse(app.otherElements["ticket-stamp-bundle-open"].waitForExistence(timeout: 1))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(app.otherElements["ticket-stamp-bundle-open"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func dragBundle(dx: CGFloat, dy: CGFloat) {
        let bundle = app.otherElements["ticket-stamp-bundle"]
        let start = bundle.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.80))
        let end = start.withOffset(CGVector(dx: dx, dy: dy))
        start.press(forDuration: 0.2, thenDragTo: end)
    }
}
