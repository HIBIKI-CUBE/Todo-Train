//
//  TransferCanvasPresenterTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct TransferCanvasPresenterTests {
    @Test func enqueueThenPresentPending_promotesOnce() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let parent = Ticket(title: "親", estimatedSeconds: 600)
        context.insert(parent)
        try context.save()

        let presenter = TransferCanvasPresenter()
        let sessionID = UUID()
        presenter.enqueueAfterFocusDismiss(parent: parent, sessionID: sessionID)

        #expect(presenter.pending != nil)
        #expect(presenter.active == nil)

        presenter.presentPendingIfNeeded()
        #expect(presenter.pending == nil)
        #expect(presenter.active?.parent.id == parent.id)
        #expect(presenter.active?.sessionID == sessionID)

        presenter.presentPendingIfNeeded()
        #expect(presenter.active?.parent.id == parent.id)
    }

    @Test func clearPending_dropsQueuedLaunch() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let parent = Ticket(title: "親", estimatedSeconds: 600)
        context.insert(parent)

        let presenter = TransferCanvasPresenter()
        presenter.enqueueAfterFocusDismiss(parent: parent, sessionID: nil)
        presenter.clearPending()
        presenter.presentPendingIfNeeded()

        #expect(presenter.active == nil)
        #expect(presenter.pending == nil)
    }
}
