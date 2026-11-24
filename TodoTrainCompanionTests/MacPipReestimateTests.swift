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
    private let now = Date(timeIntervalSince1970: 1_768_000_120)

    @Test func adjustCommandUsesPositionReportOnMacPip() throws {
        let progress = MacPipReestimate.progressAnswers[1]
        let command = try #require(make(.adjust(progress: progress), active: 600, stage: .checkIn))
        #expect(command.op == .reestimate)
        #expect(command.mode == .positionReport)
        #expect(command.trigger == .checkIn)
        #expect(command.surface == .macPip)
        #expect(command.input == .click)
        #expect(command.progressAnswer == 0.5)
        #expect(command.committedRemainingSeconds == 600)
        #expect(command.promptId == MacPipReestimate.positionPromptID)
        #expect(command.sessionId == sessionID)
        let object = try json(command)
        #expect(object["surface"] as? String == "macPip")
        #expect(object["input"] as? String == "click")
        #expect(object["mode"] as? String == "positionReport")
        #expect(object["trigger"] as? String == "checkIn")
        #expect(object["heldBy"] == nil)
        #expect(object["choice"] == nil)
    }

    @Test func recoveryCommandKeepsTheSnapRemaining() throws {
        let progress = MacPipReestimate.progressAnswers[0]
        let remaining = 540
        let command = try #require(
            make(.recovery(progress: progress, committedRemainingSeconds: remaining), active: 900, stage: .checkIn)
        )
        #expect(command.mode == .positionReport)
        #expect(command.progressAnswer == 0.3)
        #expect(command.committedRemainingSeconds == remaining)
        #expect(command.promptId == MacPipReestimate.positionPromptID)
    }

    @Test func progressTriggerFollowsTheQuestion() throws {
        let ratio = MacPipReestimate.progressAnswers[0]
        let checkIn = try #require(make(.adjust(progress: ratio), active: 900, stage: .checkIn))
        #expect(checkIn.trigger == .checkIn)
        #expect(checkIn.committedRemainingSeconds == 2_100)

        let estimate = try #require(make(.adjust(progress: ratio), active: 900, stage: .estimate))
        #expect(estimate.trigger == .planEnd)

        let handoff = try #require(
            make(.adjust(progress: MacPipReestimate.progressAnswers[2]), active: 600, stage: .handoff3)
        )
        #expect(handoff.trigger == .planEnd)
        #expect(handoff.progressAnswer == 0.8)
        #expect(handoff.committedRemainingSeconds == 150)
    }

    @Test func declareLabelsShowRecoveryBeforeOriginalArrival() {
        let progress = 0.5
        let labels = MacPipReestimate.declareLabels(
            progress: progress,
            activeSeconds: 21 * 60,
            plannedBudgetSeconds: 30 * 60,
            remainingSeconds: 9 * 60,
            now: now
        )
        #expect(labels?.showsRecovery == true)
        #expect(labels?.recoveryCaption == PipPositionWording.recoveryCaption(arrival: now.addingTimeInterval(9 * 60)))
        #expect(
            labels?.adjustCaption
                == PipPositionWording.adjustCaption(
                    arrival: PositionReport.projectedArrival(now: now, activeSeconds: 21 * 60, progress: progress)!
                )
        )
    }

    @Test func declareLabelsHideRecoveryAfterOriginalArrival() {
        let labels = MacPipReestimate.declareLabels(
            progress: 0.5,
            activeSeconds: 31 * 60,
            plannedBudgetSeconds: 30 * 60,
            remainingSeconds: 120,
            now: now
        )
        #expect(labels?.showsRecovery == false)
        #expect(labels?.recoveryCaption == nil)
    }

    @Test func refusesProgressWithoutARunningSecond() {
        #expect(make(.adjust(progress: 0.5), active: 0, stage: .checkIn) == nil)
        #expect(make(.adjust(progress: 0.4), active: 600, stage: .checkIn) == nil)
        #expect(make(.recovery(progress: 0.5, committedRemainingSeconds: 0), active: 600, stage: .checkIn) == nil)
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
            ("pip-band-declare", .declare),
        ]
        for (name, band) in bands {
            let progress = band == .declare ? 0.5 : nil
            let renderer = ImageRenderer(content: rideReestimatePreview(band, progress: progress))
            renderer.scale = scale
            renderer.isOpaque = true
            let image = try #require(renderer.nsImage)
            let rep = try #require(bitmap(image))
            #expect(rep.pixelsWide == Int(card.width * scale))
            #expect(rep.pixelsHigh == Int(card.height * scale))
            let png = try #require(rep.representation(using: .png, properties: [:]))
            if ProcessInfo.processInfo.environment["PIP_BAND_STDOUT"] == "1" {
                print("PIP_BAND_PNG:\(name):\(png.base64EncodedString())")
            }
            if let staging = Self.pipBandScreenshotDirectory {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let url = staging.appendingPathComponent("\(name).png")
                try png.write(to: url, options: .atomic)
            }
        }
    }

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var pipBandScreenshotDirectory: URL? {
        guard let raw = ProcessInfo.processInfo.environment["PIP_BAND_DIR"], !raw.isEmpty else { return nil }
        let expanded = raw.replacingOccurrences(of: "$(SRCROOT)", with: projectRoot.path())
        return URL(fileURLWithPath: expanded, isDirectory: true)
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