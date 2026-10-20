//
//  SessionPause+Reason.swift
//  Todo train
//

import Foundation
import TodoTrainSync

/// Device that paused. Not on the wire. Mac `pause` is `mac`; every iPhone path is `iphone`.
enum PauseOrigin: String, Sendable, Equatable {
    case iphone
    case mac
}

extension SessionPause {
    var heldBy: PauseHeldBy? {
        get {
            guard let heldByRaw else { return nil }
            let value = PauseHeldBy(rawValue: heldByRaw)
            if case .unknown = value { return nil }
            return value
        }
        set { heldByRaw = newValue?.rawValue }
    }

    var pausedOn: PauseOrigin? {
        get { pausedOnRaw.flatMap(PauseOrigin.init(rawValue:)) }
        set { pausedOnRaw = newValue?.rawValue }
    }
}
