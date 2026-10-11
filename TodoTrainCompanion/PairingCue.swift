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
            "つながりました。この Mac だけが読めます。"
        case .authenticating:
            "Touch ID で確定"
        case .waitingPeer:
            "読み取りました。iPhone を待っています"
        case .captured:
            "読み取りました"
        case .failed(let message):
            message
        case .scanning:
            "iPhone の画面をこの枠に入れる"
        }
    }
}
