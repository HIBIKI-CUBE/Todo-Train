//
//  PR160IslandCaptureTests.swift
//
//  Simulator shots for PR 160 2a. Skipped unless /tmp/pr160-2a-capture exists,
//  so the normal suite does not drive the Dynamic Island.
//

import XCTest

final class PR160IslandCaptureTests: XCTestCase {
    private let flag = "/tmp/pr160-2a-capture"
    private let shotDir = "/tmp/pr160-2a-shots"

    @MainActor
    func testCaptureDynamicIsland() throws {
        guard FileManager.default.fileExists(atPath: flag) else {
            throw XCTSkip("Set up by tools/screenshots/pr160-2a-capture.sh")
        }
        let dir = URL(fileURLWithPath: shotDir, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Compact: 12:00, 1:30, overtime. Expanded: riding, paused, prompt, overtime.
        let shots: [(state: String, compact: String, expanded: String?)] = [
            ("laRemain12", "compact-12-00.png", "expanded-riding.png"),
            ("laRemain90", "compact-1-30.png", nil),
            ("laOvertime", "compact-overtime.png", "expanded-overtime.png"),
            ("laPaused", "compact-paused.png", "expanded-paused.png"),
            ("laPrompt", "compact-prompt.png", "expanded-prompt.png")
        ]
        for shot in shots {
            let app = XCUIApplication()
            app.launchArguments = ["-uiPreviewState", shot.state, "-uiPreviewLiveActivity"]
            app.launch()
            let ready = app.staticTexts["スクショ用"].waitForExistence(timeout: 12)
            XCTAssertTrue(ready, "preview \(shot.state) did not show")
            XCUIDevice.shared.press(.home)
            sleep(3)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let compact = XCUIScreen.main.screenshot()
            try compact.pngRepresentation.write(to: dir.appendingPathComponent(shot.compact))
            if let expandedName = shot.expanded {
                let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.055))
                island.press(forDuration: 1.3)
                sleep(1)
                let expanded = XCUIScreen.main.screenshot()
                try expanded.pngRepresentation.write(to: dir.appendingPathComponent(expandedName))
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
                sleep(1)
            }
            app.terminate()
        }
    }
}
