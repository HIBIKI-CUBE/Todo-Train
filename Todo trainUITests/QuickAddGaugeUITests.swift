//
//  QuickAddGaugeUITests.swift
//  Todo trainUITests
//

import XCTest

final class QuickAddGaugeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    func testTapSelectedMinuteIssuesTicket() throws {
        launchQuickAdd()
        let title = app.textFields["quickAdd.title"]
        title.tap()
        title.typeText("ゲージ発行")

        XCTAssertTrue(app.otherElements["quickAdd.gauge"].waitForExistence(timeout: 2))
        tapGauge(at: 0.5)

        XCTAssertFalse(
            app.navigationBars["新しい切符"].waitForExistence(timeout: 3),
            "単発発行後はシートが閉じる"
        )
    }

    @MainActor
    func testSameMinuteIssuesTwiceWithContinuousDump() throws {
        launchQuickAdd(continuousDump: true)

        let title = app.textFields["quickAdd.title"]
        title.tap()
        title.typeText("A")

        tapGauge(at: 0.5)
        XCTAssertTrue(
            app.buttons["取り消す"].waitForExistence(timeout: 5),
            "連続掃き出しではシートを開いたまま発行する"
        )
        XCTAssertTrue(app.navigationBars["新しい切符"].exists)
        XCTAssertTrue(app.staticTexts["発行 1"].waitForExistence(timeout: 3))

        title.tap()
        title.typeText("B")
        tapGauge(at: 0.5)
        XCTAssertTrue(app.staticTexts["発行 2"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptyTitleTapMovesFocusToTitleField() throws {
        launchQuickAdd()
        XCTAssertTrue(app.otherElements["quickAdd.gauge"].waitForExistence(timeout: 2))
        tapGauge(at: 0.5)

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 3),
            "題名が空のときゲージを離すと題名欄にフォーカスする"
        )
        XCTAssertTrue(app.navigationBars["新しい切符"].exists, "シートは閉じない")
    }

    private func launchQuickAdd(continuousDump: Bool = false) {
        app.launchArguments = [FocusUIPreviewLaunch.stateArgument, "quickAdd"]
        if continuousDump {
            app.launchArguments.append("-uiPreviewQuickAddContinuous")
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["新しい切符"].waitForExistence(timeout: 5))
    }

    private func tapGauge(at normalizedX: CGFloat) {
        let gauge = app.otherElements["quickAdd.gauge"]
        let start = gauge.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5))
        let end = gauge.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}

/// Mirrors DEBUG launch flag without linking app target types into UITests.
private enum FocusUIPreviewLaunch {
    static let stateArgument = "-uiPreviewState"
}
