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
