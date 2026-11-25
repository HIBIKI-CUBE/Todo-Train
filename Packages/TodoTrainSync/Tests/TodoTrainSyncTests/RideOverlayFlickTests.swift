import Foundation
import Testing
import TodoTrainSync

@Suite("Ride overlay flick")
struct RideOverlayFlickTests {
    private let screen = OverlayRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func thresholdIs150AndProjectionIsPointThree() {
        #expect(RideOverlayGeometry.flickThreshold == 150)
        #expect(RideOverlayGeometry.flickProjection == 0.3)
        #expect(RideOverlayGeometry.flickVelocityWindow >= 0.08)
        #expect(RideOverlayGeometry.flickVelocityWindow <= 0.1)
    }

    @Test func belowThresholdKeepsTheNearestCorner() {
        let released = card(40, 40)
        let slow = OverlayVelocity(x: RideOverlayGeometry.flickThreshold - 1, y: 0)
        #expect(slow.speed < RideOverlayGeometry.flickThreshold)
        let layout = place(released, slow)
        #expect(layout == RideOverlayGeometry.layout(afterDrag: released, screen: screen))
        #expect(layout.corner == .bottomLeading)
        #expect(!layout.isTucked)

        let diagonal = OverlayVelocity(x: 100, y: 100)
        #expect(diagonal.speed < RideOverlayGeometry.flickThreshold)
        #expect(place(released, diagonal).corner == .bottomLeading)
    }

    @Test func atThresholdFollowsTheThrow() {
        let released = card(40, 40)
        let flick = OverlayVelocity(x: RideOverlayGeometry.flickThreshold, y: 0)
        #expect(flick.speed >= RideOverlayGeometry.flickThreshold)
        let layout = place(released, flick)
        #expect(layout.corner == .bottomTrailing)
        #expect(!layout.isTucked)
    }

    @Test func directionMapsToTheFourCorners() {
        let released = card(1000, 700)
        #expect(place(released, .zero).corner == .topTrailing)

        #expect(place(released, OverlayVelocity(x: 400, y: 400)).corner == .topTrailing)
        #expect(place(released, OverlayVelocity(x: -400, y: 400)).corner == .topLeading)
        #expect(place(released, OverlayVelocity(x: 400, y: -400)).corner == .bottomTrailing)
        #expect(place(released, OverlayVelocity(x: -400, y: -400)).corner == .bottomLeading)

        // Signs, not the quadrant of the projected point. 80 pt/s rightward
        // moves the card 24 pt in 0.3s and it stays on the leading half.
        let stillLeading = card(400, 40)
        #expect(stillLeading.midX + 80 * RideOverlayGeometry.flickProjection < screen.midX)
        #expect(place(stillLeading, OverlayVelocity(x: 80, y: 400)).corner == .topTrailing)
    }

    @Test func aQuietAxisKeepsTheReleaseSide() {
        let bottomLeading = card(40, 40)
        let deadzone = RideOverlayGeometry.flickAxisDeadzone
        let keepVertical = OverlayVelocity(x: 400, y: deadzone - 1)
        #expect(place(bottomLeading, keepVertical).corner == .bottomTrailing)

        let flipVertical = OverlayVelocity(x: 400, y: deadzone)
        #expect(place(bottomLeading, flipVertical).corner == .topTrailing)

        let topTrailing = card(1000, 700)
        let keepHorizontal = OverlayVelocity(x: deadzone - 1, y: -400)
        #expect(place(topTrailing, keepHorizontal).corner == .bottomTrailing)

        let flipHorizontal = OverlayVelocity(x: -deadzone, y: -400)
        #expect(place(topTrailing, flipHorizontal).corner == .bottomLeading)
    }

    @Test func flickNeverTucksAndSlowReleaseStillDoes() {
        let offTrailing = card(screen.maxX - 20, 40)
        let slow = OverlayVelocity(x: 100, y: 0)
        let tucked = place(offTrailing, slow)
        #expect(tucked.isTucked)
        #expect(tucked.corner == .bottomTrailing)
        #expect(tucked == RideOverlayGeometry.layout(afterDrag: offTrailing, screen: screen))

        let thrownBack = place(offTrailing, OverlayVelocity(x: -400, y: 400))
        #expect(!thrownBack.isTucked)
        #expect(thrownBack.corner == .topLeading)

        let thrownOut = place(offTrailing, OverlayVelocity(x: 800, y: 0))
        #expect(!thrownOut.isTucked)
        #expect(thrownOut.corner == .bottomTrailing)

        // Projection clears the tuck line. The release itself does not.
        let inside = card(400, 200)
        let fast = OverlayVelocity(x: 3000, y: 10)
        let projectedX = inside.x + fast.x * RideOverlayGeometry.flickProjection
        #expect(projectedX + inside.width - screen.maxX >= RideOverlayGeometry.tuckThreshold)
        let flung = place(inside, fast)
        #expect(!flung.isTucked)
        #expect(flung.corner == .bottomTrailing)
    }

    @Test func projectionPicksTheDisplayAheadOfTheThrow() {
        let left = OverlayRect(x: 0, y: 0, width: 1440, height: 900)
        let right = OverlayRect(x: 1440, y: 0, width: 1440, height: 900)
        let screens = [OverlayScreen(left), OverlayScreen(right)]
        let released = card(1000, 100)
        let stay = OverlayVelocity(x: 900, y: 0)
        let cross = OverlayVelocity(x: 1000, y: 0)
        #expect(released.midX + stay.x * RideOverlayGeometry.flickProjection < left.maxX)
        #expect(released.midX + cross.x * RideOverlayGeometry.flickProjection >= right.minX)

        let stayed = RideOverlayGeometry.layout(afterDrag: released, velocity: stay, screens: screens)
        #expect(stayed.screenIndex == 0)
        #expect(!stayed.state.isTucked)
        #expect(stayed.state.corner == .bottomTrailing)

        let crossed = RideOverlayGeometry.layout(afterDrag: released, velocity: cross, screens: screens)
        #expect(crossed.screenIndex == 1)
        #expect(!crossed.state.isTucked)
        #expect(crossed.state.corner == .bottomTrailing)
    }

    @Test func velocityUsesOnlyTheLastWindow() {
        let window = RideOverlayGeometry.flickVelocityWindow
        let end = 1.0
        let samples = [
            OverlayDragSample(time: 0, x: -500, y: 80),
            OverlayDragSample(time: end - window, x: 0, y: 10),
            OverlayDragSample(time: end, x: 150 * window, y: 10),
        ]
        let velocity = RideOverlayGeometry.velocity(samples: samples)
        #expect(abs(velocity.x - 150) < 0.001)
        #expect(abs(velocity.y) < 0.001)
        #expect(RideOverlayGeometry.velocity(samples: []) == .zero)
        #expect(RideOverlayGeometry.velocity(samples: [samples[0]]) == .zero)
    }

    @Test func glideStartsAtTheReleaseSpeedAndDoesNotPassTheCorner() {
        let from = OverlayRect(x: 0, y: 0, width: 320, height: 128)
        let to = OverlayRect(x: 240, y: 0, width: 320, height: 128)
        let glide = RideOverlayGeometry.glide(
            from: from,
            to: to,
            velocity: OverlayVelocity(x: 800, y: 0)
        )
        #expect(abs(glide.initialSpeed(distance: 240) - 800) < 0.001)
        #expect(glide.y1 <= 1)
        #expect(glide.y2 == 1)
        #expect(glide.progress(at: 0) == 0)
        #expect(abs(glide.progress(at: 1) - 1) < 0.000_001)
        var previous = 0.0
        for step in 1...20 {
            let progress = glide.progress(at: Double(step) / 20)
            #expect(progress + 0.000_001 >= previous)
            #expect(progress <= 1)
            previous = progress
        }
        #expect(glide.progress(at: 0.05) > 1 - glide.progress(at: 0.95))

        let fast = RideOverlayGeometry.glide(
            from: from,
            to: OverlayRect(x: 40, y: 0, width: 320, height: 128),
            velocity: OverlayVelocity(x: 8000, y: 0)
        )
        var peak = 0.0
        for step in 0...40 {
            peak = max(peak, fast.progress(at: Double(step) / 40))
        }
        #expect(peak <= 1)
    }

    private func card(_ x: Double, _ y: Double) -> OverlayRect {
        OverlayRect(
            x: x,
            y: y,
            width: RideOverlayGeometry.cardSize.width,
            height: RideOverlayGeometry.cardSize.height
        )
    }

    private func place(_ frame: OverlayRect, _ velocity: OverlayVelocity) -> OverlayLayoutState {
        RideOverlayGeometry.layout(afterDrag: frame, velocity: velocity, screen: screen)
    }
}
