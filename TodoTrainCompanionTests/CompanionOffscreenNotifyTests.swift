import Foundation
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

@Suite("Mac offscreen notifications")
struct CompanionOffscreenNotifyTests {
    @Test func pipAndIphoneTurnsDoNotAskMacToPost() {
        var snap = SnapPlaintext(
            rev: 1,
            sessionId: UUID(uuidString: "11111111-1111-4111-8111-111111111111"),
            ticketId: nil,
            title: "週次レポート",
            phase: .running,
            startedAt: 1_768_000_000,
            estimatedSeconds: 1500,
            pausedAccumulated: 0,
            pausedAt: nil,
            boardedDeviceID: "phone-a",
            notifyOn: .mac,
            notifyTurn: 0
        )
        let now = Date(timeIntervalSince1970: TimeInterval(1_768_000_000))
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: true, now: now).isEmpty)
        snap.notifyOn = .none
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: false, now: now).isEmpty)
        snap.notifyOn = nil
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: false, now: now).isEmpty)
        snap.notifyOn = .iphone
        #expect(CompanionOffscreenNotify.requests(snap: snap, pipVisible: false, now: now).isEmpty)
    }

    @Test func staleSnapAndAFireOnSaturdayDoNotAskMacToPost() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let friday = moment(2024, 1, 12, 23, 50, calendar: calendar)
        var snap = SnapPlaintext(
            rev: 1,
            sessionId: UUID(uuidString: "11111111-1111-4111-8111-111111111111"),
            ticketId: nil,
            title: "週次レポート",
            phase: .running,
            startedAt: Int(friday.timeIntervalSince1970),
            estimatedSeconds: 5 * 60,
            pausedAccumulated: 0,
            pausedAt: nil,
            boardedDeviceID: "phone-a",
            notifyOn: .mac,
            notifyTurn: 0
        )
        let fresh = CompanionOffscreenNotify.requests(
            snap: snap,
            pipVisible: false,
            now: friday,
            snapAt: friday,
            calendar: calendar
        )
        #expect(fresh.map(\.identifier) == [MacOffscreenPlanning.overtimeID])
        let stale = CompanionOffscreenNotify.requests(
            snap: snap,
            pipVisible: false,
            now: friday.addingTimeInterval(MacOffscreenPlanning.snapStaleAfter + 1),
            snapAt: friday,
            calendar: calendar
        )
        #expect(stale.isEmpty)
        let armed: Set<String> = [MacOffscreenPlanning.overtimeID]
        #expect(MacOffscreenPlanning.identifiersToClear(armed: armed, requests: stale) == armed)

        snap.estimatedSeconds = 30 * 60
        let saturday = CompanionOffscreenNotify.requests(
            snap: snap,
            pipVisible: false,
            now: friday,
            snapAt: friday,
            calendar: calendar
        )
        #expect(saturday.isEmpty)
    }

    private func moment(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.timeZone = calendar.timeZone
        return calendar.date(from: parts)!
    }
}
