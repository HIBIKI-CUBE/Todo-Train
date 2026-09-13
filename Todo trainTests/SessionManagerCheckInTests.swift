//
//  SessionManagerCheckInTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct SessionManagerCheckInTests {
    @Test func board_shortTrip_schedulesNoProgressCheckIns() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 10 * 60)
        try manager.board(ticket: ticket)
        #expect(manager.activeSession?.checkInOffsets.isEmpty == true)
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func board_thirtyMinutes_schedulesTwoProgressCheckIns() throws {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offsets = manager.activeSession?.checkInOffsets ?? []
        #expect(offsets.count == 2)
        #expect(offsets[0] < offsets[1])
    }

    @Test func reconcile_firesProgressCheckIn_whenElapsedPassesOffset() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)

        clock.advance(by: max(offset - 1, 0))
        manager.reconcile()
        #expect(manager.pendingCheckIn == nil)

        clock.advance(by: 2)
        manager.reconcile()
        #expect(manager.activeSession?.checkInOffsetSeconds.isEmpty == false)
        #expect(manager.pendingCheckIn == .progress)
        #expect(manager.checkInPromptLine.contains("A"))
    }

    @Test func pause_doesNotFireProgressCheckIn() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        try manager.pause()
        clock.advance(by: offset + 60)
        manager.reconcile()
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.phase == .paused)
    }

    @Test func overtime_clearsPendingCheckIn_andDoesNotRestack() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 15 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)

        clock.advance(by: 15 * 60)
        manager.reconcile()
        #expect(manager.phase == .overtime)
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func answerCheckIn_stillOnIt_clearsPending() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        try manager.answerCheckIn(.stillOnIt)
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.activeSession?.checkInFiredCount == 1)
        #expect(manager.activeSession?.checkInAnswers.count == 1)
        #expect(manager.phase == .running)
    }

    @Test func acknowledgeCabinStill_consumesPendingProgress() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == .progress)
        manager.acknowledgeCabinStill()
        #expect(manager.pendingCheckIn == nil)
        #expect(manager.activeSession?.checkInFiredCount == 1)
    }

    @Test func acknowledgeCabinStill_consumesDueWithoutPending() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = try #require(manager.activeSession?.checkInOffsets.first)
        clock.advance(by: offset + 1)
        #expect(manager.pendingCheckIn == nil)
        manager.acknowledgeCabinStill()
        #expect(manager.activeSession?.checkInFiredCount == 1)
        manager.reconcile()
        #expect(manager.pendingCheckIn == nil)
    }

    @Test func idleCabin_firesWhenServiceOpenWithoutRide() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness(checkInNotifier: checkIns)
        try manager.startService()
        let day = try #require(manager.activeServiceDay)
        #expect(day.pendingCabin == nil)
        #expect(!checkIns.idle.isEmpty)
        let delay = try #require(CabinIdleScheduling.delay(firedCount: 0, seed: day.id))
        clock.advance(by: delay + 1)
        manager.reconcile()
        #expect(day.pendingCabin == .idle)
        let snap = CompanionSnapBuilding.idle(
            rev: 1,
            serviceActive: true,
            cabinEnabled: true,
            pendingCabin: day.pendingCabin?.cabin
        )
        #expect(snap.pendingCabin == .idle)
        #expect(snap.checkInFiredCount == 0)
        manager.reconcile()
        #expect(day.pendingCabin == .idle)
        #expect(checkIns.idle.count == 1)
    }

    @Test func idleCabin_doesNotFireDuringRide() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let day = try #require(manager.activeServiceDay)
        let delay = try #require(CabinIdleScheduling.delay(firedCount: 0, seed: day.id))
        clock.advance(by: delay + 1)
        manager.reconcile()
        #expect(day.pendingCabin != .idle)
        #expect(manager.pendingCheckIn != .idle)
    }

    @Test func board_clearsPendingIdle() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let day = try #require(manager.activeServiceDay)
        let delay = try #require(CabinIdleScheduling.delay(firedCount: 0, seed: day.id))
        clock.advance(by: delay + 1)
        manager.reconcile()
        #expect(day.pendingCabin == .idle)
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 5 * 60)
        try manager.board(ticket: ticket)
        #expect(day.pendingCabin == nil)
    }

    @Test func acknowledgeCabinStill_consumesIdleWithoutSession() throws {
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let day = try #require(manager.activeServiceDay)
        let delay = try #require(CabinIdleScheduling.delay(firedCount: 0, seed: day.id))
        clock.advance(by: delay + 1)
        manager.reconcile()
        #expect(day.pendingCabin == .idle)
        manager.acknowledgeCabinStill()
        #expect(day.pendingCabin == nil)
        #expect(day.cabinIdleFiredCount == 1)
    }

    @Test func acknowledgeCabinStill_idleAlreadyConsumedIsNoOp() throws {
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let day = try #require(manager.activeServiceDay)
        let delay = try #require(CabinIdleScheduling.delay(firedCount: 0, seed: day.id))
        clock.advance(by: delay + 1)
        manager.reconcile()
        manager.acknowledgeCabinStill()
        manager.acknowledgeCabinStill()
        #expect(day.cabinIdleFiredCount == 1)
        #expect(day.pendingCabin == nil)
    }

    @Test func idleCabin_schedulesSecondAfterStill() throws {
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness()
        try manager.startService()
        let day = try #require(manager.activeServiceDay)
        let first = try #require(CabinIdleScheduling.delay(firedCount: 0, seed: day.id))
        clock.advance(by: first + 1)
        manager.reconcile()
        manager.acknowledgeCabinStill()
        #expect(day.cabinIdleFiredCount == 1)
        let second = try #require(CabinIdleScheduling.delay(firedCount: 1, seed: day.id))
        clock.advance(by: second + 1)
        manager.reconcile()
        #expect(day.pendingCabin == .idle)
        manager.acknowledgeCabinStill()
        #expect(day.cabinIdleFiredCount == 2)
        clock.advance(by: 40 * 60)
        manager.reconcile()
        #expect(day.pendingCabin == nil)
    }

    @Test func pairedCompanion_stillSchedulesIdleNotifications() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, _, _, _) = try SessionManagerFixtures.makeHarness(checkInNotifier: checkIns)
        manager.suppressProgressLocalNotifications = true
        try manager.startService()
        #expect(!checkIns.idle.isEmpty)
    }

    @Test func cabinAnnouncementsOff_doesNotFireIdle() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, _, clock, _) = try SessionManagerFixtures.makeHarness(
            cabinAnnouncementsEnabled: false,
            checkInNotifier: checkIns
        )
        try manager.startService()
        let day = try #require(manager.activeServiceDay)
        let delay = CabinIdleScheduling.delay(firedCount: 0, seed: day.id) ?? (20 * 60)
        clock.advance(by: delay + 1)
        manager.reconcile()
        #expect(day.pendingCabin == nil)
        #expect(checkIns.idle.isEmpty)
    }

    @Test func pairedCompanion_doesNotScheduleProgressNotifications() throws {
        let checkIns = InMemoryCheckInNotifier()
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness(checkInNotifier: checkIns)
        manager.suppressProgressLocalNotifications = true
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        #expect(checkIns.progress.isEmpty)
        manager.beginAwayWatch()
        #expect(!checkIns.away.isEmpty)
    }

    @Test func cabinAnnouncementsOff_doesNotFire() throws {
        let (manager, context, clock, _) = try SessionManagerFixtures.makeHarness(cabinAnnouncementsEnabled: false)
        try manager.startService()
        let ticket = try SessionManagerFixtures.makeTicket(context, seconds: 30 * 60)
        try manager.board(ticket: ticket)
        let offset = manager.activeSession?.checkInOffsets.first ?? 0
        clock.advance(by: max(offset, 1))
        manager.reconcile()
        #expect(manager.pendingCheckIn == nil)
    }
}
