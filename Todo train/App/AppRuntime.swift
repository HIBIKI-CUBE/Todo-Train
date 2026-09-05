//
//  AppRuntime.swift
//  Todo train
//
//  Shared handle for App Intents / notification actions after launch.
//

import SwiftData

@MainActor
enum AppRuntime {
    static var modelContainer: ModelContainer?
    static var sessionManager: SessionManager?
}
