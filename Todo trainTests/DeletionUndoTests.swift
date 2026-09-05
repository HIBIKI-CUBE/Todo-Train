//
//  DeletionUndoTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct DeletionUndoTests {
    private func makeContext() throws -> ModelContext {
        let container = try AppModelContainer.make(inMemory: true)
        return ModelContext(container)
    }

    @Test func bannerMessages_includeNames() {
        #expect(DeletionUndo.bannerMessage(ticketTitle: "誤作成") == "「誤作成」を削除しました")
        #expect(
            DeletionUndo.bannerMessage(historyTicketTitle: "報告書", deletedTicketToo: false)
                == "「報告書」の履歴を削除しました"
        )
        #expect(
            DeletionUndo.bannerMessage(historyTicketTitle: "報告書", deletedTicketToo: true)
                == "「報告書」の履歴と切符を削除しました"
        )
        #expect(DeletionUndo.bannerMessage(tagName: "仕事") == "「仕事」を削除しました")
    }

    @Test func restoreTicket_bringsBackUnusedTicketAndTags() throws {
        let context = try makeContext()
        let tag = Tag(name: "仕事", colorHex: "#000000", sortOrder: 0)
        context.insert(tag)
        let ticket = Ticket(title: "誤作成", estimatedSeconds: 600, sortOrder: 3)
        ticket.tags = [tag]
        context.insert(ticket)
        try context.save()
        let record = DeletionUndo.captureTicket(ticket)
        let ticketID = ticket.id

        context.delete(ticket)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Ticket>()).isEmpty)

        try DeletionUndo.restoreTicket(record, into: context)
        try context.save()

        let restored = try context.fetch(FetchDescriptor<Ticket>())
        #expect(restored.count == 1)
        #expect(restored.first?.id == ticketID)
        #expect(restored.first?.title == "誤作成")
        #expect(restored.first?.sortOrder == 3)
        #expect(restored.first?.tags.first?.name == "仕事")
    }

    @Test func restoreSession_keepsBoardedDeviceID() throws {
        let context = try makeContext()
        let ticket = Ticket(title: "往復", estimatedSeconds: 600)
        context.insert(ticket)
        let session = WorkSession(
            startedAt: .now,
            estimatedSecondsAtStart: 600,
            ticket: ticket,
            boardedDeviceID: "phone-a"
        )
        session.endedAt = .now
        context.insert(session)
        try context.save()

        let record = DeletionUndo.captureSession(session)
        context.delete(session)
        try context.save()

        DeletionUndo.restoreSession(record, onto: ticket, into: context)
        try context.save()

        let restored = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(restored.first?.boardedDeviceID == "phone-a")
    }

    @Test func undoCenter_undoRunsRestoreOnce() {
        let center = DeletionUndoCenter()
        var restored = 0
        center.offer(message: "削除しました") {
            restored += 1
        }
        #expect(center.bannerMessage == "削除しました")
        center.undo()
        #expect(center.bannerMessage == nil)
        #expect(restored == 1)
        center.undo()
        #expect(restored == 1)
    }
}
