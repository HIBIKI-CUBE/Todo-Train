//
//  TicketDeletionTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct TicketDeletionTests {
    @Test func canDeleteEndedSession_requiresEndedAt() {
        let open = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600)
        #expect(!TicketDeletion.canDeleteEndedSession(open))

        open.endedAt = .now
        #expect(TicketDeletion.canDeleteEndedSession(open))
    }

    @Test func shouldDeleteOrphanTicket_whenLastSessionRemoved() {
        let a = UUID()
        let b = UUID()
        #expect(
            TicketDeletion.shouldDeleteOrphanTicket(remainingSessionIDs: [a], removing: a)
        )
        #expect(
            !TicketDeletion.shouldDeleteOrphanTicket(remainingSessionIDs: [a, b], removing: a)
        )
        #expect(
            TicketDeletion.shouldDeleteOrphanTicket(remainingSessionIDs: [], removing: a)
        )
    }

    @Test func displayTitle_trimsAndFallsBack() {
        #expect(TicketDeletion.displayTitle("  報告書  ", fallback: "無題の切符") == "報告書")
        #expect(TicketDeletion.displayTitle("   ", fallback: "無題の切符") == "無題の切符")
        #expect(TicketDeletion.displayTitle("", fallback: "不明な切符") == "不明な切符")
    }

    @Test func rideState_priorityIsRunningThenPausedThenHistory() {
        #expect(
            TicketDeletion.rideState(hasEndedSessions: false, isPaused: false, isRunning: false) == .unused
        )
        #expect(
            TicketDeletion.rideState(hasEndedSessions: true, isPaused: false, isRunning: false) == .idle
        )
        #expect(
            TicketDeletion.rideState(hasEndedSessions: true, isPaused: true, isRunning: false) == .paused
        )
        #expect(
            TicketDeletion.rideState(hasEndedSessions: true, isPaused: true, isRunning: true) == .running
        )
    }

    @Test func swipeNeedsAlert_onlyWhenSideEffectsAreUncommon() {
        #expect(!TicketDeletion.swipeNeedsAlert(ride: .unused))
        #expect(TicketDeletion.swipeNeedsAlert(ride: .idle))
        #expect(TicketDeletion.swipeNeedsAlert(ride: .paused))
        #expect(TicketDeletion.swipeNeedsAlert(ride: .running))
        #expect(!TicketDeletion.swipeNeedsAlertForTag(ticketCount: 0))
        #expect(TicketDeletion.swipeNeedsAlertForTag(ticketCount: 1))
    }

    @Test func ticketPrompt_emptyTitle_usesFallbackInTitle() {
        let prompt = TicketDeletion.ticketPrompt(title: "  ", ride: .unused)
        #expect(prompt.title.contains("「無題の切符」"))
        #expect(!prompt.message.contains("「"))
    }

    @Test func ticketPrompt_putsNameInTitle_notRepeatedInMessage() {
        let prompt = TicketDeletion.ticketPrompt(title: "誤作成", ride: .unused)
        #expect(prompt.title == "「誤作成」を削除しますか？")
        #expect(prompt.message == "この操作は取り消せません。")
        #expect(!prompt.message.contains("誤作成"))
        #expect(!prompt.message.contains("履歴"))
    }

    @Test func ticketPrompt_idle_mentionsHistory() {
        let prompt = TicketDeletion.ticketPrompt(title: "報告書", ride: .idle)
        #expect(prompt.title == "「報告書」と履歴を削除しますか？")
        #expect(prompt.message.contains("乗車記録"))
        #expect(prompt.message.contains("取り消せません"))
        #expect(!prompt.message.contains("停車中"))
        #expect(!prompt.message.contains("走行中"))
        #expect(!prompt.message.contains("「報告書」"))
    }

    @Test func ticketPrompt_paused_and_running_explainSideEffects() {
        let paused = TicketDeletion.ticketPrompt(title: "レビュー", ride: .paused)
        #expect(paused.title == "停車中の「レビュー」を削除しますか？")
        #expect(paused.message.contains("停車中"))

        let running = TicketDeletion.ticketPrompt(title: "レビュー", ride: .running)
        #expect(running.title == "走行中の「レビュー」を削除しますか？")
        #expect(running.message.contains("フォーカス"))
        #expect(running.message.contains("終了ベル"))
    }

    @Test func ticketPrompt_transferChildren_areKept() {
        let prompt = TicketDeletion.ticketPrompt(
            title: "親",
            ride: .idle,
            hasTransferChildren: true
        )
        #expect(prompt.message.contains("乗り継ぎ先の切符は残ります"))
        let unused = TicketDeletion.ticketPrompt(
            title: "親",
            ride: .unused,
            hasTransferChildren: false
        )
        #expect(!unused.message.contains("乗り継ぎ"))
    }

    @Test func historySessionPrompt_distinguishesLastSession() {
        let keepTicket = TicketDeletion.historySessionPrompt(
            ticketTitle: "報告書",
            isLastSession: false
        )
        #expect(keepTicket.title == "「報告書」のこの履歴を削除しますか？")
        #expect(keepTicket.message.contains("この乗車記録だけ"))
        #expect(keepTicket.message.contains("切符と他の履歴は残ります"))
        #expect(!keepTicket.message.contains("最後"))

        let last = TicketDeletion.historySessionPrompt(
            ticketTitle: "報告書",
            isLastSession: true
        )
        #expect(last.title == "「報告書」の履歴と切符を削除しますか？")
        #expect(last.message.contains("最後の記録"))
        #expect(last.message.contains("切符も削除"))
        #expect(last.message.contains("取り消せません"))
    }

    @Test func historySessionPrompt_lastSessionKeepsTransferChildren() {
        let prompt = TicketDeletion.historySessionPrompt(
            ticketTitle: "親",
            isLastSession: true,
            hasTransferChildren: true
        )
        #expect(prompt.message.contains("乗り継ぎ先の切符は残ります"))
    }

    @Test func tagPrompt_unusedVersusInUse() {
        let unused = TicketDeletion.tagPrompt(name: "仕事", ticketCount: 0)
        #expect(unused.title == "「仕事」を削除しますか？")
        #expect(unused.message.contains("切符には影響しません"))
        #expect(!unused.message.contains("仕事"))

        let inUse = TicketDeletion.tagPrompt(name: "仕事", ticketCount: 3)
        #expect(inUse.title == unused.title)
        #expect(inUse.message.contains("3 枚の切符からこのタグが外れます"))
        #expect(inUse.message.contains("切符自体は残ります"))
    }

    @Test func sectionFooters_matchRideAndTagUsage() {
        #expect(TicketDeletion.ticketDeleteFooter(ride: .unused).contains("Hub"))
        #expect(TicketDeletion.ticketDeleteFooter(ride: .idle).contains("乗車記録"))
        #expect(TicketDeletion.ticketDeleteFooter(ride: .paused).contains("停車中"))
        #expect(TicketDeletion.ticketDeleteFooter(ride: .running).contains("フォーカス"))
        #expect(TicketDeletion.tagDeleteFooter(ticketCount: 0).contains("影響しません"))
        #expect(TicketDeletion.tagDeleteFooter(ticketCount: 2).contains("2 枚"))
    }
}
