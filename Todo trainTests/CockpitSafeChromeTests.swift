//
//  CockpitSafeChromeTests.swift
//
//  Slots for the known Live Activity size classes stay inside the system clip
//  and off the TrueDepth housing. A later edit that pulls content into a
//  corner or under the camera fails here.
//

import CoreGraphics
import XCTest
@testable import Todo_train

final class CockpitSafeChromeTests: XCTestCase {
    func testCornerInsetClearsARoundedCorner() {
        let radius: CGFloat = CockpitSafeChrome.expandedOuterRadius
        let inset = CockpitSafeChrome.cornerInset(radius: radius)
        XCTAssertEqual(inset, 13)
        XCTAssertEqual(
            CockpitSafeChrome.expandedOuterRadius - inset,
            CockpitSafeChrome.expandedOuterRadius - CockpitSafeChrome.expandedEdgeInset
        )
        let canvas = CGSize(width: CockpitSizeContract.proMaxWidth, height: CockpitSizeContract.lockScreenMaxHeight)
        let chrome = CockpitSafeChrome.resolve(surface: .islandExpanded, canvas: canvas)
        XCTAssertTrue(chrome.pointInsideClip(CGPoint(x: inset, y: inset)))
        XCTAssertFalse(chrome.pointInsideClip(CGPoint(x: inset - 1, y: inset - 1)))
        // The previous face padded 12×4 and the train mark sat in the clipped corner.
        XCTAssertFalse(chrome.pointInsideClip(CGPoint(x: 12, y: 4)))
    }

    func testKnownCanvasesKeepSlotsInsideTheClip() {
        for sample in samples {
            let chrome = CockpitSafeChrome.resolve(surface: sample.surface, canvas: sample.canvas)
            XCTAssertFalse(chrome.guardedRects.isEmpty, "\(sample.surface) \(sample.canvas)")
            for rect in chrome.guardedRects {
                XCTAssertTrue(chrome.contains(rect), "\(sample.surface) \(rect) left \(sample.canvas)")
                XCTAssertTrue(chrome.clearOfCamera(rect), "\(sample.surface) \(rect) meets the camera")
            }
            XCTAssertGreaterThanOrEqual(chrome.concentricRadius, 0)
            XCTAssertEqual(chrome.concentricRadius, chrome.clip.radius - chrome.edgeInset, accuracy: 0.001)
        }
    }

    func testExpandedControlAndTrainMarkSitInTheSafeSlots() {
        let canvas = CGSize(width: CockpitSizeContract.proMaxWidth, height: 160)
        let chrome = CockpitSafeChrome.resolve(surface: .islandExpanded, canvas: canvas)
        XCTAssertEqual(chrome.camera?.width ?? 0, CockpitSafeChrome.cameraHousing.width, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(chrome.leading.width, 80)
        XCTAssertGreaterThanOrEqual(chrome.trailing.width, CockpitSafeChrome.controlSide)
        XCTAssertGreaterThanOrEqual(chrome.trailing.height, CockpitSafeChrome.controlSide)
        XCTAssertGreaterThanOrEqual(chrome.bottom.height, 24)

        let mark = CGRect(x: chrome.leading.minX, y: chrome.leading.minY, width: 16, height: 16)
        let button = CGRect(
            x: chrome.trailing.maxX - CockpitSafeChrome.controlSide,
            y: chrome.trailing.minY,
            width: CockpitSafeChrome.controlSide,
            height: CockpitSafeChrome.controlSide
        )
        XCTAssertTrue(chrome.contains(mark))
        XCTAssertTrue(chrome.contains(button))
        XCTAssertTrue(chrome.clearOfCamera(mark))
        XCTAssertTrue(chrome.clearOfCamera(button))
        XCTAssertEqual(chrome.concentricRadius, 31, accuracy: 0.001)
    }

    func testCardCornersKeepAControlInside() {
        let canvases: [(CockpitSafeSurface, CGSize)] = [
            (.lockScreen, CGSize(width: 408, height: 160)),
            (.lockScreen, CGSize(width: 408, height: 84)),
            (.lockScreen, CGSize(width: 371, height: 160)),
            (.standBy, CGSize(width: 408, height: 160)),
            (.stack, CGSize(width: 184, height: 72)),
            (.stack, CGSize(width: 198, height: 140))
        ]
        for (surface, canvas) in canvases {
            let chrome = CockpitSafeChrome.resolve(surface: surface, canvas: canvas)
            XCTAssertGreaterThanOrEqual(chrome.content.width, CockpitSafeChrome.controlSide, "\(surface) \(canvas)")
            XCTAssertGreaterThanOrEqual(chrome.content.height, CockpitSafeChrome.controlSide, "\(surface) \(canvas)")
            let corners = [
                CGRect(x: chrome.content.minX, y: chrome.content.minY, width: 44, height: 44),
                CGRect(x: chrome.content.maxX - 44, y: chrome.content.minY, width: 44, height: 44),
                CGRect(x: chrome.content.minX, y: chrome.content.maxY - 44, width: 44, height: 44),
                CGRect(x: chrome.content.maxX - 44, y: chrome.content.maxY - 44, width: 44, height: 44)
            ]
            for corner in corners {
                XCTAssertTrue(chrome.contains(corner), "\(surface) \(corner)")
            }
        }
    }

    func testCompactCapsAndMinimalCircleKeepTheContentRect() {
        let compact = CockpitSafeChrome.resolve(
            surface: .islandCompact,
            canvas: CockpitSizeContract.islandCompactSide
        )
        XCTAssertTrue(compact.contains(compact.content))
        XCTAssertGreaterThan(compact.content.width, 40)
        XCTAssertGreaterThan(compact.content.height, 20)
        XCTAssertEqual(compact.edgeInset, CockpitSafeChrome.compactEdgeInset)

        let minimal = CockpitSafeChrome.resolve(
            surface: .islandMinimal,
            canvas: CGSize(width: 45, height: 45)
        )
        XCTAssertTrue(minimal.contains(minimal.content))
        XCTAssertEqual(minimal.edgeInset, CockpitSafeChrome.minimalEdgeInset)
        let tight = CockpitSafeChrome.resolve(
            surface: .islandMinimal,
            canvas: CockpitSizeContract.islandMinimalMin
        )
        XCTAssertTrue(tight.contains(tight.content))
        XCTAssertLessThanOrEqual(tight.edgeInset, CockpitSafeChrome.minimalEdgeInset)
    }

    private var samples: [(surface: CockpitSafeSurface, canvas: CGSize)] {
        [
            (.islandExpanded, CGSize(width: 408, height: 160)),
            (.islandExpanded, CGSize(width: 371, height: 160)),
            (.islandExpanded, CGSize(width: 340, height: 140)),
            (.islandCompact, CockpitSizeContract.islandCompactSide),
            (.islandCompact, CGSize(width: 52.33, height: 36.67)),
            (.islandMinimal, CockpitSizeContract.islandMinimalMin),
            (.islandMinimal, CGSize(width: 45, height: 45)),
            (.lockScreen, CGSize(width: 408, height: 160)),
            (.lockScreen, CGSize(width: 408, height: 84)),
            (.lockScreen, CGSize(width: 371, height: 160)),
            (.standBy, CGSize(width: 408, height: 160)),
            (.stack, CGSize(width: 184, height: 72)),
            (.stack, CGSize(width: 198, height: 140))
        ]
    }
}
