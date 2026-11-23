//
//  OpeningPanelStateTests.swift
//  Todo trainTests
//
//  起動の段は ServiceCabinSequence の dark → test → live → ready から、
//  運行開始の盤の状態機械へ移した。
//

import AVFoundation
import CoreHaptics
import Foundation
import Testing
@testable import Todo_train

@MainActor
struct OpeningPanelStateTests {
    private let microsecond: TimeInterval = 0.000_001

    @Test func masterDoesNotTurnByItself() {
        let harness = OpeningPanelHarness()
        harness.advance(by: 5)
        #expect(!harness.state.isPowered)
        #expect(!harness.state.serviceStarted)
        #expect(harness.log.starts == 0)
        #expect(harness.state.nextAutomaticModule == nil)
    }

    @Test func keysBeforeMaster_playDullAndStayDark() {
        let harness = OpeningPanelHarness()
        harness.state.pressConfirm(.clock)
        harness.state.pressConfirm(.timetable)
        harness.state.pressConfirm(.tickets)
        harness.state.pressSequence()
        harness.state.pressDepart()
        #expect(harness.feedback.cues == [.dull, .dull, .dull, .dull, .dull])
        #expect(!harness.state.isPowered)
        #expect(!harness.state.hasDeparted)
        #expect(harness.state.confirmation(of: .clock) == .unconfirmed)
        #expect(harness.state.generation(of: .clock) == 0)
        #expect(harness.state.clockStage == .dark)
        #expect(harness.log.hubs == 0)
        harness.advance(by: 5)
        #expect(harness.state.clockStage == .dark)
        #expect(harness.log.starts == 0)
    }

    @Test func modulesConfirmInAnyOrder() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.state.pressMaster()
        harness.state.pressConfirm(.timetable)
        harness.finishTimetable()
        #expect(harness.state.confirmation(of: .timetable) == .confirmed)
        #expect(harness.state.confirmation(of: .clock) == .unconfirmed)
        #expect(harness.state.confirmation(of: .tickets) == .unconfirmed)
        #expect(!harness.state.isReady)

        harness.state.pressConfirm(.tickets)
        harness.finishTickets()
        #expect(harness.state.confirmation(of: .tickets) == .confirmed)
        #expect(harness.state.confirmation(of: .clock) == .unconfirmed)
        #expect(!harness.state.isReady)

        harness.state.pressConfirm(.clock)
        harness.state.pressConfirm(.timetable)
        harness.advance(by: OpeningPanelTiming.backlight)
        #expect(harness.state.clockStage == .digits("8"))
        #expect(harness.state.timetableStage == .fill(1))
        #expect(harness.state.confirmation(of: .tickets) == .confirmed)
        harness.finishClock()
        harness.finishTimetable()
        #expect(harness.state.isReady)
        #expect(harness.state.readyLampLit)
        #expect(harness.state.chevronsFlowing)
        #expect(!harness.state.chevronsHeldDim)
        #expect(harness.state.nextAutomaticModule == nil)
    }

    @Test func repressRestartsOnlyThatModuleAndDropsReady() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.bringToReady()
        #expect(harness.state.isReady)
        let clockGeneration = harness.state.generation(of: .clock)
        let timetableGeneration = harness.state.generation(of: .timetable)
        harness.state.pressConfirm(.clock)
        #expect(!harness.state.isReady)
        #expect(!harness.state.chevronsFlowing)
        #expect(harness.state.confirmation(of: .clock) == .confirming)
        #expect(harness.state.confirmation(of: .timetable) == .confirmed)
        #expect(harness.state.confirmation(of: .tickets) == .confirmed)
        #expect(harness.state.generation(of: .clock) == clockGeneration + 1)
        #expect(harness.state.generation(of: .timetable) == timetableGeneration)
        #expect(harness.state.clockStage == .backlight)
        #expect(harness.state.timetableStage == .drawn)
        #expect(harness.state.isLockLit(.timetable))
        #expect(!harness.state.isLockLit(.clock))
    }

    @Test func oldClockStageIsDiscardedByGeneration() {
        let harness = OpeningPanelHarness()
        harness.state.pressMaster()
        harness.state.pressConfirm(.clock)
        harness.advance(by: OpeningPanelTiming.backlight)
        harness.advance(by: OpeningPanelTiming.clockDigit)
        #expect(harness.state.clockStage == .digits("88"))
        let generation = harness.state.generation(of: .clock)
        harness.state.pressConfirm(.clock)
        #expect(harness.state.generation(of: .clock) == generation + 1)
        #expect(harness.state.clockStage == .backlight)
        harness.advance(by: OpeningPanelTiming.clockDigit)
        #expect(harness.state.clockStage == .digits("8"))
        #expect(harness.state.confirmation(of: .clock) == .confirming)
    }

    @Test func autoAdvancesClockThenTimetableThenTickets() {
        let harness = OpeningPanelHarness(ticketCount: 2)
        harness.state.pressMaster()
        harness.advanceAlmost(OpeningPanelTiming.autoWait)
        #expect(harness.state.confirmation(of: .clock) == .unconfirmed)
        #expect(harness.state.nextAutomaticModule == .clock)
        harness.advance(by: microsecond)
        #expect(harness.state.confirmation(of: .clock) == .confirming)
        #expect(harness.state.confirmation(of: .timetable) == .unconfirmed)
        #expect(harness.state.nextAutomaticModule == .timetable)

        harness.advanceAlmost(OpeningPanelTiming.autoGap)
        #expect(harness.state.confirmation(of: .timetable) == .unconfirmed)
        harness.advance(by: microsecond)
        #expect(harness.state.confirmation(of: .timetable) == .confirming)
        #expect(harness.state.confirmation(of: .tickets) == .unconfirmed)

        harness.advanceAlmost(OpeningPanelTiming.autoGap)
        harness.advance(by: microsecond)
        #expect(harness.state.confirmation(of: .tickets) == .confirming)
        #expect(harness.state.nextAutomaticModule == nil)
        #expect(!harness.state.isReady)
    }

    @Test func departBeforeReady_abortsBootAndReachesHubOnSpecDelay() {
        let harness = OpeningPanelHarness(ticketCount: 3)
        harness.state.pressMaster()
        harness.state.pressConfirm(.clock)
        harness.advance(by: OpeningPanelTiming.backlight)
        harness.advance(by: OpeningPanelTiming.clockDigit)
        #expect(harness.state.clockStage == .digits("88"))
        let frozen = harness.state.clockStage
        harness.state.pressDepart()
        #expect(harness.state.hasDeparted)
        #expect(harness.state.powerLEDCount == OpeningPanelTiming.ledCount)
        #expect(harness.feedback.cues.contains(.heavy))
        #expect(harness.feedback.cues.contains(.haptic(.depart)))
        #expect(!harness.feedback.cues.contains(.dull))
        #expect(harness.log.hubs == 0)
        harness.advance(by: 2)
        #expect(harness.state.clockStage == frozen)
        #expect(harness.state.confirmation(of: .clock) == .confirming)
        #expect(harness.state.confirmation(of: .timetable) == .unconfirmed)
        #expect(harness.state.confirmation(of: .tickets) == .unconfirmed)
        #expect(!harness.state.isReady)
        #expect(harness.log.hubs == 1)
    }

    @Test func departDuringSequence_commitsThenLeaves() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        var cutoff = 3
        harness.state.pressMaster()
        harness.state.pressSequence()
        #expect(harness.feedback.cues.contains(.dull))
        #expect(!harness.state.isSequencing)
        #expect(harness.log.commits == 0)
        #expect(cutoff == 3)

        harness.state.pressConfirm(.tickets)
        harness.finishTickets()
        harness.state.pressSequence()
        #expect(harness.state.isSequencing)
        #expect(harness.log.commits == 0)
        harness.state.pressDepart()
        #expect(harness.log.commits == 1)
        #expect(!harness.state.isSequencing)
        #expect(harness.state.hasDeparted)
        #expect(harness.log.hubs == 0)
        #expect(cutoff == 3)
        harness.advanceAlmost(OpeningPanelTiming.hubSwitch)
        #expect(harness.log.hubs == 0)
        harness.advance(by: microsecond)
        #expect(harness.log.hubs == 1)
    }

    @Test func hubSwitchMatchesTempoFormula() {
        #expect(OpeningPanelFace.allCases.count == 10)
        #expect(OpeningPanelTiming.moduleCount == 10)
        let expected = OpeningPanelTiming.tempo(260)
            + Double(OpeningPanelTiming.moduleCount) * OpeningPanelTiming.departModuleStagger
            + OpeningPanelTiming.hubTail
        #expect(abs(OpeningPanelTiming.hubSwitch - expected) < 1e-12)
    }

    @Test func departMotion_sinksBarReleasesLitLocksAndFillsChevrons() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.bringToReady()
        #expect(harness.state.isLockLit(.master))
        #expect(harness.state.isLockLit(.clock))
        #expect(harness.state.isLockLit(.timetable))
        #expect(harness.state.isLockLit(.tickets))
        harness.state.pressDepart()
        #expect(harness.state.departBarDepth == 1)
        #expect(!harness.state.isLockLit(.master))
        #expect(harness.state.isLockLit(.clock))
        #expect(harness.state.isLockLit(.timetable))
        #expect(!harness.state.readyLampLit)
        harness.advance(by: OpeningPanelTiming.departBarStep)
        #expect(harness.state.departBarDepth == 2)
        #expect(harness.state.isLockLit(.clock))
        harness.advance(by: OpeningPanelTiming.departBarStep)
        #expect(harness.state.departBarDepth == 3)
        #expect(!harness.state.isLockLit(.clock))
        #expect(harness.state.isLockLit(.timetable))
        harness.advance(by: OpeningPanelTiming.chevronLead)
        #expect(harness.state.chevronFill == 1)
        #expect(!harness.state.isLockLit(.timetable))
        #expect(!harness.state.isLockLit(.tickets))
        #expect(harness.state.powerLEDCount == OpeningPanelTiming.ledCount)
    }

    @Test func masterOff_dropsThePanelAndKeepsService() {
        var order = ["先", "次"]
        var cutoff = 3
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.state.pressMaster()
        #expect(harness.log.starts == 1)
        #expect(harness.state.serviceStarted)
        harness.state.pressConfirm(.clock)
        harness.advance(by: OpeningPanelTiming.backlight)
        #expect(harness.state.clockStage == .digits("8"))
        harness.state.pressSequence()
        #expect(!harness.state.isSequencing)
        harness.state.pressMaster()
        #expect(!harness.state.isPowered)
        #expect(harness.state.serviceStarted)
        #expect(harness.log.starts == 1)
        #expect(harness.log.commits == 0)
        #expect(harness.log.hubs == 0)
        #expect(order == ["先", "次"])
        #expect(cutoff == 3)
        #expect(harness.state.confirmation(of: .clock) == .unconfirmed)
        #expect(harness.state.clockStage == .dark)
        #expect(harness.state.timetableStage == .dark)
        #expect(harness.state.ticketsStage == .dark)
        #expect(harness.state.lampCheck == .off)
        #expect(harness.state.powerLEDCount == 0)
        #expect(!harness.state.isReady)
        harness.advance(by: 3)
        #expect(harness.state.clockStage == .dark)
        #expect(harness.state.powerLEDCount == 0)
        harness.state.pressMaster()
        #expect(harness.state.isPowered)
        #expect(harness.log.starts == 2)
        #expect(harness.state.serviceStarted)
    }

    @Test func tempoScalesMarkedGaps() {
        #expect(abs(OpeningPanelTiming.tempo(110) - 110 * 100 / 170 / 1_000) < 1e-12)
        #expect(abs(OpeningPanelTiming.tempo(70 * 0.6) - 42 * 100 / 170 / 1_000) < 1e-12)
        #expect(abs(OpeningPanelTiming.tempo(32) - 32 * 100 / 170 / 1_000) < 1e-12)
        #expect(OpeningPanelTiming.timetableDraw == 0.300)
        #expect(OpeningPanelTiming.ticketStep == 0.110)
        #expect(OpeningPanelTiming.lampCheck == 0.280)
        #expect(OpeningPanelTiming.autoWait == 0.800)
        #expect(OpeningPanelTiming.autoGap == 0.120)

        let harness = OpeningPanelHarness()
        harness.state.pressMaster()
        harness.state.pressConfirm(.clock)
        harness.advance(by: OpeningPanelTiming.backlight)
        #expect(harness.state.clockStage == .digits("8"))
        harness.advanceAlmost(OpeningPanelTiming.clockDigit)
        #expect(harness.state.clockStage == .digits("8"))
        harness.advance(by: microsecond)
        #expect(harness.state.clockStage == .digits("88"))
        #expect(harness.state.clockStage.stageNumber == 2)
    }

    @Test func bootStages_clockDigitsTimetableTicketsCheckAndPower() {
        let power = OpeningPanelHarness()
        power.state.pressMaster()
        #expect(power.state.lampCheck == .allOn)
        #expect(power.state.powerLEDCount == OpeningPanelTiming.ledCount)
        power.advance(by: OpeningPanelTiming.lampCheck)
        #expect(power.state.lampCheck == .done)
        #expect(power.state.powerLEDCount == 1)
        for expected in 2...OpeningPanelTiming.ledCount {
            power.advance(by: OpeningPanelTiming.powerLEDStep)
            #expect(power.state.powerLEDCount == expected)
        }
        #expect(!power.state.powerSettled)
        power.advance(by: OpeningPanelTiming.powerLEDSettle)
        #expect(power.state.powerSettled)
        #expect(power.state.checkStep(for: .master) == 0)
        #expect(power.state.checkIsLit(.master))
        #expect(power.state.isLockLit(.master))
        for expected in 1...OpeningPanelTiming.checkBlinkLast {
            power.advance(by: OpeningPanelTiming.checkBlink)
            #expect(power.state.checkStep(for: .master) == expected)
            #expect(power.state.checkIsLit(.master) == expected.isMultiple(of: 2))
        }
        power.advance(by: OpeningPanelTiming.checkBlink)
        #expect(power.state.checkStep(for: .master) == OpeningPanelTiming.checkBlinkLast)

        let clock = OpeningPanelHarness()
        clock.state.pressMaster()
        clock.state.pressConfirm(.clock)
        clock.advance(by: OpeningPanelTiming.backlight)
        #expect(clock.state.clockStage == .digits("8"))
        #expect(clock.state.clockStage.stageNumber == 1)
        clock.advance(by: OpeningPanelTiming.clockDigit)
        #expect(clock.state.clockStage == .digits("88"))
        clock.advance(by: OpeningPanelTiming.clockDigit)
        #expect(clock.state.clockStage == .digits("888"))
        clock.advance(by: OpeningPanelTiming.clockDigit)
        #expect(clock.state.clockStage == .digits("8888"))
        #expect(clock.state.clockStage.stageNumber == 4)
        clock.advance(by: OpeningPanelTiming.clockDigit)
        #expect(clock.state.clockStage == .blank)
        #expect(clock.state.clockStage.stageNumber == 5)
        clock.advance(by: OpeningPanelTiming.clockToLive)
        #expect(clock.state.clockStage == .live)
        #expect(clock.state.clockStage.stageNumber == 6)
        #expect(clock.state.confirmation(of: .clock) == .confirmed)
        #expect(clock.state.checkStep(for: .clock) == 0)
        #expect(clock.state.isLockLit(.clock))

        let table = OpeningPanelHarness()
        table.state.pressMaster()
        table.state.pressConfirm(.timetable)
        table.advance(by: OpeningPanelTiming.backlight)
        #expect(table.state.timetableStage == .fill(1))
        #expect(table.state.timetableStage.stageNumber == 1)
        for step in 2...OpeningPanelTiming.timetableFillCount {
            table.advance(by: OpeningPanelTiming.timetableFill)
            #expect(table.state.timetableStage == .fill(step))
        }
        table.advance(by: OpeningPanelTiming.timetableToInTest)
        #expect(table.state.timetableStage == .inTest)
        #expect(table.state.timetableStage.stageNumber == 13)
        table.advance(by: OpeningPanelTiming.timetableDraw)
        #expect(table.state.timetableStage == .drawn)
        #expect(table.state.timetableStage.stageNumber == 14)
        #expect(table.state.confirmation(of: .timetable) == .confirmed)

        let tickets = OpeningPanelHarness(ticketCount: 3)
        tickets.state.pressMaster()
        tickets.state.pressConfirm(.tickets)
        tickets.advance(by: OpeningPanelTiming.backlight)
        #expect(tickets.state.ticketsStage == .cursor(1))
        tickets.advance(by: OpeningPanelTiming.ticketCursor)
        #expect(tickets.state.ticketsStage == .cursor(2))
        tickets.advance(by: OpeningPanelTiming.ticketCursor)
        #expect(tickets.state.ticketsStage == .cursor(3))
        #expect(tickets.state.ticketsStage.stageNumber == 3)
        let beforeReveal = tickets.feedback.cues.count
        tickets.advance(by: OpeningPanelTiming.ticketAfterCursor)
        #expect(tickets.state.ticketsStage == .shown(1))
        let revealed = tickets.feedback.cues.dropFirst(beforeReveal)
        #expect(revealed.contains(.light))
        #expect(revealed.contains(.haptic(.operation)))
        tickets.advance(by: OpeningPanelTiming.ticketStep)
        #expect(tickets.state.ticketsStage == .shown(2))
        tickets.advance(by: OpeningPanelTiming.ticketStep)
        #expect(tickets.state.ticketsStage == .shown(3))
        #expect(tickets.state.confirmation(of: .tickets) == .confirmed)
        #expect(tickets.state.isLockLit(.tickets))
        #expect(tickets.state.ticketGrowthStep == 0)
    }

    @Test func fiveTickets_cursorThenRevealOneByOne() {
        let harness = OpeningPanelHarness(ticketCount: 5)
        harness.state.pressMaster()
        harness.state.pressConfirm(.tickets)
        harness.advance(by: OpeningPanelTiming.backlight)
        for step in 1...5 {
            #expect(harness.state.ticketsStage == .cursor(step))
            if step < 5 {
                harness.advance(by: OpeningPanelTiming.ticketCursor)
            }
        }
        harness.advance(by: OpeningPanelTiming.ticketAfterCursor)
        for shown in 1...5 {
            #expect(harness.state.ticketsStage == .shown(shown))
            if shown < 5 {
                harness.advance(by: OpeningPanelTiming.ticketStep)
            }
        }
        #expect(harness.state.confirmation(of: .tickets) == .confirmed)
    }

    @Test func ticketGrowth_sixStepsAfterTheLamp() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.state.pressMaster()
        harness.state.pressConfirm(.tickets)
        harness.finishTickets()
        #expect(harness.state.ticketGrowthStep == 0)
        harness.advanceAlmost(OpeningPanelTiming.ticketGrowthDelay)
        #expect(harness.state.ticketGrowthStep == 0)
        harness.advance(by: microsecond)
        #expect(harness.state.ticketGrowthStep == 1)
        for step in 2...OpeningPanelTiming.ticketGrowthSteps {
            harness.advance(by: OpeningPanelTiming.ticketGrowthStep)
            #expect(harness.state.ticketGrowthStep == step)
        }
    }

    @Test func repressTickets_restartsGrowth() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.state.pressMaster()
        harness.state.pressConfirm(.tickets)
        harness.finishTickets()
        harness.advance(by: OpeningPanelTiming.ticketGrowthDelay)
        harness.advance(by: OpeningPanelTiming.ticketGrowthStep)
        #expect(harness.state.ticketGrowthStep == 2)
        harness.state.pressConfirm(.tickets)
        #expect(harness.state.ticketGrowthStep == 0)
        #expect(harness.state.ticketsStage == .backlight)
        #expect(harness.state.confirmation(of: .tickets) == .confirming)
    }

    @Test func reduceMotion_ticketsFinishAtFullGrowth() {
        let harness = OpeningPanelHarness(ticketCount: 2, reduceMotion: true)
        harness.state.pressMaster()
        harness.state.pressConfirm(.tickets)
        harness.advance(by: OpeningPanelTiming.backlight)
        #expect(harness.state.ticketsStage == .shown(2))
        #expect(harness.state.ticketGrowthStep == OpeningPanelTiming.ticketGrowthSteps)
    }

    @Test func sequenceStaysOpenWhileTheClockRuns() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.state.pressMaster()
        harness.state.pressConfirm(.tickets)
        harness.finishTickets()
        harness.state.pressSequence()
        #expect(harness.state.isSequencing)
        #expect(harness.state.sequenceLampLit)
        #expect(harness.log.commits == 0)
        harness.advance(by: OpeningPanelTiming.sequenceQuiet + OpeningPanelTiming.sequenceBlink + 2)
        #expect(harness.state.isSequencing)
        #expect(harness.state.sequenceLampLit)
        #expect(harness.log.commits == 0)
        #expect(harness.log.abandons == 0)
    }

    @Test func sequenceRow_keepsTheLampLit() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.state.pressMaster()
        harness.state.pressConfirm(.tickets)
        harness.finishTickets()
        harness.state.pressSequence()
        let before = harness.feedback.cues.count
        harness.state.noteSequenceRow(accepted: true)
        let added = harness.feedback.cues.dropFirst(before)
        #expect(added.contains(.light))
        #expect(added.contains(.haptic(.operation)))
        harness.advance(by: 0)
        #expect(harness.state.sequenceLampLit)
        #expect(harness.state.isSequencing)
        harness.state.noteSequenceRow(accepted: false)
        #expect(harness.feedback.cues.last == .dull)
        #expect(harness.state.isSequencing)
        #expect(harness.state.sequenceLampLit)
        #expect(harness.log.commits == 0)
    }

    @Test func masterOffDuringSequence_doesNotCommit() {
        let harness = OpeningPanelHarness(ticketCount: 1)
        harness.state.pressMaster()
        harness.state.pressConfirm(.tickets)
        harness.finishTickets()
        harness.state.pressSequence()
        harness.state.pressMaster()
        #expect(!harness.state.isPowered)
        #expect(!harness.state.isSequencing)
        #expect(harness.log.commits == 0)
        #expect(harness.log.abandons == 0)
        harness.advance(by: 4)
        #expect(harness.log.commits == 0)
        #expect(harness.log.abandons == 0)
    }

    @Test func reduceMotion_skipsStagedBootsAndHoldsChevronsDim() {
        let harness = OpeningPanelHarness(ticketCount: 4, reduceMotion: true)
        harness.state.pressMaster()
        #expect(harness.state.lampCheck == .done)
        #expect(harness.state.powerLEDCount == 1)
        harness.advance(by: OpeningPanelTiming.powerLEDStep)
        #expect(harness.state.powerLEDCount == 2)

        harness.state.pressConfirm(.clock)
        harness.state.pressConfirm(.timetable)
        harness.state.pressConfirm(.tickets)
        harness.advanceAlmost(OpeningPanelTiming.backlight)
        #expect(harness.state.clockStage == .backlight)
        #expect(harness.state.timetableStage == .backlight)
        #expect(harness.state.ticketsStage == .backlight)
        harness.advance(by: microsecond)
        #expect(harness.state.clockStage == .live)
        #expect(harness.state.timetableStage == .drawn)
        #expect(harness.state.ticketsStage == .shown(4))
        #expect(harness.state.isReady)
        #expect(harness.state.chevronsHeldDim)
        #expect(!harness.state.chevronsFlowing)
        #expect(harness.state.checkStep(for: .clock) == 0)
        harness.advance(by: OpeningPanelTiming.checkBlink)
        #expect(harness.state.checkStep(for: .clock) == 1)
        #expect(!harness.state.checkIsLit(.clock))

        harness.state.pressDepart()
        #expect(harness.state.chevronsHeldDim)
        #expect(harness.state.chevronFill == 0)
        harness.advanceAlmost(OpeningPanelTiming.hubSwitch)
        #expect(harness.log.hubs == 0)
        #expect(harness.state.chevronFill == 0)
        #expect(harness.state.departBarDepth == OpeningPanelTiming.departBarSteps)
        harness.advance(by: microsecond)
        #expect(harness.log.hubs == 1)
    }

    @Test func clockBoot_holdsBlankForTempoBeforeLive() {
        #expect(abs(OpeningPanelTiming.clockDigit - OpeningPanelTiming.tempo(110)) < 1e-12)
        #expect(abs(OpeningPanelTiming.clockToLive - OpeningPanelTiming.tempo(300)) < 1e-12)

        let harness = OpeningPanelHarness()
        harness.state.pressMaster()
        harness.state.pressConfirm(.clock)
        harness.advance(by: OpeningPanelTiming.backlight)
        #expect(harness.state.clockStage == .digits("8"))
        harness.advance(by: OpeningPanelTiming.clockDigit * 4)
        #expect(harness.state.clockStage == .blank)
        #expect(harness.state.clockStage.stageNumber == 5)
        harness.advanceAlmost(OpeningPanelTiming.clockToLive)
        #expect(harness.state.clockStage == .blank)
        harness.advance(by: microsecond)
        #expect(harness.state.clockStage == .live)
        #expect(harness.state.confirmation(of: .clock) == .confirmed)
    }

    @Test func hourMode_switchesOnlyWhilePoweredAndRearmsAuto() {
        let harness = OpeningPanelHarness()
        #expect(harness.state.hourCycle == .twentyFour)
        harness.state.pressHourMode()
        #expect(harness.feedback.cues == [.dull])
        #expect(harness.state.hourCycle == .twentyFour)
        #expect(!harness.state.isPowered)
        #expect(harness.state.clockStage == .dark)

        harness.state.pressMaster()
        harness.advance(by: 0.5)
        #expect(harness.state.confirmation(of: .clock) == .unconfirmed)
        let before = harness.feedback.cues.count
        harness.state.pressHourMode()
        #expect(harness.state.hourCycle == .twelve)
        let added = Array(harness.feedback.cues.dropFirst(before))
        #expect(added.contains(.light))
        #expect(added.contains(.haptic(.operation)))
        #expect(!added.contains(.dull))

        harness.advance(by: 0.4)
        #expect(harness.state.confirmation(of: .clock) == .unconfirmed)
        harness.advance(by: 0.5)
        #expect(harness.state.confirmation(of: .clock) == .confirming)

        let generation = harness.state.generation(of: .clock)
        harness.state.pressHourMode()
        #expect(harness.state.hourCycle == .twentyFour)
        harness.state.pressHourMode()
        #expect(harness.state.hourCycle == .twelve)
        #expect(harness.state.generation(of: .clock) == generation)
        #expect(harness.state.confirmation(of: .clock) == .confirming)

        harness.state.pressMaster()
        #expect(!harness.state.isPowered)
        #expect(harness.state.hourCycle == .twelve)
        harness.state.pressHourMode()
        #expect(harness.feedback.cues.last == .dull)
        #expect(harness.state.hourCycle == .twelve)
    }

    @Test func hourMode_whileLiveDoesNotRestartClock() {
        let harness = OpeningPanelHarness()
        harness.state.pressMaster()
        harness.state.pressConfirm(.clock)
        harness.finishClock()
        #expect(harness.state.clockStage == .live)
        #expect(harness.state.confirmation(of: .clock) == .confirmed)
        let generation = harness.state.generation(of: .clock)
        harness.state.pressHourMode()
        #expect(harness.state.hourCycle == .twelve)
        #expect(harness.state.clockStage == .live)
        #expect(harness.state.confirmation(of: .clock) == .confirmed)
        #expect(harness.state.generation(of: .clock) == generation)
        #expect(!harness.state.isReady)
        harness.advance(by: 2)
        #expect(harness.state.clockStage == .live)
        #expect(harness.state.hourCycle == .twelve)

        harness.state.pressConfirm(.clock)
        #expect(harness.state.clockStage == .backlight)
        #expect(harness.state.hourCycle == .twelve)
        #expect(harness.state.confirmation(of: .clock) == .confirming)
        harness.advance(by: OpeningPanelTiming.backlight)
        #expect(harness.state.clockStage == .digits("8"))
    }

    @Test func soundRecipesAndHapticsMatchTheTable() {
        #expect(OpeningPanelSoundRecipe.light.duration == 0.025)
        #expect(OpeningPanelSoundRecipe.light.filter == .bandpass(3_200))
        #expect(OpeningPanelSoundRecipe.heavy.duration == 0.180)
        #expect(OpeningPanelSoundRecipe.heavy.filter == .lowpass(400))
        #expect(OpeningPanelSoundRecipe.heavyBass.startFrequency == 90)
        #expect(OpeningPanelSoundRecipe.heavyBass.endFrequency == 55)
        #expect(OpeningPanelSoundRecipe.dull.startFrequency == 140)
        #expect(OpeningPanelSoundRecipe.dull.duration == 0.030)

        let light = OpeningPanelSynthesis.noise(OpeningPanelSoundRecipe.light)
        #expect(light.count == OpeningPanelSynthesis.frameCount(0.025, sampleRate: OpeningPanelSoundRecipe.sampleRate))
        #expect(light.allSatisfy { abs($0) <= 1 })
        #expect(light.contains { $0 != 0 })
        let head = meanAbsolute(light.prefix(light.count / 10))
        let tail = meanAbsolute(light.suffix(light.count / 10))
        #expect(head > tail * 5)

        let bass = OpeningPanelSynthesis.tone(OpeningPanelSoundRecipe.heavyBass)
        #expect(bass.count == OpeningPanelSynthesis.frameCount(0.180, sampleRate: OpeningPanelSoundRecipe.sampleRate))
        #expect(meanAbsolute(bass.prefix(bass.count / 10)) > meanAbsolute(bass.suffix(bass.count / 10)))

        let dull = OpeningPanelSynthesis.tone(OpeningPanelSoundRecipe.dull)
        #expect(dull.count == OpeningPanelSynthesis.frameCount(0.030, sampleRate: OpeningPanelSoundRecipe.sampleRate))
        let crossings = zeroCrossings(dull)
        #expect(crossings >= 6)
        #expect(crossings <= 12)

        let buffer = OpeningPanelSynthesis.buffer(light)
        #expect(buffer?.frameLength == AVAudioFrameCount(light.count))

        let eq = AVAudioUnitEQ(numberOfBands: 1)
        OpeningPanelSoundRecipe.light.filter.apply(to: eq.bands[0])
        #expect(eq.bands[0].filterType == .bandPass)
        #expect(eq.bands[0].frequency == 3_200)
        OpeningPanelSoundRecipe.heavy.filter.apply(to: eq.bands[0])
        #expect(eq.bands[0].filterType == .lowPass)
        #expect(eq.bands[0].frequency == 400)

        #expect(OpeningPanelHapticSpec.operation.duration == 0.010)
        #expect(OpeningPanelHapticSpec.divider.duration == 0.008)
        #expect(OpeningPanelHapticSpec.depart.duration == 0.030)
        #expect(OpeningPanelHapticSpec.depart.intensity > OpeningPanelHapticSpec.operation.intensity)
        #expect(OpeningPanelHapticSpec.operation.intensity > OpeningPanelHapticSpec.divider.intensity)

        for spec in [OpeningPanelHapticSpec.operation, .divider, .depart] {
            let events = OpeningPanelHaptics.events(for: spec)
            let transient = events.contains(where: { $0.type == .hapticTransient })
            let continuous = events.first(where: { $0.type == .hapticContinuous })
            #expect(transient)
            #expect(continuous != nil)
            if let continuous {
                #expect(abs(continuous.duration - spec.duration) < 0.000_001)
            }
        }

        let sound = OpeningPanelSound()
        sound.play(.light)
        sound.play(.heavy)
        sound.play(.dull)
        sound.play(.haptic(.operation))
        sound.play(.haptic(.divider))
        sound.play(.haptic(.depart))

        let live = OpeningPanelState.live()
        #expect(!live.isPowered)
        #expect(!live.serviceStarted)
    }
}

@MainActor
private final class OpeningPanelLog {
    var starts = 0
    var commits = 0
    var abandons = 0
    var hubs = 0
}

@MainActor
private final class OpeningPanelFeedbackSpy: OpeningPanelFeedback {
    private(set) var cues: [OpeningPanelCue] = []

    func play(_ cue: OpeningPanelCue) {
        cues.append(cue)
    }
}

@MainActor
private final class OpeningPanelManualScheduler: OpeningPanelScheduling {
    private struct Item {
        var id: Int
        var due: Int64
        var action: () -> Void
    }

    private var now: Int64 = 0
    private var nextID = 0
    private var items: [Item] = []

    func schedule(after seconds: TimeInterval, execute: @escaping () -> Void) -> OpeningPanelTask {
        let id = nextID
        nextID += 1
        items.append(Item(id: id, due: now + microseconds(seconds), action: execute))
        return OpeningPanelTask { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func advance(by seconds: TimeInterval) {
        advance(to: now + microseconds(seconds))
    }

    func advanceAlmost(_ seconds: TimeInterval) {
        advance(to: now + microseconds(seconds) - 1)
    }

    private func advance(to target: Int64) {
        while true {
            guard let index = nextIndex(), items[index].due <= target else {
                now = target
                return
            }
            let item = items.remove(at: index)
            now = item.due
            item.action()
        }
    }

    private func nextIndex() -> Int? {
        items.indices.min { lhs, rhs in
            let left = items[lhs]
            let right = items[rhs]
            if left.due != right.due { return left.due < right.due }
            return left.id < right.id
        }
    }

    private func microseconds(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * 1_000_000).rounded())
    }
}

@MainActor
private final class OpeningPanelHarness {
    let scheduler: OpeningPanelManualScheduler
    let feedback: OpeningPanelFeedbackSpy
    let log: OpeningPanelLog
    let state: OpeningPanelState

    init(ticketCount: Int = 0, reduceMotion: Bool = false) {
        let scheduler = OpeningPanelManualScheduler()
        let feedback = OpeningPanelFeedbackSpy()
        let log = OpeningPanelLog()
        self.scheduler = scheduler
        self.feedback = feedback
        self.log = log
        state = OpeningPanelState(
            scheduler: scheduler,
            feedback: feedback,
            ticketCount: ticketCount,
            reduceMotion: reduceMotion,
            onStartService: { log.starts += 1 },
            onCommitSequence: { log.commits += 1 },
            onAbandonSequence: { log.abandons += 1 },
            onShowHub: { log.hubs += 1 }
        )
    }

    func advance(by seconds: TimeInterval) {
        scheduler.advance(by: seconds)
    }

    func advanceAlmost(_ seconds: TimeInterval) {
        scheduler.advanceAlmost(seconds)
    }

    func finishClock() {
        advance(by: OpeningPanelTiming.backlight)
        guard !state.reducesMotion else { return }
        for _ in 0..<4 {
            advance(by: OpeningPanelTiming.clockDigit)
        }
        advance(by: OpeningPanelTiming.clockToLive)
    }

    func finishTimetable() {
        advance(by: OpeningPanelTiming.backlight)
        guard !state.reducesMotion else { return }
        for _ in 1..<OpeningPanelTiming.timetableFillCount {
            advance(by: OpeningPanelTiming.timetableFill)
        }
        advance(by: OpeningPanelTiming.timetableToInTest)
        advance(by: OpeningPanelTiming.timetableDraw)
    }

    func finishTickets() {
        let count = state.ticketCount
        advance(by: OpeningPanelTiming.backlight)
        guard !state.reducesMotion, count > 0 else { return }
        for _ in 1..<count {
            advance(by: OpeningPanelTiming.ticketCursor)
        }
        advance(by: OpeningPanelTiming.ticketAfterCursor)
        for _ in 1..<count {
            advance(by: OpeningPanelTiming.ticketStep)
        }
    }

    func bringToReady() {
        state.pressMaster()
        state.pressConfirm(.timetable)
        finishTimetable()
        state.pressConfirm(.tickets)
        finishTickets()
        state.pressConfirm(.clock)
        finishClock()
    }
}

private func meanAbsolute(_ samples: ArraySlice<Float>) -> Float {
    guard !samples.isEmpty else { return 0 }
    return samples.reduce(Float(0)) { $0 + abs($1) } / Float(samples.count)
}

private func zeroCrossings(_ samples: [Float]) -> Int {
    var count = 0
    for index in 1..<samples.count {
        let previous = samples[index - 1]
        let current = samples[index]
        if (previous < 0 && current > 0) || (previous > 0 && current < 0) {
            count += 1
        }
    }
    return count
}
