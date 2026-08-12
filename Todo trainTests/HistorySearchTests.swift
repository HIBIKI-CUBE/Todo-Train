//
//  HistorySearchTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

struct HistorySearchTests {
    @Test func emptyQuery_matchesAll() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "メール返信", estimatedSeconds: 900)
        context.insert(ticket)
        let session = WorkSession(startedAt: .now, estimatedSecondsAtStart: 900, ticket: ticket)
        session.endedAt = .now
        session.outcome = .arrived
        context.insert(session)
        try context.save()

        #expect(HistorySearch.matches(session: session, query: ""))
        #expect(HistorySearch.matches(session: session, query: "   "))
    }

    @Test func partialTitle_caseInsensitive() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "SwiftData 設計", estimatedSeconds: 1800)
        context.insert(ticket)
        let session = WorkSession(startedAt: .now, estimatedSecondsAtStart: 1800, ticket: ticket)
        session.endedAt = .now
        context.insert(session)
        try context.save()

        #expect(HistorySearch.matches(session: session, query: "swift"))
        #expect(!HistorySearch.matches(session: session, query: "kotlin"))
    }

    @Test func filter_returnsOnlyMatches() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let a = Ticket(title: "Alpha", estimatedSeconds: 600)
        let b = Ticket(title: "Beta", estimatedSeconds: 600)
        context.insert(a)
        context.insert(b)

        let sessionA = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: a)
        sessionA.endedAt = .now
        let sessionB = WorkSession(startedAt: .now, estimatedSecondsAtStart: 600, ticket: b)
        sessionB.endedAt = .now
        context.insert(sessionA)
        context.insert(sessionB)
        try context.save()

        let filtered = HistorySearch.filter(sessions: [sessionA, sessionB], query: "alp")
        #expect(filtered.count == 1)
        #expect(filtered.first?.ticket?.title == "Alpha")
    }
}
