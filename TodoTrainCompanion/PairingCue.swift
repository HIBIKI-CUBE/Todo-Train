import Foundation

enum PairingCue: Equatable {
    case scanning
    case captured
    case waitingPeer
    case authenticating
    case established
    case failed(String)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .established:
            "つながった。この Mac だけが読める。"
        case .authenticating:
            "Touch ID で確定"
        case .waitingPeer:
            "読めた。iPhone を待っています"
        case .captured:
            "読めた"
        case .failed(let message):
            message
        case .scanning:
            "iPhone の画面をこの枠に入れる"
        }
    }
}
