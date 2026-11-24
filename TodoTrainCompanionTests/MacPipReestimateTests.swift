import AppKit
import Foundation
import SwiftUI
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

struct MacPipReestimateTests {
    private let sessionID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let commandID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let build = WireBuildInfo(sha: "abc", dirty: false, schema: "7", builtAt: "2026-11-25T00:00:00Z")

    @Test func progressCommandUsesClickOnMacPip() throws {
        let ratio = MacPipReestimate.progressAnswers[1]
        let command = try #require(make(.progress(ratio), active: 600, stage: .checkIn))
        #expect(command.op == .reestimate)
        #expect(command.mode == .progress)
        #expect(command.trigger == .checkIn)
        #expect(command.surface == .macPip)
        #expect(command.input == .click)
        #expect(command.progressAnswer == 0.5)
        #expect(command.committedRemainingSeconds == 600)
        #expect(command.promptId == MacPipReestimate.progressPromptID)
        #expect(command.sessionId == sessionID)
        let object = try json(command)
        #expect(object["surface"] as? String == "macPip")
        #expect(object["input"] as? String == "click")
        #expect(object["mode"] as? String == "progress")
        #expect(object["trigger"] as? String == "checkIn")
        #expect(object["heldBy"] == nil)
        #expect(object["choice"] == nil)
    }

    @Test func progressTriggerFollowsTheQuestion() throws {
        let ratio = MacPipReestimate.progressAnswers[0]
        let checkIn = try #require(make(.progress(ratio), active: 900, stage: .checkIn))
        #expect(checkIn.trigger == .checkIn)
        #expect(checkIn.committedRemainingSeconds == 2_100)

        let estimate = try #require(make(.progress(ratio), active: 900, stage: .estimate))
        #expect(estimate.trigger == .planEnd)

        let handoff = try #require(make(.progress(MacPipReestimate.progressAnswers[2]), active: 600, stage: .handoff3))
        #expect(handoff.trigger == .planEnd)
        #expect(handoff.progressAnswer == 0.8)
        #expect(handoff.committedRemainingSeconds == 150)
    }

    @Test func minutesCommandOmitsTheProgressAnswer() throws {
        let command = try #require(make(.minutes(15), active: 0, stage: nil))
        #expect(command.op == .reestimate)
        #expect(command.mode == .minutesOnly)
        #expect(command.trigger == .manual)
        #expect(command.surface == .macPip)
        #expect(command.input == .click)
        #expect(command.progressAnswer == nil)
        #expect(command.committedRemainingSeconds == 900)
        #expect(command.promptId == MacPipReestimate.minutesPromptID)
        let object = try json(command)
        #expect(object["progressAnswer"] == nil)
        #expect(object["mode"] as? String == "minutesOnly")
        #expect(object["committedRemainingSeconds"] as? Int == 900)
        #expect(object["surface"] as? String == "macPip")
        #expect(object["input"] as? String == "click")
    }

    @Test func eachMinuteStopBecomesRemainingSeconds() throws {
        for minutes in MacPipReestimate.minuteAnswers {
            let command = try #require(make(.minutes(minutes), active: 10, stage: .approach))
            #expect(command.committedRemainingSeconds == minutes * 60)
            #expect(command.mode == .minutesOnly)
            #expect(command.trigger == .manual)
            #expect(command.progressAnswer == nil)
        }
    }

    @Test func refusesProgressWithoutARunningSecond() {
        #expect(make(.progress(0.5), active: 0, stage: .checkIn) == nil)
        #expect(make(.progress(0.4), active: 600, stage: .checkIn) == nil)
        #expect(make(.minutes(10), active: 600, stage: .checkIn) == nil)
    }

    @Test func undoCommandCarriesOnlyTheSession() throws {
        let command = MacPipReestimate.undoCommand(
            id: commandID,
            sessionId: sessionID,
            at: 1_768_002_010,
            build: build,
            contract: ContractVersion.contract,
            minReadable: ContractVersion.minReadable
        )
        #expect(command.op == .undoReestimate)
        #expect(command.sessionId == sessionID)
        #expect(command.at == 1_768_002_010)
        #expect(command.mode == nil)
        #expect(command.trigger == nil)
        #expect(command.surface == nil)
        #expect(command.input == nil)
        #expect(command.progressAnswer == nil)
        #expect(command.committedRemainingSeconds == nil)
        #expect(command.promptId == nil)
        let object = try json(command)
        #expect(object["op"] as? String == "undoReestimate")
        #expect(object["mode"] == nil)
        #expect(object["surface"] == nil)
        #expect(object["input"] == nil)
        #expect(object["progressAnswer"] == nil)
    }

    @Test func triggerTable() {
        #expect(MacPipReestimate.trigger(for: .checkIn) == .checkIn)
        #expect(MacPipReestimate.trigger(for: .estimate) == .planEnd)
        #expect(MacPipReestimate.trigger(for: .handoff1) == .planEnd)
        #expect(MacPipReestimate.trigger(for: .handoff2) == .planEnd)
        #expect(MacPipReestimate.trigger(for: .approach) == .manual)
        #expect(MacPipReestimate.trigger(for: .gap1) == .manual)
        #expect(MacPipReestimate.trigger(for: nil) == .manual)
    }

    @MainActor
    @Test func rendersThreeBands() throws {
        let scale: CGFloat = 2
        let card = RideOverlayGeometry.cardSize
        let bands: [(String, PipReestimateBand)] = [
            ("pip-band-answers", .answers),
            ("pip-band-progress", .progress),
            ("pip-band-minutes", .minutes),
        ]
        for (name, band) in bands {
            let renderer = ImageRenderer(content: rideReestimatePreview(band))
            renderer.scale = scale
            renderer.isOpaque = true
            let image = try #require(renderer.nsImage)
            let rep = try #require(bitmap(image))
            #expect(rep.pixelsWide == Int(card.width * scale))
            #expect(rep.pixelsHigh == Int(card.height * scale))
            if let dir = ProcessInfo.processInfo.environment["PIP_BAND_DIR"], !dir.isEmpty {
                let png = try #require(rep.representation(using: .png, properties: [:]))
                let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("\(name).png")
                try png.write(to: url)
            }
        }
    }

    private func make(
        _ choice: MacPipReestimateChoice,
        active: TimeInterval,
        stage: NudgeStageWire?
    ) -> CommandPlaintext? {
        MacPipReestimate.command(
            id: commandID,
            sessionId: sessionID,
            at: 1_768_002_000,
            activeSeconds: active,
            nudgeStage: stage,
            choice: choice,
            build: build,
            contract: ContractVersion.contract,
            minReadable: ContractVersion.minReadable
        )
    }

    private func json(_ command: CommandPlaintext) throws -> [String: Any] {
        let data = try JSONEncoder().encode(command)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
}
