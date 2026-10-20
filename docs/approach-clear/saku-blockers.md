# v6 → v7 · サクサク感ブロッカー分析

日付: 2026-10-05（Asia/Tokyo）  
対象: `index-v6.html`（証拠）→ 適用先 `index-v7.html`  
北極星: 桜井「**遅さは罪**」／「**ギュッ→パッ**」。削るのは成功後・待機の空隙。接近の「ため」は残す。

---

## Top 5（体感を一番殺している順）

| # | ブロッカー | 証拠（v6） | 死時間 |
|---|---|---|---|
| **1** | **ヒット後の linger + nextAfter 二段スタック** | `lingerPerfectMs:190` + `nextAfterPerfectMs:220`＝**410ms**／可 130+200＝**330ms**／不可 **380+340＝720ms**（`resolveApproach` L1478–1497） | 刺した直後に「空」が来る。サクサクの最大敵 |
| **2** | **熱上昇の `heatTightenThen` 620ms ロック** | `phase='easedown'` で押下拒否（L1510–1512）。`setTimeout(..., 620)` + `comboDeadline += 700`（L1339–1344）。帯 transition CSS **.65s** | コンボが乗った瞬間に 0.6s 以上「構えて」待ち |
| **3** | **インターロック挿入 ~510ms ボタンロック** | 5灯 × `interlockStepMs:80` + 起動40 + 終了70 ≈ **510ms**。`locked-ilk` + `disabled`（L1174–1212）。`interlockChance:0.08` | 接近前に連動確認で手を止める |
| **4** | **STANDBY gap / boot の空き** | `gapStepsMs:[200,260,330,400]`、`bootGapMs:520`、運休時 `Math.max(d,900)`（L1275–1280） | 成功後 nextAfter のあとにさらに 200–400ms |
| **5** | **不可の長 linger + 重い FX 余韻** | `lingerMissMs:380`（コメント「let 不可 sit」）。`rejectBlink5 .44s`／`shake .34s`／`dropFx .65s`／ease-down ビジュアル **.9–1.0s**（`easeDownFx`） | 刺さりは良いが「座らせすぎ」で次拍が遠い |

---

## 全ブロッカー一覧（コード証拠つき）

### A. 殺す／大幅短縮（サクサク用）

| 項目 | v6 証拠 | 問題 | v7 |
|---|---|---|---|
| linger 良/可/不可/見送り | 190 / 130 / **380** / 280 | 成功・失敗後の眺め時間 | **80 / 55 / 150 / 120** |
| nextAfter 良/可/不可/見送り | 220 / 200 / **340** / 260 | linger 後の二段目待機 | **90 / 80 / 140 / 110** |
| gapStepsMs | `[200,260,330,400]` | 拍のあいだの自由空気 | `[100,140,180,220]` |
| pressLockMs | `120` | ヒット直後の空フレーム | **50** |
| earlyJamMs | `420` | 空押し stun が長い | **260**（噛みは残す） |
| bootGapMs | `520` | 起動の待ち | **260** |
| heatTighten hold | hardcoded **620** + deadline+700 | 段アップで押下ロック | **`heatTightenMs:180`** |
| band shrink/widen CSS | transition **.65s** | 見た目が遅い | **.22s** |
| interlock | 5×80 ≈510ms / chance 0.08 | ループを盗む | **3×45 ≈175ms** / chance **0.04** |
| barrier hold | hardcoded **280** / chance 0.05 | 接近前の空き | **`barrierHoldMs:120`** / 0.03 |
| trainPassTrack | **.42s** | 通過が次拍に食い込む | **.28s** |
| idle breath / band fidget | `idleBreath 2.6s`・`bandBreathe 2.8s` 常時 | 短 gap でも「ゆるい待機」に見える | **gap≥280ms のときだけ**／帯 breathe **kill** |
| 運休 idle stretch | `max(d,900)` | 世界観は良いが長すぎ | **max(d,520)** |
| stageUp / Down / banner / ochi | .7s / .85s / .75s / .95s | 段表示の余韻 | .32 / .40 / .35 / .45 |
| ease-down ビジュアル | cool .9s・easeFx .9s・ghost 1.1s | 落ちの意味は残しつつ短く | ~.35–.45s |
| miss FX 余韻 | reject .44 / shake .34 / drop .65 | 刺さりは短くて足りる | .28 / .22 / .36 |
| approachMs | **1320** | ためとしては妥当だがわずかに長い | **1180**（ためは残す） |

**死時間ざっくり（ヒット→次接近開始）**

| 結果 | v6 | v7 | 削減 |
|---|---|---|---|
| 良 | 190+220 = **410ms** | 80+90 = **170ms** | −59% |
| 可 | 130+200 = **330ms** | 55+80 = **135ms** | −59% |
| 不可 | 380+340 = **720ms** | 150+140 = **290ms** | −60% |

### B. 残す（世界観／コンボ／咬み）

| 項目 | 理由 |
|---|---|
| **HEAT_DIFF 閑→温→熱→灼** | コンボ熱＝難易度の核。帯狭・接近速のカーブはそのまま |
| **ease-down /「落ち」** | 切れ感の報酬。時間だけ短縮、文言・帯 widen・汁抜きは維持 |
| **太鼓 良／可／不可 帯** | `goodHalfW` / `perfectHalfW0` / earlyMul は触らない（窓の厳しさ＝ハラハラ） |
| **運行帯（運行中｜運休｜停車）** | 世界ストリップ。運休減光も維持（idle だけ短縮） |
| **点数・連続数なし** | プロダクトロック |
| **短セッション** | `sessionMs:40000` / `sessionFullClears:14` |
| **コンボ汁** | cascade / heat Taptic / train heat trail / 鋭スパイク |
| **不可の刺さり** | shake・赤ストロボ・× press-mark・jam（時間は短く） |
| **見送り（timeout）** | ループ継続のソフト却下 |
| **press 時刻判定** | フレーム量子化しない（狭い窓に必須） |
| **doubleBlip / jitter** | 単調さ対策。時間コストほぼゼロ |

---

## v7 への道（適用方針）

1. **成功後の空隙を半減以下**（linger + nextAfter + gap）→ 「刺す→パッ→すぐ次」
2. **熱上昇ロックを 620→180ms** → コンボの気持ちよさを盗まない
3. **まれな挿入は短く・稀に**（連動・遮断）→ 味は残し、主ループは盗まない
4. **idle breath は長い STANDBY だけ** → 短ギャップは「即接近」に見せる
5. **窓の広さ・熱倍率・世界帯・無スコアは不変** → v6 の好きな芯を壊さない

実装: `index-v7.html`。設計メモは `design.md`「v7」、開き方は `README.md`。
