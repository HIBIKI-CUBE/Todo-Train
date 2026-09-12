# 16 — 起床後にやること（確認が要る残り）

最終更新: 2026-09-12。コード側で進められる引き継ぎは PR にした。ここは **人が見ないと閉じない** ものだけ。

## マージしてよい PR（Web で足りる）

#34 は `develop` 済み。残りはこの順。コンフリクトしやすいのは Settings / `docs/08` / `project.pbxproj`。

| 順 | PR | 内容 | 自動テスト |
|----|----|------|------------|
| 済 | [#34](https://github.com/HIBIKI-CUBE/Todo-Train/pull/34) | Linux 同期の CI と現状ドキュメント | `sync-swift` green |
| 1 | [#36](https://github.com/HIBIKI-CUBE/Todo-Train/pull/36) | 車内放送 away → Session LA alert。develop のテスト壊れも直す | `Todo trainTests` 233 Swift Testing |
| 2 | [#35](https://github.com/HIBIKI-CUBE/Todo-Train/issues/37) / [PR](https://github.com/HIBIKI-CUBE/Todo-Train/pull/35) | SYNC-3 iOS セルフィー + ScenePhase | パッケージテスト。実機は後 |
| 3 | [#39](https://github.com/HIBIKI-CUBE/Todo-Train/pull/39) | SYNC-4 メニューバー accessory | `TodoTrainCompanionTests`。カメラは後 |

#35 と #36 は両方 `SettingsView` と `docs/08` を触る。先にマージした方に合わせて後続を直す。

## 実機・画面（コードでは閉じない）

### 車内放送 / Live Activity（#36、[11](11-v2-alarmkit-setup.md) §6）

- [ ] 終了ベル OFF・他アプリへ退避（画面オン）→ 数十秒で Session LA alert「まだ乗ってる？」→ 停車が効く
- [ ] ロックして作業 → away 通知も LA alert も出ない
- [ ] 終了ベル ON・同じ退避 → away が Alarm LA に重ならない
- [ ] 走行中 Session LA の停車 → LA は残り、再乗車できる
- [ ] ロック中の Intent 認証（停車 / 停止）

### SYNC-3 セルフィー（#35 / Issue #37）

- [ ] 設定に Mac セクションとペアリング画面。つながったあとはコンピュータ名とペア識別子
- [ ] 発車すると（前面のまま）Mac メニューバーに乗務が出る。再起動した iPhone が既に乗務中でも出る
- [ ] 実機で前面カメラ。画面を Mac に向ける
- [ ] Face ID は光学のあと、自分に戻してから
- [ ] 前面復帰で停車 cmd → 既存の停車（上限なら止まらず ack だけ）
- [ ] CloudKit / iCloud capability は増えていない
- [ ] 発券・Focus・停車 LA が壊れていない

### SYNC-4 メニューバー（Issue #38）

- [ ] メニューバー extra が Dock なしで出る
- [ ] 未ペアクリックで大きな正方カメラ。読めたら緑、失敗は赤。Touch ID は自動
- [ ] iPhone がつながったあと、Mac も「つながった」になる（オファーを消して Mac だけ失敗しない）
- [ ] 吹き出しを閉じるとカメラインジケータが消える
- [ ] 走行中は短いタイトル + 残り。停車ボタン。停車中は再乗車
- [ ] 乗務中 PiP が四隅へスナップする。左右へ十分ドラッグすると Peek。クリックで戻る
- [ ] PiP ホバーで停車 / 再乗車。クリックしても前面アプリのキー入力を奪わない
- [ ] フルスクリーンの上にも PiP が残る
- [ ] 乗務なし・未ペアでは PiP が出ない
- [ ] 超過は表示だけ（3 択なし）
- [ ] 送信中は「iPhone に送った」。同じ cmd を連打しない
- [ ] Mac の設定から連携を解除できる。吹き出しは未ペアのペアリングに戻る
- [ ] 吹き出しの歯車とメニューバー右クリックが同じ設定ウィンドウを開く
- [ ] ウェブカメラ枠に iPhone を入れて haptic。Mac の Touch ID は自動。iPhone は自分に戻して Face ID
- [ ] ログイン時起動が既定 ON

## リポジトリ secrets（本番リレー）

無いと GitHub Actions の Cloudflare deploy は skip のまま。ゾーン `hibiki-cube.dev` はデプロイ先アカウントに置く。詳細は `sync/worker/README.md`。

- [ ] ゾーン `hibiki-cube.dev` が同じ Cloudflare アカウントにある
- [ ] `CLOUDFLARE_API_TOKEN`（Edit Cloudflare Workers + ゾーンの DNS Edit）
- [ ] `CLOUDFLARE_ACCOUNT_ID`
- [ ] `develop` へ載せて `https://dev.todo-train.hibiki-cube.dev` が出る
- [ ] `main` へ載せて `https://todo-train.hibiki-cube.dev` が出る

## 体験の覆し（SYNC-4 を本採用する前でも可）

[14](14-mac-companion-ux.md) の確認 1–6。確認 1 は吹き出し＋乗務中 PiP、2 は停車と再乗車で確定。3–6 の未回答は提案値のまま。覆すなら 14 を先に更新。

1. 殻はメニューバー accessory でよいか → **確定（吹き出し。ペアリング用の別ウィンドウなし）。乗務中 PiP は追加**
2. 操作は停車だけでよいか → **確定（停車と再乗車）**
3. 乗務なしのときバーはアイコンのみでよいか
4. 超過を Mac で表示だけでよいか
5. 送信中は「送った」で待ってよいか
6. カメラ無し Mac は例外のままでよいか（SYNC-4 では未実装）

## 触らない（意図的）

- CloudKit ゲートを true にする / 有料 ADP
- iPad・系譜可視化
- Hub 10–15 件リマインド、見積 0 分（未決）
- 乗り継ぎキャンバスのゲージ統一（Phase 2）
