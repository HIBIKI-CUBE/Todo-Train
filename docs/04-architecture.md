# 04 — 技術の不変条件

スタックとモデルの形はコードを見る。ここは **壊すとプロダクトが崩れる置き方** だけ。

## 真実源

走行 / 停車の真実は open な `WorkSession`（`endedAt == nil`）と `SessionManager.reconcile()`。  
`Timer`・Live Activity・通知に経過時間の正を置かない。UI の 1 秒 tick は表示専用。

Live Activity を消しても、運行とセッションは DB が本尊。  
定時も車内放送もスコアにしない。判定は Date と当初見積もり。

ベル / LA / 車内放送の副作用は `WorkSession.boardedDeviceID` が自機のときだけ。取消済みの終了ベルを `recoverOnLaunch` で復活させない。

## CloudKit を足さない

Mac 同期の土管に SwiftData CloudKit は使わない。鍵が Apple 側にあり、「正規ユーザー以外は読めない」を満たさない。[13](13-sync-mac-companion.md)。

`CloudKitSync.isConfigured` は false のまま。store は `.none`。Personal Team に iCloud / CloudKit entitlement を足すと署名が失敗する。有料 ADP が要る実 iCloud は、App Store / 本番プッシュまで不要。
