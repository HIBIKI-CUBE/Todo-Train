//
//  AppSettings.swift
//  Todo train
//

import Foundation
import Observation
import TodoTrainSync

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let pauseLimit = "settings.pauseLimit"
        static let overtimeSoundEnabled = "settings.overtimeSoundEnabled"
        static let endBellEnabled = "settings.endBellEnabled"
        static let keepAwakeWhileChargingInFocus = "settings.keepAwakeWhileChargingInFocus"
        static let cabinAnnouncementsEnabled = "settings.cabinAnnouncementsEnabled"
        static let lastIssuedEstimateMinutes = "settings.lastIssuedEstimateMinutes"
        static let companionRelayURL = "settings.companionRelayURL"
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

    /// Focus + charging (or full): disable idle timer so the screen stays on. Default ON.
    var keepAwakeWhileChargingInFocus: Bool {
        didSet {
            UserDefaults.standard.set(keepAwakeWhileChargingInFocus, forKey: Keys.keepAwakeWhileChargingInFocus)
        }
    }

    /// Mid-ride 車内放送 (progress + away). Default ON; a tool the user can silence.
    var cabinAnnouncementsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cabinAnnouncementsEnabled, forKey: Keys.cabinAnnouncementsEnabled)
        }
    }

    /// Last issued estimate in minutes (1...60). Nil until the user has issued once this install.
    var lastIssuedEstimateMinutes: Int? {
        didSet {
            if let minutes = lastIssuedEstimateMinutes {
                UserDefaults.standard.set(Self.clampEstimateMinutes(minutes), forKey: Keys.lastIssuedEstimateMinutes)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastIssuedEstimateMinutes)
            }
        }
    }

    /// Relay for Mac companion. Release 既定は本番カスタムドメイン。DEBUG はローカル wrangler。
    var companionRelayURLString: String {
        didSet {
            UserDefaults.standard.set(companionRelayURLString, forKey: Keys.companionRelayURL)
        }
    }

    var companionRelayURL: URL? {
        let trimmed = companionRelayURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme else { return nil }
        if scheme == "https" { return url }
        #if DEBUG
        if scheme == "http" { return url }
        #endif
        return nil
    }

    static func makeForTesting(
        pauseLimit: Int = PauseLimitGuard.defaultLimit,
        overtimeSoundEnabled: Bool = true,
        endBellEnabled: Bool = false,
        keepAwakeWhileChargingInFocus: Bool = true,
        cabinAnnouncementsEnabled: Bool = true,
        lastIssuedEstimateMinutes: Int? = nil,
        companionRelayURLString: String = ""
    ) -> AppSettings {
        let settings = AppSettings()
        settings.pauseLimit = Self.clampPauseLimit(pauseLimit)
        settings.overtimeSoundEnabled = overtimeSoundEnabled
        settings.endBellEnabled = endBellEnabled
        settings.keepAwakeWhileChargingInFocus = keepAwakeWhileChargingInFocus
        settings.cabinAnnouncementsEnabled = cabinAnnouncementsEnabled
        settings.lastIssuedEstimateMinutes = lastIssuedEstimateMinutes.map(Self.clampEstimateMinutes)
        settings.companionRelayURLString = companionRelayURLString
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

        if UserDefaults.standard.object(forKey: Keys.keepAwakeWhileChargingInFocus) == nil {
            keepAwakeWhileChargingInFocus = true
        } else {
            keepAwakeWhileChargingInFocus = UserDefaults.standard.bool(forKey: Keys.keepAwakeWhileChargingInFocus)
        }

        if UserDefaults.standard.object(forKey: Keys.cabinAnnouncementsEnabled) == nil {
            cabinAnnouncementsEnabled = true
        } else {
            cabinAnnouncementsEnabled = UserDefaults.standard.bool(forKey: Keys.cabinAnnouncementsEnabled)
        }

        if UserDefaults.standard.object(forKey: Keys.lastIssuedEstimateMinutes) == nil {
            lastIssuedEstimateMinutes = nil
        } else {
            lastIssuedEstimateMinutes = Self.clampEstimateMinutes(
                UserDefaults.standard.integer(forKey: Keys.lastIssuedEstimateMinutes)
            )
        }

        if let storedRelay = UserDefaults.standard.string(forKey: Keys.companionRelayURL) {
            companionRelayURLString = storedRelay
        } else {
            companionRelayURLString = RelayEndpoint.defaultURLString
        }
    }

    nonisolated static func clampPauseLimit(_ value: Int) -> Int {
        value == 3 ? 3 : PauseLimitGuard.defaultLimit
    }

    nonisolated static func clampEstimateMinutes(_ value: Int) -> Int {
        min(max(value, 1), Ticket.maxEstimatedSeconds / 60)
    }
}
