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
        static let endBellEnabled = "settings.endBellEnabled"
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

    /// AlarmKit end bell at session budget (v2). Default OFF until user opts in.
    var endBellEnabled: Bool {
        didSet {
            UserDefaults.standard.set(endBellEnabled, forKey: Keys.endBellEnabled)
        }
    }

    static func makeForTesting(
        pauseLimit: Int = PauseLimitGuard.defaultLimit,
        overtimeSoundEnabled: Bool = true,
        endBellEnabled: Bool = false
    ) -> AppSettings {
        let settings = AppSettings()
        settings.pauseLimit = Self.clampPauseLimit(pauseLimit)
        settings.overtimeSoundEnabled = overtimeSoundEnabled
        settings.endBellEnabled = endBellEnabled
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

        if UserDefaults.standard.object(forKey: Keys.endBellEnabled) == nil {
            endBellEnabled = false
        } else {
            endBellEnabled = UserDefaults.standard.bool(forKey: Keys.endBellEnabled)
        }
    }

    static func clampPauseLimit(_ value: Int) -> Int {
        value == 3 ? 3 : PauseLimitGuard.defaultLimit
    }
}
