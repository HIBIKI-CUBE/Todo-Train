//
//  Todo_trainApp.swift
//  Todo train
//
//  Created by HIBIKI CUBE on 2026/08/11.
//

import SwiftUI
import SwiftData

@main
struct Todo_trainApp: App {
    private let container: ModelContainer
    @State private var sessionManager: SessionManager

    init() {
        do {
            let container = try AppModelContainer.make(inMemory: false)
            self.container = container
            // Use the same ModelContext the views will share via environment...
            // SessionManager needs a long-lived context bound to this container.
            let context = container.mainContext
            _sessionManager = State(
                initialValue: SessionManager(modelContext: context)
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .modelContainer(container)
        }
    }
}
