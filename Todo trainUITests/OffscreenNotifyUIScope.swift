import XCTest

/// Notification delivery is covered by unit tests. This target does not post it.
enum OffscreenNotifyUIScope {
    static let postsFromThisTarget = false
}
