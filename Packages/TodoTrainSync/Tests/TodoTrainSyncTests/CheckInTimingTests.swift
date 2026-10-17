import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Check-in timing")
struct CheckInTimingTests {
    private let ride = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func tenMinutesExactlyIsNil() {
        #expect(CheckInTiming.offset(rideID: ride, estimateSeconds: 10 * 60) == nil)
        #expect(CheckInTiming.offset(rideID: ride, estimateSeconds: 10 * 60 + 1) != nil)
    }

    @Test func elevenMinutesUsesFiveMinuteFloor() throws {
        let offset = try #require(CheckInTiming.offset(rideID: ride, estimateSeconds: 11 * 60))
        #expect(offset >= CheckInTiming.minimumRunningSeconds)
        let band = try #require(CheckInTiming.fractionBandRange(estimateSeconds: 11 * 60))
        #expect(offset >= max(band.lowerBound, CheckInTiming.minimumRunningSeconds))
        #expect(offset <= max(band.upperBound, CheckInTiming.minimumRunningSeconds))
    }

    @Test func fractionEndpoints() throws {
        let estimate = 30 * 60
        let lowRide = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highRide = UUID(uuidString: "00000000-0000-0000-0000-0000000000ff")!
        let low = try #require(CheckInTiming.offset(rideID: lowRide, estimateSeconds: estimate))
        let high = try #require(CheckInTiming.offset(rideID: highRide, estimateSeconds: estimate))
        let band = try #require(CheckInTiming.fractionBandRange(estimateSeconds: estimate))
        #expect(low >= max(band.lowerBound, CheckInTiming.minimumRunningSeconds))
        #expect(high <= max(band.upperBound, CheckInTiming.minimumRunningSeconds))
    }

    @Test func sameRideIsStable() {
        let first = CheckInTiming.offset(rideID: ride, estimateSeconds: 30 * 60)
        let again = CheckInTiming.offset(rideID: ride, estimateSeconds: 30 * 60)
        #expect(first == again)
    }

    @Test func differentRidesSpreadInsideBand() throws {
        let estimate = 30 * 60
        let offsets = (0..<24).map { index in
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index))!
            return CheckInTiming.offset(rideID: id, estimateSeconds: estimate)
        }
        let band = try #require(CheckInTiming.fractionBandRange(estimateSeconds: estimate))
        let floor = CheckInTiming.minimumRunningSeconds
        #expect(offsets.allSatisfy { offset in
            guard let offset else { return false }
            return offset >= max(band.lowerBound, floor) && offset <= max(band.upperBound, floor)
        })
        #expect(Set(offsets).count > 1)
    }
}
