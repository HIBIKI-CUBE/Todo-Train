//
//  SessionManagerPunctualityTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerPunctualityTests {
    @Test func arrive_onTime_enqueuesPunctualityMoment() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()

        let moment = try #require(manager.punctualityMoment)
        #expect(manager.punctualityHapticTick == 0)
        #expect(
            moment.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 600,
                actualSeconds: 560,
                punctuality: .onTime,
                tagNames: [],
                colorHex: nil
            )
        )
    }

    @Test func arrive_early_enqueuesArrivalMoment() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 10)
        try manager.arrive()

        let moment = try #require(manager.punctualityMoment)
        #expect(manager.punctualityHapticTick == 0)
        #expect(
            moment.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 600,
                actualSeconds: 10,
                punctuality: .early,
                tagNames: [],
                colorHex: nil
            )
        )
    }

    @Test func arrive_overtime_enqueuesArrivalMoment() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 120)

        try manager.board(ticket: ticket)
        clock.advance(by: 180)
        try manager.arrive(resolution: .justFinished)

        let moment = try #require(manager.punctualityMoment)
        #expect(
            moment.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 120,
                actualSeconds: 180,
                punctuality: .late,
                tagNames: [],
                colorHex: nil
            )
        )
    }

    @Test func endService_onTimeArrivals_enqueuesServiceMoment() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()
        manager.consumePunctualityMoment()
        #expect(manager.punctualityMoment == nil)

        try manager.endService()
        let moment = try #require(manager.punctualityMoment)
        #expect(moment.kind == .onTimeService)
        #expect(manager.punctualityHapticTick == 1)
    }

    @Test func endService_withoutArrivals_doesNotEnqueueServiceMoment() throws {
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        try manager.endService()
        #expect(manager.punctualityMoment == nil)
        #expect(manager.punctualityHapticTick == 0)
    }

    @Test func endService_withEarlyArrival_enqueuesServiceMoment() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 10)
        try manager.arrive()
        manager.consumePunctualityMoment()

        try manager.endService()
        let moment = try #require(manager.punctualityMoment)
        #expect(moment.kind == .onTimeService)
    }

    @Test func endService_withOvertimeArrival_doesNotEnqueueServiceMoment() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 120)

        try manager.board(ticket: ticket)
        clock.advance(by: 180)
        try manager.arrive(resolution: .justFinished)
        manager.consumePunctualityMoment()

        try manager.endService()
        #expect(manager.punctualityMoment == nil)
    }

    @Test func consumePunctualityMoment_doesNotTickHaptic() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()
        // Arrival joy is gesture-owned; enqueue must not fire success haptic.
        #expect(manager.punctualityHapticTick == 0)

        manager.consumePunctualityMoment()
        #expect(manager.punctualityMoment == nil)
        #expect(manager.punctualityHapticTick == 0)
        manager.consumePunctualityMoment()
        #expect(manager.punctualityHapticTick == 0)
    }

    @Test func arriveThenEndService_queuesArrivalThenService() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()
        try manager.endService()

        #expect(manager.punctualityQueue.count == 2)
        #expect(
            manager.punctualityMoment?.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 600,
                actualSeconds: 560,
                punctuality: .onTime,
                tagNames: [],
                colorHex: nil
            )
        )
        manager.consumePunctualityMoment()
        #expect(manager.punctualityMoment?.kind == .onTimeService)
    }

    @Test func arrive_taggedTicket_carriesWinningStockColor() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let work = Tag(name: "仕事", colorHex: "#0091FF", sortOrder: 0)
        let home = Tag(name: "家", colorHex: "#30A46C", sortOrder: 1)
        context.insert(work)
        context.insert(home)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 600)
        ticket.tags = [home, work]
        try context.save()

        try manager.board(ticket: ticket)
        clock.advance(by: 560)
        try manager.arrive()

        let moment = try #require(manager.punctualityMoment)
        #expect(
            moment.kind == .arrival(
                title: ticket.title,
                estimateSeconds: 600,
                actualSeconds: 560,
                punctuality: .onTime,
                tagNames: ["仕事", "家"],
                colorHex: "#0091FF"
            )
        )
    }
}
