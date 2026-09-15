# 07 — 研究根拠とプラットフォーム制約

実装時に踏んではいけない「なぜ」と OS の上限。画面の現行パターンはコードを見る。

## 研究

| 設計 | 根拠 | 強度 |
|------|------|------|
| 停車上限 2（設定で 3）。制限は新規発車。停車は常に可 | 同時ゴール ≈2 | **強〜中** |
| 走行中 1 | シングルタスクング | **強** |
| Inbox 無制限 / 停車は制限 | GTD capture vs clarify; [Risko & Gilbert 2016](https://doi.org/10.1016/j.tics.2016.07.008) | **強** |
| 見積もり上限 60 分 | [Buehler et al. 1994](https://doi.org/10.1037/0022-3514.67.3.366) Planning Fallacy。unpacking で精度が上がる。「60」自体はヒューリスティック | **中〜強** |
| 途中下車 + 乗り継ぎ | [Masicampo & Baumeister 2011](https://doi.org/10.1037/a0024192); Ovsiankina | **中** |
| 分割 > 書き換え | 表象変更コスト | **弱〜中** |
| 道具 > コーチ | [Barkley 1997](https://doi.org/10.1037/0033-2909.121.1.65)。介入自体が実行機能を消費する | **中** |
| 見積もり校正は中央値 | 平均より Planning Fallacy に強い | **中** |
| 定時は帯域内・非通貨。到着は完了優先 | Goodhart。超過で祝祭を取り上げると責めになる。[Deci & Ryan SDT](https://doi.org/10.1037/0003-066X.55.1.68) | **中** |
| 計画は if-then、状況認識は乗務の現場、網は掛け損ねだけ | [Gollwitzer implementation intentions](https://doi.org/10.1037/0033-2909.124.2.163); [Endsley SA](https://doi.org/10.1177/0018720815573149); [Wood 習慣](https://doi.org/10.1146/annurev-psych-122216-011705)。タブを毎日開かせるのは別行動を鍛える | **中** |
| ATS に運転を任せない | [Bainbridge 自動化の皮肉](https://doi.org/10.1016/0003-6870(83)90223-0)。網の回数を成績にすると外的調整になる | **中** |

警告だけで停車上限を守らせるのは弱い。枠を臨時停車で増やさない。

定時を残しつつハックさせない: 測ると見積もり水増しが合理になる。空の運行を定時運行にしない。延長後予算で「間に合わせた」ことにしない。

## Live Activities

出典: [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [WWDC26 #223](https://developer.apple.com/videos/play/wwdc2026/223/)。

iOS 27 でも緩和されていない:

- アクティブ **最大 8 時間**（システムが終了）
- Dynamic Island は終了と同時に消える
- 終了後の Lock Screen は最大 +4 時間
- ContentState ≈ 4KB。開始は原則フォアグラウンド。休眠中の任意更新は push なしでは不可
- 毎秒 `update` は非推奨 → `Text(timerInterval:)` に任せる

**全日の「運行」を 1 本の LA で張り続けない。** 昼過ぎに死ぬ。Apple の定義は “いま起きていること”。空き時間の催促は Widget / アプリ内 / 控えめな通知。

1 LA = 走行中 1 件、または直近の停車中 1 件（こちらの 2 時間は 8 時間上限の手前）。運行日ではない。停車中は `timerInterval` を止められないので静的な残りに切る。`end` すると StandBy / Island が消えるので、停車は `pause` / `update` で残す。

LA を消すこと ≠ 運行キャンセル。DB が本尊。

## AlarmKit

[WWDC25 #230](https://developer.apple.com/videos/play/wwdc2025/230/)。Focus / サイレントを突き破る終了ベル。StandBy のカウントダウンには Alarm の Live Activity が必須。運行を 8 時間表示する手段ではない。

**LA = 視線。AlarmKit = 終了の強制通知。** 同時に 2 本張らない。

StandBy は Clock アプリ級の没入 UI ではない。ActivityKit は提案ビューをスケールし、`activityBackgroundTint` を延長するだけ。箱型の黒オーバーレイで帯を小さく見せない。HIG どおり操作は原則 1 つ。

## Foundation Models / PCC

オンデバイスは entitlement 不要。PCC は `com.apple.developer.private-cloud-compute` と日次クォータ。得意は短い構造化出力であり、汎用チャットボットではない。見積もり数値は Heuristic で足りる。

## フォーカスの限界

アプリ内で Hub を隠すことはできる。ホーム / App Switcher / 他アプリの起動は止められない。仕様は **「アプリ内ではフォーカスを維持。OS では閉じ込めない」**。

## CloudKit / ADP

SwiftData の私有同期は有料 Apple Developer Program の iCloud コンテナが要る。Personal Team に entitlement を足すと署名が失敗する。`@Attribute(.unique)` は CloudKit と両立しない。同期の土管は CloudKit にしない（[13](13-sync-mac-companion.md)）。

## カレンダーと ATS

EventKit は **掲示** であり、所属の正ではない。載せた枠だけがダイヤ。終日と辞退は対象外。掲示するカレンダーはユーザーが選ぶ。選んでいないカレンダーは図表に出さない。載せたダイヤは消さない。

iOS はバックグラウンドで任意時刻に SwiftData を確実に更新できない。ATS の 60 秒停車は前面ならその場、背景なら次の `reconcile()` で境界へ遡及する。AlarmKit は終了ベル用で **1 本**。見積終了と次のダイヤ開始の早い方に畳む。ダイヤ開始用に 2 本目を足さない。

状況認識（次枠・いま被っている枠）は案内板と Focus / PiP、Hub 運行の一行に出す。Hub に掲示リストは常設しない。許可済みなら Hub でも掲示を温める（表示はしない）。発車が見積と載せた枠、またはいまの掲示と重なるときは確認する。発車は止めない。
