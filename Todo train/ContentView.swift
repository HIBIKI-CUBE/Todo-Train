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
    @State private var didRecoverOnLaunch = false

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
            if !didRecoverOnLaunch {
                recoverOnLaunch()
                didRecoverOnLaunch = true
            } else {
                sessionManager.reconcile()
            }
            syncFocusPresentation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Foreground: recompute Date-based phase only.
                // Do not re-run recoverOnLaunch (would re-schedule cancelled end bells).
                sessionManager.reconcile()
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

    private func recoverOnLaunch() {
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
