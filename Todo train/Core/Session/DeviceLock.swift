//
//  DeviceLock.swift
//  Todo train
//
//  Lock vs unlocked-background: away interrupt only when the device is unlocked.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol DeviceLockReading: Sendable {
    var isLocked: Bool { get }
}

struct SystemDeviceLock: DeviceLockReading {
    var isLocked: Bool {
        #if canImport(UIKit)
        !UIApplication.shared.isProtectedDataAvailable
        #else
        false
        #endif
    }
}

struct FixedDeviceLock: DeviceLockReading {
    var isLocked: Bool
}
