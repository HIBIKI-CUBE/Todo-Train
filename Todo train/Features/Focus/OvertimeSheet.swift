//
//  OvertimeSheet.swift
//  Todo train
//

import AudioToolbox
import SwiftUI

enum OvertimeAlert {
    static func playSound() {
        AudioServicesPlaySystemSound(1005)
    }
}

// Legacy name kept for call sites migrating off the full-screen overlay.
enum OvertimeOverlay {
    static func playAlertSound() {
        OvertimeAlert.playSound()
    }
}
