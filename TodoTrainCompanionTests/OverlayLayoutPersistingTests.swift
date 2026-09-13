import Foundation
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

struct OverlayLayoutPersistingTests {
    @Test func roundTripCornerAndTuck() {
        let defaults = UserDefaults(suiteName: "overlay-layout-\(UUID().uuidString)")!
        OverlayLayoutPersisting.save(
            OverlayLayoutState(corner: .topLeading, isTucked: true),
            screenID: 42,
            to: defaults
        )
        let loaded = OverlayLayoutPersisting.load(defaults)
        #expect(loaded.corner == .topLeading)
        #expect(loaded.isTucked)
        #expect(OverlayLayoutPersisting.screenID(defaults) == 42)
    }

    @Test func missingKeysDefaultToBottomTrailing() {
        let defaults = UserDefaults(suiteName: "overlay-layout-empty-\(UUID().uuidString)")!
        let loaded = OverlayLayoutPersisting.load(defaults)
        #expect(loaded == .default)
        #expect(OverlayLayoutPersisting.screenID(defaults) == 0)
    }
}
