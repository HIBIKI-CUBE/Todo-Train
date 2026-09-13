//
//  HubPreviewSeed.swift
//  Todo train
//
//  In-memory SwiftData for Hub `#Preview`. Not used at runtime.
//

import Foundation
import SwiftData
import SwiftUI

enum HubPreviewSeed {
    enum Scenario {
        /// ContentUnavailableView on an idle platform.
        case empty
        /// Tickets in the Wallet, but 運行開始 has not run (発車 disabled).
        case backlogIdle
        /// Open service day with a mixed unused stack.
        case inService
        /// Open service plus one paused ride so 停車中 is visible.
        case inServiceWithPause
    }

    @MainActor
    static func make(scenario: Scenario) -> (ModelContainer, SessionManager) {
        let container = try! AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let now = Date()
        let clock = FixedSessionClock(now)
        let manager = SessionManager(modelContext: context, clock: clock)

        guard scenario != .empty else {
            return (container, manager)
        }

        let samples = insertSampleTickets(into: context, now: now)
        try! context.save()

        if scenario == .backlogIdle {
            return (container, manager)
        }

        try! manager.startService(now: now)

        if scenario == .inServiceWithPause {
            try! manager.board(ticket: samples.pauseCandidate, now: now)
            clock.advance(by: 8 * 60)
            try! manager.pause(now: clock.now)
        }

        return (container, manager)
    }

    @MainActor
    static func hubView(scenario: Scenario) -> some View {
        let (container, manager) = make(scenario: scenario)
        return NavigationStack {
            HubView()
                .environment(manager)
                .environment(AppSettings.shared)
                .environment(DeletionUndoCenter())
                .environment(TicketMotionBridge())
                .modelContainer(container)
        }
    }

    @discardableResult
    private static func insertSampleTickets(
        into context: ModelContext,
        now: Date
    ) -> (pauseCandidate: Ticket, others: [Ticket]) {
        let work = Tag(name: "仕事", colorHex: "#0091FF", sortOrder: 0)
        let life = Tag(name: "生活", colorHex: "#30A46C", sortOrder: 1)
        let review = Tag(name: "レビュー", colorHex: "#8E4EC6", sortOrder: 2)
        [work, life, review].forEach(context.insert)

        let memo = Ticket(
            title: "メモ",
            estimatedSeconds: 15 * 60,
            sortOrder: 0,
            createdAt: now.addingTimeInterval(-3 * 3_600)
        )
        let weekly = Ticket(
            title: "週次レビューの下書き",
            estimatedSeconds: 25 * 60,
            sortOrder: 1,
            createdAt: now.addingTimeInterval(-2 * 3_600)
        )
        let shopping = Ticket(
            title: "買い物",
            estimatedSeconds: 10 * 60,
            sortOrder: 2,
            createdAt: now.addingTimeInterval(-90 * 60)
        )
        shopping.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: now)
        let longTitle = Ticket(
            title: "長いタイトルでマルス券の折り返しと密度を確認する",
            estimatedSeconds: 45 * 60,
            sortOrder: 3,
            createdAt: now.addingTimeInterval(-40 * 60)
        )
        let mail = Ticket(
            title: "メール返信",
            estimatedSeconds: 5 * 60,
            sortOrder: 4,
            createdAt: now.addingTimeInterval(-12 * 60)
        )
        let docs = Ticket(
            title: "ドキュメント整理",
            estimatedSeconds: 20 * 60,
            sortOrder: 5,
            createdAt: now
        )

        let tickets = [memo, weekly, shopping, longTitle, mail, docs]
        tickets.forEach(context.insert)
        weekly.tags = [work]
        shopping.tags = [life]
        longTitle.tags = [work, review]
        mail.tags = [work]
        return (weekly, [memo, shopping, longTitle, mail, docs])
    }
}
