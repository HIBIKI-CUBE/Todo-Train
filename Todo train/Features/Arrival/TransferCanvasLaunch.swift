import Foundation
import SwiftData

/// Shared launch payload when 途中下車 opens the remaining-tickets canvas.
struct TransferCanvasLaunch: Identifiable {
    let id = UUID()
    let parent: Ticket
    let sessionID: UUID?
}
