import Foundation
import TodoTrainSync

/// Mac posts with UserNotifications. No push, no Apple Developer Program.
enum CompanionOffscreenNotify {
    static func requests(snap: SnapPlaintext?, pipVisible: Bool, now: Date) -> [MacOffscreenRequest] {
        MacOffscreenPlanning.requests(snap: snap, pipVisible: pipVisible, now: now)
    }
}
