import Foundation

/// User-facing companion copy. Keep iPhone and Mac on the same phrasing.
public enum SyncCopy {
    public static let relayDisconnected = "リレーが切れた"
    public static let notConnected = "つながっていません"
    public static let invalidQR = "その QR ではつながらない"
    public static let reconnectNeeded = "つなぎ直しが必要"
    public static let confirmTimedOut = "確定の時間切れ。自分に戻してもう一度。"
    public static let confirmFailed = "確定できなかった。自分に戻してからもう一度。"
    public static let relayURLMissing = "リレー URL を設定に書いてから、もう一度。"
    public static let pauseLimitReached = "停車できません（停車上限）"
    public static let notPaused = "停車中ではない"
    public static let sentToIPhone = "iPhone に送った"
    public static let iphoneConfirmReason = "画面を自分に戻して、この Mac との連携を確定します"
    public static let macConfirmReason = "画面を自分に戻して、iPhone との連携を確定します"

    public static func connectionStatus(_ error: Error) -> String {
        guard let sync = error as? SyncError else { return relayDisconnected }
        switch sync {
        case .notPaired, .pairingAborted, .pairingNotBound:
            return notConnected
        case .confirmTimedOut:
            return confirmTimedOut
        case .transport(_, let code) where code == "pauseLimitReached":
            return pauseLimitReached
        case .transport(_, let code) where code == "notPaused":
            return notPaused
        default:
            return relayDisconnected
        }
    }

    public static func pairingFailure(_ error: Error) -> String {
        guard let sync = error as? SyncError else { return reconnectNeeded }
        switch sync {
        case .invalidPairingURL:
            return invalidQR
        case .confirmTimedOut:
            return confirmTimedOut
        case .pairingAborted:
            return confirmFailed
        case .transport(_, let code) where code == "confirmWindow":
            return confirmTimedOut
        default:
            return reconnectNeeded
        }
    }
}
