import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Relay reconnect")
struct RelayReconnectTests {
    @Test func delayStaysInsideOneToSixtySeconds() {
        for attempt in 1...12 {
            let low = RelayReconnect.delaySeconds(attempt: attempt, unit: 0)
            let high = RelayReconnect.delaySeconds(attempt: attempt, unit: 0.999)
            #expect(low >= RelayReconnect.minimumSeconds)
            #expect(high <= RelayReconnect.maximumSeconds)
            #expect(low <= high)
        }
    }

    @Test func firstFailureWaitsOneSecond() {
        #expect(RelayReconnect.delaySeconds(attempt: 1, unit: 0) == 1)
        #expect(RelayReconnect.delaySeconds(attempt: 1, unit: 0.5) == 1)
        #expect(RelayReconnect.delaySeconds(attempt: 0, unit: 0) == 1)
    }

    @Test func laterFailuresGrowAndJitter() {
        let second = RelayReconnect.delaySeconds(attempt: 2, unit: 0)
        let secondHigh = RelayReconnect.delaySeconds(attempt: 2, unit: 0.999)
        #expect(second == 1)
        #expect(secondHigh > second)
        #expect(secondHigh <= 2)

        let third = RelayReconnect.delaySeconds(attempt: 3, unit: 0)
        #expect(third == 2)
        #expect(RelayReconnect.delaySeconds(attempt: 3, unit: 0.999) > third)

        let late = RelayReconnect.delaySeconds(attempt: 8, unit: 0)
        let lateHigh = RelayReconnect.delaySeconds(attempt: 8, unit: 0.999)
        #expect(late == 30)
        #expect(lateHigh > 59)
        #expect(lateHigh <= 60)
    }

    @Test func retryStopsAfterEightFailuresOrOneMinute() {
        #expect(RelayReconnect.shouldRetry(attempt: 1, elapsedSeconds: 0))
        #expect(RelayReconnect.shouldRetry(attempt: 7, elapsedSeconds: 59))
        #expect(!RelayReconnect.shouldRetry(attempt: 8, elapsedSeconds: 0))
        #expect(!RelayReconnect.shouldRetry(attempt: 1, elapsedSeconds: 60))
        #expect(!RelayReconnect.shouldRetry(attempt: 0, elapsedSeconds: 0))
    }

    @Test func hint401StopsAnd429Waits() {
        #expect(HintPolling.rateLimit(401) == .stop)
        #expect(HintPolling.rateLimit(429) == .wait)
        #expect(HintPolling.rateLimit(500) == .again)
        #expect(HintPolling.rateLimit(200) == .again)
    }
}

@Suite("Relay radio")
struct RelayRadioTests {
    let zone = RelayRadio.utc
    let now = 1_700_000_000

    private func input(
        snapAge: Int? = nil,
        retryAge: Int? = nil,
        exhausted: Bool = false,
        acknowledged: Bool = false,
        prior: RelayRadioPhase = .quiet,
        recoveredUntil: Int? = nil,
        at: Int? = nil
    ) -> RelayRadio.Input {
        let moment = at ?? now
        return RelayRadio.Input(
            now: moment,
            snapConfirmedAt: snapAge.map { moment - $0 },
            retryingSince: retryAge.map { moment - $0 },
            exhausted: exhausted,
            acknowledged: acknowledged,
            prior: prior,
            recoveredUntil: recoveredUntil,
            timeZone: zone
        )
    }

    @Test func freshSnapStaysQuietWhileTheSocketIsDown() {
        let reading = RelayRadio.judge(input(snapAge: 14, retryAge: 50, exhausted: true)).reading
        #expect(reading.phase == .quiet)
        #expect(!reading.blinks)
    }

    @Test func staleSnapBlinksThenHoldsAmber() {
        let early = RelayRadio.judge(input(snapAge: 20, retryAge: 20)).reading
        #expect(early.phase == .reconnecting)
        #expect(early.blinks)
        #expect(!early.dimmed)

        let held = RelayRadio.judge(input(snapAge: 30, retryAge: 30)).reading
        #expect(held.phase == .reconnecting)
        #expect(!held.blinks)
    }

    @Test func minuteWithoutASnapIsOutOfContact() {
        let reading = RelayRadio.judge(input(snapAge: 60, retryAge: 20)).reading
        #expect(reading.phase == .outOfContact)
        #expect(!reading.blinks)
        #expect(reading.lastReceivedClock == RelayRadio.clock(unix: now - 60, timeZone: zone))
    }

    @Test func exhaustedOrLongRetryTurnsAStaleSnapRed() {
        let spent = RelayRadio.judge(input(snapAge: 20, retryAge: 10, exhausted: true)).reading
        #expect(spent.phase == .outOfContact)

        let long = RelayRadio.judge(input(snapAge: 20, retryAge: 60)).reading
        #expect(long.phase == .outOfContact)
    }

    @Test func acknowledgementDimsAndStopsTheBlink() {
        let reading = RelayRadio.judge(input(snapAge: 16, retryAge: 16, acknowledged: true)).reading
        #expect(reading.phase == .reconnecting)
        #expect(!reading.blinks)
        #expect(reading.dimmed)

        let red = RelayRadio.judge(input(snapAge: 60, acknowledged: true)).reading
        #expect(red.phase == .outOfContact)
        #expect(red.dimmed)
    }

    @Test func noSnapYetStaysQuietUntilTheRetryItselfIsStale() {
        #expect(RelayRadio.judge(input()).reading.phase == .quiet)
        #expect(RelayRadio.judge(input(retryAge: 10)).reading.phase == .quiet)
        let amber = RelayRadio.judge(input(retryAge: 20)).reading
        #expect(amber.phase == .reconnecting)
        #expect(amber.blinks)
    }

    @Test func recoveryIsGreenForTwoSecondsAfterOutOfContact() {
        let back = RelayRadio.judge(input(snapAge: 1, prior: .outOfContact))
        #expect(back.reading.phase == .recovered)
        #expect(back.recoveredUntil == now + RelayRadio.recoveredSeconds)
        #expect(!back.clearAcknowledged)

        let still = RelayRadio.judge(
            input(snapAge: 1, prior: .recovered, recoveredUntil: back.recoveredUntil, at: now + 1)
        )
        #expect(still.reading.phase == .recovered)

        let done = RelayRadio.judge(
            input(snapAge: 1, prior: .recovered, recoveredUntil: back.recoveredUntil, at: now + 2)
        )
        #expect(done.reading.phase == .quiet)
        #expect(done.clearAcknowledged)
    }

    @Test func amberReturningDoesNotFlashGreen() {
        let back = RelayRadio.judge(input(snapAge: 1, prior: .reconnecting))
        #expect(back.reading.phase == .quiet)
        #expect(back.clearAcknowledged)
    }

    @Test func clockIsHourAndMinute() {
        #expect(RelayRadio.clock(unix: 0, timeZone: zone) == "00:00")
        #expect(RelayRadio.clock(unix: 3_661, timeZone: zone) == "01:01")
    }

    @Test func noticeOncePerRideAndOnlyWhileRiding() {
        let session = UUID()
        #expect(RelayRadio.riding(.running))
        #expect(RelayRadio.riding(.paused))
        #expect(RelayRadio.riding(.overtime))
        #expect(!RelayRadio.riding(.idle))

        #expect(
            RelayRadio.shouldPostNotice(
                phase: .outOfContact,
                riding: true,
                session: session,
                postedFor: nil
            )
        )
        #expect(
            !RelayRadio.shouldPostNotice(
                phase: .outOfContact,
                riding: true,
                session: session,
                postedFor: session
            )
        )
        #expect(
            !RelayRadio.shouldPostNotice(
                phase: .outOfContact,
                riding: false,
                session: session,
                postedFor: nil
            )
        )
        #expect(
            !RelayRadio.shouldPostNotice(
                phase: .reconnecting,
                riding: true,
                session: session,
                postedFor: nil
            )
        )
    }
}
