import Foundation

/// 設定と Mac のメニューに出す、同期の約束の文言。
public enum ContractCopy {
    public static let heading = "同期の約束"
    public static let macOlder = "Mac のアプリを更新すると、すべての操作が届くようになります。"
    public static let iphoneOlder = "この iPhone のアプリを更新すると、すべての操作が届くようになります。"
    public static let relayOlder = "中継の更新を待っています。そのあいだも、走行と停車の表示は届きます。"
    public static let unsupportedOp = "この操作は Mac のアプリを更新すると使えます。"
    public static let aligned = "約束の版はそろっています。"

    public static func versions(iphone: Int, mac: Int) -> String {
        "この iPhone は約束 \(iphone) 版、Mac は約束 \(mac) 版です。"
    }
}

/// Where the contract notice goes. In range, only the diagnostic line. Out of range, the Mac section and the Mac menu.
public struct ContractPresentation: Equatable, Sendable {
    public var diagnostic: String?
    public var guidance: [String]

    public static let quiet = ContractPresentation(diagnostic: nil, guidance: [])

    public init(diagnostic: String? = nil, guidance: [String] = []) {
        self.diagnostic = diagnostic
        self.guidance = guidance
    }

    public static func make(
        local: ContractAnnouncement = .current,
        peer: ContractAnnouncement?,
        relay: ContractAnnouncement?,
        side: ContractSide
    ) -> ContractPresentation {
        if let block = ContractCompat.commandBlock(local: local, peer: peer, relay: relay, side: side) {
            var lines: [String] = []
            if let peer {
                let iphone = side == .iphone ? local.contract : peer.contract
                let mac = side == .iphone ? peer.contract : local.contract
                lines.append(ContractCopy.versions(iphone: iphone, mac: mac))
            }
            lines.append(block)
            return ContractPresentation(guidance: lines)
        }
        guard peer != nil else { return .quiet }
        return ContractPresentation(diagnostic: ContractCopy.aligned)
    }
}
