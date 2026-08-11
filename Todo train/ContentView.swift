//
//  ContentView.swift
//  Todo train
//
//  Tab host + Focus fullScreenCover.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isFocusPresented = false

    var body: some View {
        TabView {
            Tab("切符", systemImage: "tram.fill") {
                NavigationStack {
                    HubView()
                }
            }

            Tab("履歴", systemImage: "clock") {
                NavigationStack {
                    HistoryView()
                }
            }

            Tab("設定", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tint(TrainTheme.rail)
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
        .environment(AppSettings.shared)
        .modelContainer(container)
}
