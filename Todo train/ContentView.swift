//
//  ContentView.swift
//  Todo train
//
//  Hub host + Focus fullScreenCover.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isFocusPresented = false

    var body: some View {
        NavigationStack {
            HubView()
        }
        .onAppear {
            recover()
            syncFocusPresentation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                recover()
                syncFocusPresentation()
            }
        }
        .onChange(of: sessionManager.phase) { _, _ in
            syncFocusPresentation()
        }
        .fullScreenCover(isPresented: $isFocusPresented) {
            FocusView()
                .environment(sessionManager)
                .interactiveDismissDisabled()
        }
    }

    private func syncFocusPresentation() {
        let shouldShow = sessionManager.phase == .running || sessionManager.phase == .overtime
        if isFocusPresented != shouldShow {
            isFocusPresented = shouldShow
        }
    }

    private func recover() {
        do {
            try sessionManager.recoverOnLaunch()
        } catch {
            sessionManager.reconcile()
        }
        syncFocusPresentation()
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let manager = SessionManager(modelContext: container.mainContext)
    return ContentView()
        .environment(manager)
        .modelContainer(container)
}
