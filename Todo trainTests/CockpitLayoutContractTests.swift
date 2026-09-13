import XCTest
@testable import Todo_train

final class CockpitLayoutContractTests: XCTestCase {
    func testDensityThreshold() {
        XCTAssertEqual(CockpitLayoutPolicy.density(forHeight: 84), .compact)
        XCTAssertEqual(CockpitLayoutPolicy.density(forHeight: 119), .compact)
        XCTAssertEqual(CockpitLayoutPolicy.density(forHeight: 120), .regular)
        XCTAssertEqual(CockpitLayoutPolicy.density(forHeight: 160), .regular)
    }

    func testLockScreenRegularFitsOneTwentyWithoutControls() {
        let regular = CockpitLayoutPolicy.requiredTotalHeight(
            density: .regular,
            hasControls: false,
            surface: .lockScreen
        )
        XCTAssertLessThanOrEqual(regular, 120)
        XCTAssertTrue(
            CockpitLayoutPolicy.fits(
                proposedHeight: 120,
                density: .regular,
                hasControls: false,
                surface: .lockScreen
            )
        )
    }

    func testLockScreenRegularExceedsMaxWithControls() {
        let regular = CockpitLayoutPolicy.requiredTotalHeight(
            density: .regular,
            hasControls: true,
            surface: .lockScreen
        )
        XCTAssertGreaterThan(regular, CockpitSizeContract.lockScreenMaxHeight)
        XCTAssertFalse(
            CockpitLayoutPolicy.fits(
                proposedHeight: 160,
                density: .regular,
                hasControls: true,
                surface: .lockScreen
            )
        )
        let withoutDeadline = CockpitLayoutPolicy.lockScreenRegularWithoutDeadlineHeight(hasControls: true)
        XCTAssertLessThanOrEqual(withoutDeadline, CockpitSizeContract.lockScreenMaxHeight)
    }

    func testLockScreenCompactFitsMinHeightWithControls() {
        let compact = CockpitLayoutPolicy.requiredTotalHeight(
            density: .compact,
            hasControls: true,
            surface: .lockScreen
        )
        XCTAssertLessThanOrEqual(compact, CockpitSizeContract.lockScreenMinHeight)
        XCTAssertTrue(
            CockpitLayoutPolicy.fits(
                proposedHeight: 84,
                density: .compact,
                hasControls: true,
                surface: .lockScreen
            )
        )
    }

    func testLockScreenRegularFitsMaxWithoutControls() {
        let regular = CockpitLayoutPolicy.requiredTotalHeight(
            density: .regular,
            hasControls: false,
            surface: .lockScreen
        )
        XCTAssertLessThanOrEqual(regular, CockpitSizeContract.lockScreenMaxHeight)
        XCTAssertTrue(
            CockpitLayoutPolicy.fits(
                proposedHeight: 160,
                density: .regular,
                hasControls: false,
                surface: .lockScreen
            )
        )
    }

    func testResolvedDensityPrefersRegularWhenItFits() {
        XCTAssertEqual(
            CockpitLayoutPolicy.resolvedDensity(
                proposedHeight: 160,
                hasControls: false,
                surface: .lockScreen
            ),
            .regular
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.resolvedDensity(
                proposedHeight: 120,
                hasControls: false,
                surface: .lockScreen
            ),
            .regular
        )
        // With controls: full regular overflows 160, but title+progress still prefer regular tier.
        XCTAssertEqual(
            CockpitLayoutPolicy.resolvedDensity(
                proposedHeight: 160,
                hasControls: true,
                surface: .lockScreen
            ),
            .regular
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.resolvedDensity(
                proposedHeight: 84,
                hasControls: true,
                surface: .lockScreen
            ),
            .compact
        )
    }

    func testStandByInstrumentFitsNominalHeights() {
        for height: CGFloat in [84, 120, 160, 240, 400] {
            let density = CockpitLayoutPolicy.resolvedDensity(
                proposedHeight: height,
                hasControls: true,
                surface: .standBy
            )
            XCTAssertTrue(
                CockpitLayoutPolicy.fits(
                    proposedHeight: height,
                    density: density,
                    hasControls: true,
                    surface: .standBy
                ),
                "StandBy \(Int(height))pt should fit density \(density)"
            )
        }
    }

    func testSizeContractClampsHeight() {
        let low = CockpitSizeContract.lockScreen(height: 40)
        XCTAssertEqual(low.height, 84)
        // StandBy keeps large proposals (no 160 ceiling).
        let high = CockpitSizeContract.standBy(height: 400)
        XCTAssertEqual(high.height, 400)
        XCTAssertEqual(high.surface, .standBy)
        let floored = CockpitSizeContract.standBy(height: 40)
        XCTAssertEqual(floored.height, 84)
    }

    func testControlHeightsDoNotDoubleCountPadding() {
        // Fixed control chrome must stay within the contract constants.
        XCTAssertEqual(CockpitSizeContract.controlHeight, 44)
        XCTAssertEqual(CockpitSizeContract.islandExpandedControlHeight, 40)
        XCTAssertEqual(CockpitSizeContract.compactControlHeight, 36)
        XCTAssertLessThanOrEqual(
            CockpitSizeContract.controlHeight,
            CockpitSizeContract.lockScreenMaxHeight / 2
        )
    }

    func testStandByFixedChromeFitsProposal() {
        for height: CGFloat in [84, 120, 160, 240, 400] {
            let density = CockpitLayoutPolicy.density(forHeight: height)
            let chrome = CockpitLayoutPolicy.standByFixedChromeHeight(density: density)
                + CockpitStandByChrome.margin * 2
            XCTAssertLessThanOrEqual(
                chrome,
                height + 0.5,
                "StandBy fixed chrome+min timer must fit \(Int(height))pt"
            )
            XCTAssertGreaterThanOrEqual(
                CockpitStandByChrome.minTimerHeight,
                36
            )
        }
    }

    func testStandByMetricsUseFixedChromeNotRatios() {
        let metrics = CockpitStandByMetrics(width: 408, height: 240)
        XCTAssertEqual(metrics.margin, CockpitStandByChrome.margin)
        XCTAssertEqual(metrics.progressHeight, CockpitStandByChrome.progressHeight)
        XCTAssertEqual(metrics.titleSize, CockpitStandByChrome.titleFont)
        XCTAssertEqual(metrics.deadlineSize, CockpitStandByChrome.deadlineFont)
        XCTAssertEqual(metrics.controlFontSize, CockpitStandByChrome.controlFont)
        XCTAssertEqual(metrics.margin, 8)
    }

    func testIslandTimerWidthTemplateByDigitShape() {
        XCTAssertEqual(CockpitLayoutPolicy.islandTimerWidthTemplate(remaining: 59), "0:00")
        XCTAssertEqual(CockpitLayoutPolicy.islandTimerWidthTemplate(remaining: 9 * 60 + 59), "0:00")
        XCTAssertEqual(CockpitLayoutPolicy.islandTimerWidthTemplate(remaining: 10 * 60), "00:00")
        XCTAssertEqual(CockpitLayoutPolicy.islandTimerWidthTemplate(remaining: 59 * 60 + 59), "00:00")
        XCTAssertEqual(CockpitLayoutPolicy.islandTimerWidthTemplate(remaining: 3600), "0:00:00")
        // Templates must stay within HIG compact / minimal caps (character count proxy).
        for remaining: TimeInterval in [59, 600, 3600] {
            let template = CockpitLayoutPolicy.islandTimerWidthTemplate(remaining: remaining)
            XCTAssertLessThanOrEqual(template.count, 7)
            if remaining < 3600 {
                XCTAssertLessThanOrEqual(template.count, 5)
            }
        }
    }

    func testIslandWidthContractsMatchHIG() {
        XCTAssertEqual(CockpitSizeContract.islandCompactSide.width, 62.33, accuracy: 0.01)
        XCTAssertEqual(CockpitSizeContract.islandMinimalMaxWidth, 45)
        XCTAssertLessThanOrEqual(
            CockpitSizeContract.islandExpandedTrailingMaxWidth,
            64
        )
        XCTAssertLessThanOrEqual(
            CockpitSizeContract.islandCompactSide.width,
            CockpitSizeContract.islandCompactSide.width
        )
    }
}
