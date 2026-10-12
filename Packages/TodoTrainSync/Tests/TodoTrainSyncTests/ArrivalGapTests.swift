import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Reminder days")
struct ReminderDayTests {
    private let tokyo = ReminderDayTests.calendar(identifier: "Asia/Tokyo")

    @Test func weekdaysPassAndWeekendsStayQuiet() {
        #expect(ReminderDay.allows(day(2024, 1, 9), calendar: tokyo))
        #expect(!ReminderDay.allows(day(2024, 1, 6), calendar: tokyo))
        #expect(!ReminderDay.allows(day(2024, 1, 7), calendar: tokyo))
    }

    @Test func japaneseHolidaysAndTheirSubstitutesStayQuiet() {
        let holidays = [
            day(2024, 1, 1),
            day(2024, 1, 8),
            day(2024, 2, 12),
            day(2024, 3, 20),
            day(2024, 5, 3),
            day(2024, 5, 6),
            day(2024, 7, 15),
            day(2024, 8, 11),
            day(2024, 9, 16),
            day(2024, 9, 22),
            day(2024, 9, 23),
            day(2024, 10, 14),
            day(2024, 11, 4),
            day(2009, 9, 22),
        ]
        for date in holidays {
            #expect(!ReminderDay.allows(date, calendar: tokyo))
        }
        #expect(ReminderDay.allows(day(2024, 1, 9), calendar: tokyo))
        #expect(ReminderDay.allows(day(2024, 5, 7), calendar: tokyo))
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func calendar(identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }
}

@Suite("Arrival gap deciding")
struct ArrivalGapDecidingTests {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    private let tokyo = ArrivalGapDecidingTests.tokyoCalendar()

    @Test func gap1ThenGap2UseDifferentDevicesAndDoNotRingTogether() {
        let both: [NudgeSurface] = [.mac, .iphone]
        let atGap1 = decide(now: stamp.addingTimeInterval(3 * 60), foreground: both, macAttending: true)
        #expect(atGap1.visible?.stage == .gap1)
        #expect(atGap1.visible?.surface == .mac)
        #expect(atGap1.visible?.rings == true)
        #expect(atGap1.newlyDue.map(\.stage) == [.gap1])
        #expect(atGap1.upcoming.map(\.stage) == [.gap2])
        #expect(atGap1.upcoming.first?.surface == .iphone)
        #expect(atGap1.prompt == CabinCopy.readyToBoard(title: "週次"))

        let atGap2 = decide(
            now: stamp.addingTimeInterval(6 * 60),
            fired: [.gap1],
            foreground: both,
            macAttending: true
        )
        #expect(atGap2.visible?.stage == .gap2)
        #expect(atGap2.visible?.surface == .iphone)
        #expect(atGap2.visible?.rings == true)
        #expect(atGap2.newlyDue.map(\.stage) == [.gap2])
        #expect(atGap2.visible?.surface != atGap1.visible?.surface)
        #expect(atGap2.wakeAt == stamp.addingTimeInterval(6 * 60 + 1))
    }

    @Test func aLateWakeDoesNotTreatTheFirstGapAsFresh() {
        let jumped = decide(
            now: stamp.addingTimeInterval(6 * 60),
            foreground: [.mac, .iphone],
            macAttending: true
        )
        let now = stamp.addingTimeInterval(6 * 60)
        let fresh = jumped.newlyDue.filter { now.timeIntervalSince($0.fireAt) <= ArrivalGapDeciding.fresh }
        #expect(jumped.newlyDue.map(\.stage) == [.gap1, .gap2])
        #expect(fresh.map(\.stage) == [.gap2])
    }

    @Test func iphoneOnlyRingsItsOwnTurn() {
        let decision = decide(
            now: stamp.addingTimeInterval(3 * 60),
            foreground: [.iphone],
            macAttending: false
        )
        #expect(decision.visible?.surface == .iphone)
        #expect(decision.visible?.rings == true)
        let later = decide(
            now: stamp.addingTimeInterval(6 * 60),
            fired: [.gap1],
            foreground: [.iphone],
            macAttending: false
        )
        #expect(later.visible?.surface == .mac)
        #expect(later.visible?.rings == false)
    }

    @Test func beforeTheWindowAndAfterItStayHidden() {
        let early = decide(now: stamp.addingTimeInterval(3 * 60 - 1), foreground: [.iphone])
        #expect(early.visible == nil)
        #expect(early.newlyDue.isEmpty)
        #expect(early.wakeAt == stamp.addingTimeInterval(3 * 60))

        let late = decide(now: stamp.addingTimeInterval(6 * 60 + 1), fired: [.gap1, .gap2], foreground: [.iphone])
        #expect(late == .hidden)
    }

    @Test func theArrivalScreenSuppressesTheCardWithoutMarkingItFired() {
        let open = decide(
            now: stamp.addingTimeInterval(3 * 60),
            arrivalScreenOpen: true,
            foreground: [.iphone]
        )
        #expect(open.visible == nil)
        #expect(open.newlyDue.isEmpty)
        #expect(open.wakeAt == stamp.addingTimeInterval(6 * 60))
    }

    @Test func weekendsAndHolidaysAndADismissStayDown() {
        let saturday = day(2024, 1, 6)
        let quiet = decide(stampedAt: saturday, now: saturday.addingTimeInterval(3 * 60), calendar: tokyo)
        #expect(quiet == .hidden)

        let friday = day(2024, 1, 5, hour: 23, minute: 58)
        let crossed = decide(stampedAt: friday, now: friday.addingTimeInterval(3 * 60), calendar: tokyo)
        #expect(crossed == .hidden)

        let holiday = day(2024, 1, 1)
        #expect(decide(stampedAt: holiday, now: holiday.addingTimeInterval(3 * 60), calendar: tokyo) == .hidden)

        #expect(decide(now: stamp.addingTimeInterval(3 * 60), dismissed: true) == .hidden)
        #expect(decide(now: stamp.addingTimeInterval(3 * 60), cabinEnabled: false) == .hidden)
        #expect(
            ArrivalGapDeciding.decide(
                stampedAt: nil,
                now: stamp,
                arrivalScreenOpen: false,
                blocked: false,
                dismissed: false,
                cabinEnabled: true,
                fired: [],
                foreground: [.iphone],
                macAttending: false,
                reservedTitle: nil
            ) == .hidden
        )
    }

    @Test func noReservationUsesTheIdleLine() {
        let decision = decide(
            now: stamp.addingTimeInterval(3 * 60),
            foreground: [.iphone],
            reservedTitle: nil
        )
        #expect(decision.prompt == CabinCopy.idle)
    }

    @Test func aRightwardReleasePastHalfTheCardBoards() {
        #expect(ArrivalGapBoardGesture.commits(translationX: 101, translationY: 10, cardWidth: 200))
        #expect(!ArrivalGapBoardGesture.commits(translationX: 100, translationY: 0, cardWidth: 200))
        #expect(!ArrivalGapBoardGesture.commits(translationX: 160, translationY: 170, cardWidth: 200))
        #expect(!ArrivalGapBoardGesture.commits(translationX: -160, translationY: 0, cardWidth: 200))
        #expect(!ArrivalGapBoardGesture.commits(translationX: 80, translationY: 0, cardWidth: 0))
    }

    private func decide(
        stampedAt: Date? = nil,
        now: Date,
        arrivalScreenOpen: Bool = false,
        blocked: Bool = false,
        dismissed: Bool = false,
        cabinEnabled: Bool = true,
        fired: Set<NudgeGap> = [],
        foreground: [NudgeSurface] = [.mac, .iphone],
        macAttending: Bool = true,
        reservedTitle: String? = "週次",
        calendar: Calendar = .current
    ) -> ArrivalGapDecision {
        ArrivalGapDeciding.decide(
            stampedAt: stampedAt ?? stamp,
            now: now,
            arrivalScreenOpen: arrivalScreenOpen,
            blocked: blocked,
            dismissed: dismissed,
            cabinEnabled: cabinEnabled,
            fired: fired,
            foreground: foreground,
            macAttending: macAttending,
            reservedTitle: reservedTitle,
            calendar: calendar
        )
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func tokyoCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
}

@Suite("Arrival gap chrome")
struct ArrivalGapChromeTests {
    @Test func reservedFaceHasNoNextBlockAndKeepsTheMenuIconOnly() {
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: gapSnap(reserved: true), now: 1_700_000_180)
        )
        #expect(view.isVisible)
        #expect(view.showsArrivalGap)
        #expect(view.canBoardReserved)
        #expect(view.nudgePrompt == CabinCopy.readyToBoard(title: "週次"))
        #expect(view.title == "週次")
        #expect(view.nextBlockLine == nil)
        #expect(view.occupancy == nil)
        #expect(view.holdLamp)
        #expect(!view.showsNudgeChoices)

        let bar = MenuBarPresentation.make(
            MenuBarInput(pairing: .paired, snap: gapSnap(reserved: true), now: 1_700_000_180)
        )
        #expect(bar.barTitle == nil)
        #expect(bar.canBoardReserved)
    }

    @Test func noReservationIsTheIdleLineWithoutABoardAction() {
        let view = RideOverlayPresentation.make(
            MenuBarInput(pairing: .paired, snap: gapSnap(reserved: false, surface: .iphone), now: 1_700_000_360)
        )
        #expect(view.isVisible)
        #expect(view.nudgePrompt == CabinCopy.idle)
        #expect(!view.canBoardReserved)
        #expect(!view.holdLamp)
        #expect(view.title.isEmpty)
        #expect(view.nextBlockLine == nil)

        let bar = MenuBarPresentation.make(
            MenuBarInput(pairing: .paired, snap: gapSnap(reserved: false, surface: .iphone), now: 1_700_000_360)
        )
        #expect(bar.barTitle == nil)
        #expect(!bar.canBoardReserved)
    }

    @Test func macRingsOnlyItsGapTurnAndDoesNotReplay() {
        let session = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let plan = [
            WireNudgePlanItem(stage: .gap1, fireAt: 180, surface: .mac, rings: true),
            WireNudgePlanItem(stage: .gap2, fireAt: 360, surface: .iphone, rings: true),
        ]
        var seen = Set<String>()
        var sounded: [String] = []
        for now in [179, 180, 181, 360, 361] {
            let step = MacNudgeRinging.cues(sessionID: session, nudge: nil, plan: plan, now: now, seen: seen)
            seen = step.seen
            sounded.append(contentsOf: step.fresh.filter(\.sound).map(\.key))
        }
        #expect(sounded == ["gap1|180"])

        let late = MacNudgeRinging.cues(sessionID: session, nudge: nil, plan: plan, now: 400, seen: [])
        #expect(late.fresh.allSatisfy { !$0.sound })

        let iphone = WireNudge(
            id: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!,
            kind: .gap,
            stage: .gap2,
            ringSurface: .iphone,
            firedAt: 360
        )
        let silent = MacNudgeRinging.cues(sessionID: session, nudge: iphone, plan: nil, now: 360, seen: [])
        #expect(silent.fresh.isEmpty)
    }

    private func gapSnap(reserved: Bool, surface: NudgeRingSurface = .mac) -> SnapPlaintext {
        let ticket = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        return SnapPlaintext(
            rev: 7,
            sessionId: nil,
            ticketId: nil,
            title: nil,
            phase: .idle,
            startedAt: nil,
            estimatedSeconds: nil,
            pausedAccumulated: nil,
            pausedAt: nil,
            boardedDeviceID: nil,
            serviceActive: true,
            cabinEnabled: true,
            pendingCabin: .gap,
            nextBlockTitle: "次の予定",
            nextBlockStartsAt: 1_700_000_900,
            nudge: WireNudge(
                id: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!,
                kind: .gap,
                stage: surface == .mac ? .gap1 : .gap2,
                ringSurface: surface,
                firedAt: surface == .mac ? 1_700_000_180 : 1_700_000_360
            ),
            reserved: reserved
                ? WireReservedTicket(ticketId: ticket, title: "週次", estimatedSeconds: 1500)
                : nil
        )
    }
}
