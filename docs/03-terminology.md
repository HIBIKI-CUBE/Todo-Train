# 03 — 用語表

UI 文言・ドメイン名・コード識別子で言い換えない。特に「乗り換え」「区間完了」「コーチ」は使わない。

## 確定用語

| 用語 | コード / 英語 | 定義 |
|------|---------------|------|
| **切符** | `Ticket` | 1 つのタスク |
| **Hub** | Hub | 未完了切符の中心画面 |
| **運行** | `ServiceDay` | 1 日の作業枠。開始〜終了 |
| **運行開始** | `startService` | その日の作業モード開始。発車の前提 |
| **運行終了** | `endService` | その日を閉じる。停車中は乗り継ぎ or 放棄 |
| **発車** | Depart / board | フォーカスセッション開始 |
| **走行中** | `SessionPhase.running` | フォーカス実行中 |
| **停車** | Pause | セッション中断。Hub に戻れる |
| **停車中** | paused open session | 中断済み・未完了。上限カウント対象 |
| **到着** | `ClosureKind.arrived` | 完了の明示操作 → アーカイブ |
| **途中下車** | `partialDisembark` | 区間終了だが全体未完了 |
| **乗り継ぎ** | `TaskLineage` | 途中下車から生まれた新切符へのリンク |
| **放棄** | `abandoned` | もう乗らない。ループを閉じる |
| **臨時停車許可** | Emergency Override | **廃止**。停車は常に可。上限は新規発車 |
| **到着整理** | Remaining tickets canvas | 到着/途中下車後に残作業を新切符として掃き出す UI |
| **超過** | `SessionPhase.overtime` | 見積もり超過 |
| **延長** | Extend | 見積もり時間を追加（フォーカス継続） |
| **割り込み** | interrupt issue | Focus 走行中に新切符を発行し、今の乗車を停車して発車。同一切符の書き換えではない |
| **再乗車** | Resume / re-board | 停車中切符の再発車 |
| **定時到着** | on-time arrival | 当初見積もりの帯域内で到着したときの見出し。同じ到着案内の味付け |
| **早着** | early arrival | 当初見積もりより早く着いたときの見出し。いい結果。点数にしない |
| **定時運行** | on-time service | その運行の到着に遅延がなかったときの短い案内（早着は可） |
| **車内放送** | check-in | 乗務中の短い問い。進捗（予測不能）と背面の「まだ乗ってる？」。ウィザードではない |

## 使わない用語

| 用語 | 理由 |
|------|------|
| 乗り換え（同一切符の書き換え） | 却下。分割 + 乗り継ぎのみ |
| インボックスへ戻す | 却下 |
| 区間完了 | 「途中下車」を使う |
| コーチ / コーチング UI | 「道具」として設計。AI は提案・要約に限定 |
| Task（型名） | Swift の `Task` と衝突 → **`Ticket`** |
| ポイント / XP / ストリーク / 定時率 | 定時の喜びを通貨化するとハックされる。出さない |

## ClosureKind（コード）

```swift
enum ClosureKind {
    case arrived           // 到着
    case partialDisembark  // 途中下車
    case abandoned         // 放棄
}
```

## SessionPhase（コード）

```swift
enum SessionPhase {
    case idle
    case running
    case paused
    case overtime
}
```
