import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Offscreen notifications")
struct OffscreenNotifyTests {
    private let tokyo = OffscreenNotifyTests.calendar()
    private let tuesday = OffscreenNotifyTests.day(2024, 1, 9)
    private let saturday = OffscreenNotifyTests.day(2024, 1, 6)
    private let newYear = OffscreenNotifyTests.day(2024, 1, 1)

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        parts.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return Calendar(identifier: .gregorian).date(from: parts)!
    }

    private func screens(
        sceneActive: Bool = false,
        focusVisible: Bool = false,
        riding: Bool = true,
        hubVisible: Bool = false,
        macPipVisible: Bool = false,
        macAttending: Bool = false,
        macKnown: Bool = true
    ) -> OffscreenScreens {
        OffscreenScreens(
            sceneActive: sceneActive,
            focusVisible: focusVisible,
            riding: riding,
            hubVisible: hubVisible,
            macPipVisible: macPipVisible,
            macAttending: macAttending,
            macKnown: macKnown
        )
    }

    @Test func progressNeverPosts() {
        let delivery = OffscreenNotify.delivery(
            kind: .progress,
            screens: screens(),
            turn: 0,
            now: tuesday,
            calendar: tokyo
        )
        #expect(delivery == .none)
    }

    @Test func focusAndMacPipStayQuiet() {
        let focus = OffscreenNotify.delivery(
            kind: .overtime,
            screens: screens(sceneActive: true, focusVisible: true),
            turn: 0,
            now: tuesday,
            calendar: tokyo
        )
        let pip = OffscreenNotify.delivery(
            kind: .away,
            screens: screens(macPipVisible: true),
            turn: 0,
            now: tuesday,
            calendar: tokyo
        )
        let hub = OffscreenNotify.delivery(
            kind: .idle,
            screens: screens(sceneActive: true, riding: false, hubVisible: true),
            turn: 0,
            now: tuesday,
            calendar: tokyo
        )
        #expect(focus == .none)
        #expect(pip == .none)
        #expect(hub == .none)
    }

    @Test func unknownPresenceSendsOnIphone() {
        let delivery = OffscreenNotify.delivery(
            kind: .overtime,
            screens: screens(macPipVisible: true, macKnown: false),
            turn: 0,
            now: tuesday,
            calendar: tokyo
        )
        #expect(delivery == .iphone)
    }

    @Test func lockedPhoneWithoutMacPostsOnceOnIphone() {
        let delivery = OffscreenNotify.delivery(
            kind: .overtime,
            screens: screens(),
            turn: 0,
            now: tuesday,
            calendar: tokyo
        )
        #expect(delivery == .iphone)
    }

    @Test func turnsAlternateAndStopAtFour() {
        #expect(NudgePlanner.offscreenSurface(turn: 0, macAttending: false) == .iphone)
        #expect(NudgePlanner.offscreenSurface(turn: 1, macAttending: false) == .mac)
        #expect(NudgePlanner.offscreenSurface(turn: 0, macAttending: true) == .mac)
        #expect(NudgePlanner.offscreenSurface(turn: 1, macAttending: true) == .iphone)
        #expect(NudgePlanner.offscreenSurface(turn: 0, macAttending: false) != NudgePlanner.offscreenSurface(turn: 1, macAttending: false))
        #expect(NudgePlanner.offscreenSurface(turn: NudgeThresholds.maxRings, macAttending: false) == .none)
        let capped = OffscreenNotify.delivery(
            kind: .idle,
            screens: screens(riding: false),
            turn: NudgeThresholds.maxRings,
            now: tuesday,
            calendar: tokyo
        )
        #expect(capped == .none)
    }

    @Test func weekendsAndHolidaysStayQuiet() {
        let weekend = OffscreenNotify.delivery(
            kind: .idle,
            screens: screens(riding: false),
            turn: 0,
            now: saturday,
            calendar: tokyo
        )
        let holiday = OffscreenNotify.delivery(
            kind: .overtime,
            screens: screens(),
            turn: 0,
            now: newYear,
            calendar: tokyo
        )
        #expect(weekend == .none)
        #expect(holiday == .none)
    }

    @Test func onScreenChimesStillUseTheFourRingColumn() {
        let now = tuesday
        let input = NudgeRideInput(
            startedAt: now.addingTimeInterval(-20 * 60),
            pausedAccumulated: 0,
            pausedAt: nil,
            isPaused: false,
            passengerAccumulated: 0,
            passengerSince: nil,
            isPassenger: false,
            estimatedSeconds: 20 * 60,
            rideID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            extensions: [],
            alarmKitEndBell: false,
            foreground: [.iphone, .mac],
            macAttending: true,
            now: now
        )
        let estimate = NudgePlanner.ring(stage: .estimate, on: input)
        let handoff = NudgePlanner.ring(stage: .handoff1, on: input)
        #expect(estimate.surface != handoff.surface || !estimate.rings || !handoff.rings)
        #expect(NudgeThresholds.maxRings == 4)
        #expect(!(estimate.rings && handoff.rings && estimate.surface == handoff.surface))
    }

    @Test func macSchedulesOnlyItsTurnAndNotWhilePipIsUp() throws {
        var snap = try WireJSON.decoder().decode(
            SnapPlaintext.self,
            from: ContractFixtures.data("fixtures/snap.json")
        )
        snap.notifyOn = .mac
        snap.notifyTurn = 0
        snap.phase = .running
        let hidden = MacOffscreenPlanning.requests(snap: snap, pipVisible: false, now: tuesday, calendar: tokyo)
        #expect(hidden.contains { $0.identifier == MacOffscreenPlanning.overtimeID })
        let pip = MacOffscreenPlanning.requests(snap: snap, pipVisible: true, now: tuesday, calendar: tokyo)
        #expect(pip.isEmpty)
        snap.notifyOn = .iphone
        let iphone = MacOffscreenPlanning.requests(snap: snap, pipVisible: false, now: tuesday, calendar: tokyo)
        #expect(iphone.isEmpty)
        snap.notifyOn = .mac
        snap.phase = .idle
        snap.sessionId = nil
        snap.pendingCabin = .idle
        snap.notifyTurn = 1
        let idle = MacOffscreenPlanning.requests(snap: snap, pipVisible: false, now: tuesday, calendar: tokyo)
        #expect(idle.map(\.identifier) == [MacOffscreenPlanning.idleID(turn: 1)])
        let quiet = MacOffscreenPlanning.requests(snap: snap, pipVisible: false, now: newYear, calendar: tokyo)
        #expect(quiet.isEmpty)
    }

    @Test func olderSnapWithoutNotifyOnStillDecodes() throws {
        let snap = try WireJSON.decoder().decode(
            SnapPlaintext.self,
            from: ContractFixtures.data("fixtures/v8/snap.json")
        )
        #expect(snap.notifyOn == nil)
        #expect(snap.notifyTurn == nil)
        #expect(snap.notifyFireAt == nil)
    }
}
