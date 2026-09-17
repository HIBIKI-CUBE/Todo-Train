//
//  ServiceCabinSequenceTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct ServiceCabinSequenceTests {
    @Test func lamp_holdsDarkBeforeFirstLight() {
        #expect(ServiceCabinSequence.lamp(elapsed: 0, reduceMotion: false) == .dark)
        #expect(
            ServiceCabinSequence.lamp(
                elapsed: ServiceCabinSequence.darkHoldSeconds - 0.01,
                reduceMotion: false
            ) == .dark
        )
    }

    @Test func lamp_stepsThroughBootsAfterHold() {
        let hold = ServiceCabinSequence.darkHoldSeconds
        let step = ServiceCabinSequence.stepSeconds
        #expect(ServiceCabinSequence.lamp(elapsed: hold, reduceMotion: false) == .lamp)
        #expect(ServiceCabinSequence.lamp(elapsed: hold + step, reduceMotion: false) == .occupancy)
        #expect(ServiceCabinSequence.lamp(elapsed: hold + step * 2, reduceMotion: false) == .phosphor)
        #expect(ServiceCabinSequence.lamp(elapsed: hold + step * 3, reduceMotion: false) == .boardReady)
        #expect(ServiceCabinSequence.lamp(elapsed: hold + step * 4, reduceMotion: false) == .circuits)
        #expect(ServiceCabinSequence.lamp(elapsed: hold + step * 40, reduceMotion: false) == .circuits)
    }

    @Test func lamp_reduceMotionJumpsToCircuits() {
        #expect(ServiceCabinSequence.lamp(elapsed: 0, reduceMotion: true) == .circuits)
    }

    @Test func shutdown_reversesLamps() {
        let step = ServiceCabinSequence.stepSeconds
        #expect(ServiceCabinSequence.shutdownLamp(elapsed: 0, reduceMotion: false) == .circuits)
        #expect(ServiceCabinSequence.shutdownLamp(elapsed: step, reduceMotion: false) == .boardReady)
        #expect(ServiceCabinSequence.shutdownLamp(elapsed: step * 5, reduceMotion: false) == .dark)
        #expect(ServiceCabinSequence.shutdownLamp(elapsed: 0, reduceMotion: true) == .dark)
    }
}

@MainActor
struct ServiceCabinExtensionTests {
    @Test func unlabeledExtensions_skipsFilledReasons() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        try manager.extend(by: 300, reason: nil)
        try manager.extend(by: 180, reason: "仕事が膨らんだ")

        let session = try #require(manager.activeSession)
        let unlabeled = ServiceCabinSequence.unlabeledExtensions(in: [session])
        #expect(unlabeled.count == 1)
        #expect(unlabeled.first?.addedSeconds == 300)
    }

    @Test func setExtensionReason_writesAfterTheRide() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context)
        try manager.board(ticket: ticket)
        try manager.extend(by: 300)

        let session = try #require(manager.activeSession)
        let unlabeled = try #require(ServiceCabinSequence.unlabeledExtensions(in: [session]).first)
        manager.setExtensionReason("割り込みが入った", on: unlabeled)
        #expect(unlabeled.reason == "割り込みが入った")
        #expect(ServiceCabinSequence.unlabeledExtensions(in: [session]).isEmpty)
    }
}
