//
//  ArrivalPraiseTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

struct ArrivalPraiseTests {
    @Test func plainArrivalDoesNotPraise() {
        let praise = ArrivalPraise.plain
        #expect(praise.count == 0)
        #expect(praise.spread == .none)
        #expect(praise.innerRingSolid == false)
        #expect(praise.ink == .arrival)
    }

    @Test func oneGoodLightsTheStampOnly() {
        let onTime = ArrivalPraise(
            punctuality: .onTime,
            alreadyDone: false,
            nextWasReserved: false,
            continuedFromStamp: false
        )
        #expect(onTime.count == 1)
        #expect(onTime.spread == .stamp)
        #expect(onTime.ink == .onTime)

        let reservedLate = ArrivalPraise(
            punctuality: .late,
            alreadyDone: false,
            nextWasReserved: true,
            continuedFromStamp: false
        )
        #expect(reservedLate.count == 1)
        #expect(reservedLate.spread == .stamp)
        #expect(reservedLate.ink == .arrival)
    }

    @Test func twoGoodsFillThePaper() {
        let praise = ArrivalPraise(
            punctuality: .early,
            alreadyDone: false,
            nextWasReserved: true,
            continuedFromStamp: false
        )
        #expect(praise.count == 2)
        #expect(praise.spread == .paper)
        #expect(praise.innerRingSolid == false)
        #expect(praise.ink == .early)
    }

    @Test func threeGoodsSolidifyTheInnerRing() {
        let praise = ArrivalPraise(
            punctuality: .onTime,
            alreadyDone: false,
            nextWasReserved: true,
            continuedFromStamp: true
        )
        #expect(praise.count == 3)
        #expect(praise.spread == .paper)
        #expect(praise.innerRingSolid == true)
    }

    @Test func alreadyDoneIsItsOwnGoodAndNotAnEstimateMatch() {
        let praise = ArrivalPraise(
            punctuality: .late,
            alreadyDone: true,
            nextWasReserved: false,
            continuedFromStamp: false
        )
        #expect(praise.count == 1)
        #expect(praise.ink == .arrival)
    }
}
