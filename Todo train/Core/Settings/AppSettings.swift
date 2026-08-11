//
//  AppSettings.swift
//  Todo train
//

import Foundation
import Observation

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let pauseLimit = "settings.pauseLimit"
        static let overtimeSoundEnabled = "settings.overtimeSoundEnabled"
    }

    var pauseLimit: Int {
        didSet {
            let clamped = Self.clampPauseLimit(pauseLimit)
            if clamped != pauseLimit {
                pauseLimit = clamped
                return
            }
            UserDefaults.standard.set(pauseLimit, forKey: Keys.pauseLimit)
        }
    }

    var overtimeSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(overtimeSoundEnabled, forKey: Keys.overtimeSoundEnabled)
        }
    }

    static func makeForTesting(
        pauseLimit: Int = PauseLimitGuard.defaultLimit,
        overtimeSoundEnabled: Bool = true
    ) -> AppSettings {
        let settings = AppSettings()
        settings.pauseLimit = Self.clampPauseLimit(pauseLimit)
        settings.overtimeSoundEnabled = overtimeSoundEnabled
        return settings
    }

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Keys.pauseLimit)
        pauseLimit = stored == 0 ? PauseLimitGuard.defaultLimit : Self.clampPauseLimit(stored)

        if UserDefaults.standard.object(forKey: Keys.overtimeSoundEnabled) == nil {
            overtimeSoundEnabled = true
        } else {
            overtimeSoundEnabled = UserDefaults.standard.bool(forKey: Keys.overtimeSoundEnabled)
        }
    }

    static func clampPauseLimit(_ value: Int) -> Int {
        value == 3 ? 3 : PauseLimitGuard.defaultLimit
    }
}
