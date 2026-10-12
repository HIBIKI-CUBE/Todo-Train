import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Watch link")
struct WatchLinkTests {
    @Test func contextRoundTripKeepsTitleAndRemaining() throws {
        let snap = try runningSnap(title: "週次レポート", rev: 7)
        let context = try WatchLink.context(for: snap)
        var mirror = WatchMirror()
        mirror.receive(context)
        #expect(mirror.title == "週次レポート")
        #expect(mirror.remainingSeconds(at: 1_768_000_060) == 1440)
        #expect(mirror.replyGate == .open)
    }

    @Test func laterContextReplacesTitleAndRemaining() throws {
        var mirror = WatchMirror()
        mirror.receive(try WatchLink.context(for: runningSnap(title: "週次レポート", rev: 1)))
        #expect(mirror.title == "週次レポート")
        #expect(mirror.remainingSeconds(at: 1_768_000_060) == 1440)

        var next = try runningSnap(title: "続きのメモ", rev: 2)
        next.estimatedSeconds = 600
        mirror.receive(try WatchLink.context(for: next))
        #expect(mirror.title == "続きのメモ")
        #expect(mirror.remainingSeconds(at: 1_768_000_060) == 540)
        #expect(mirror.replyGate == .open)
    }

    @Test func reachableInRangeUsesSendMessage() throws {
        let plan = WatchLink.plan(
            command: sampleCommand(),
            reachable: true,
            peer: .current
        )
        #expect(plan.channel == .sendMessage)
        let body = try #require(plan.body)
        let decoded = try #require(WatchLink.command(from: WatchLink.message(body: body)))
        #expect(decoded == sampleCommand())
    }

    @Test func unreachableInRangeUsesTransferUserInfo() throws {
        let plan = WatchLink.plan(
            command: sampleCommand(),
            reachable: false,
            peer: .current
        )
        #expect(plan.channel == .transferUserInfo)
        #expect(plan.body != nil)
    }

    @Test func peerTooOldDoesNotSend() {
        let peer = ContractAnnouncement(contract: 2, minReadable: 2)
        let reachable = WatchLink.plan(command: sampleCommand(), reachable: true, peer: peer)
        let queued = WatchLink.plan(command: sampleCommand(), reachable: false, peer: peer)
        #expect(reachable.channel == .displayOnly)
        #expect(reachable.body == nil)
        #expect(queued.channel == .displayOnly)
        #expect(queued.body == nil)
        #expect(WatchLink.maySendReply(peer: peer) == false)
    }

    @Test func selfTooOldDoesNotSend() {
        let peer = ContractAnnouncement(
            contract: ContractVersion.contract,
            minReadable: ContractVersion.contract + 1
        )
        let plan = WatchLink.plan(command: sampleCommand(), reachable: true, peer: peer)
        #expect(plan.channel == .displayOnly)
        #expect(plan.body == nil)
    }

    @Test func mirrorHidesReplyWhenPeerIsOutOfRange() throws {
        var snap = try runningSnap(title: "週次レポート", rev: 3)
        snap.contract = 2
        snap.minReadable = 2
        var mirror = WatchMirror()
        mirror.receive(try WatchLink.context(for: snap))
        #expect(mirror.title == "週次レポート")
        #expect(mirror.remainingSeconds(at: 1_768_000_060) == 1440)
        #expect(mirror.replyGate == .displayOnly)
    }

    @Test func waitingMirrorDoesNotLookOutOfRange() {
        let mirror = WatchMirror()
        #expect(mirror.replyGate == .waiting)
        #expect(mirror.title == nil)
        #expect(mirror.remainingSeconds(at: 1_768_000_060) == nil)
    }

    private func runningSnap(title: String, rev: Int) throws -> SnapPlaintext {
        var snap = try WireJSON.decoder().decode(
            SnapPlaintext.self,
            from: ContractFixtures.data("fixtures/snap.json")
        )
        snap.rev = rev
        snap.title = title
        snap.contract = ContractVersion.contract
        snap.minReadable = ContractVersion.minReadable
        return snap
    }

    private func sampleCommand() -> CommandPlaintext {
        CommandPlaintext(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            op: .still,
            sessionId: nil,
            at: 1_768_000_000,
            contract: ContractVersion.contract,
            minReadable: ContractVersion.minReadable
        )
    }
}
