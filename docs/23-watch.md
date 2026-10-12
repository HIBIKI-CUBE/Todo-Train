# 23 — Apple Watch

正本は iPhone の open な `WorkSession`。Watch は写しだけを持つ。SwiftData の `@Model` も iCloud も置かない。有料の Apple Developer Program が要る経路は使わない。

写しの経路は WatchConnectivity で、リレーは通さない。中身の形はいまの snap と同じで、答えはいまの cmd と同じ。操作を送ってよいかは約束の版で決める。範囲外の組み合わせでは表示だけにして、答えは送らない。届くときは `sendMessage`、届かないときは `transferUserInfo`。最新の状態は `updateApplicationContext`。

声掛けの列は Mac、その次に iPhone、その次に Watch を 1 台ぶん足す。Watch は iPhone の代わりにしない。上限の 4 回は端末ごとではなく、列全体で数える。ワイヤの `ringSurface` に `watch` を足すのは別の変更で、この骨格は列を変えない。

画面の計器と 4 択、コンプリケーション、Live Activity からの起動は、それぞれの後続で足す。この骨格の Watch アプリは題名と残りと、このビルドを出す。

実機は Apple Watch Ultra 2。Xcode と OS はベータを使う。

## App ID

無料の Apple ID（Personal Team。Apple Developer Program には入っていない）の枠:

- 1 端末に入れられるアプリは 3 本。AltStore をその端末に入れていると、その 1 本を使う。
- App ID は 7 日で 10 個まで。同じ Apple ID の AltStore と枠を分け合う。Xcode の自動署名も、AltStore の My Apps →「View App IDs」も、同じ残りを見る。

Todo列車がいま使っている App ID は 3 個。Watch のウィジェットまで足した計画は 5 個。この骨格で増やすのは 1 個だけ。

| bundle id | 状態 |
|-----------|------|
| `dev.hibiki-cube.Todo-train` | 登録済み。iPhone |
| `dev.hibiki-cube.Todo-train.TodoTrainWidget` | 登録済み。iPhone のウィジェット |
| `dev.hibiki-cube.Todo-train.companion` | 登録済み。Mac |
| `dev.hibiki-cube.Todo-train.watchkitapp` | この骨格で足す Watch アプリ。以後変えない |

Watch のウィジェット拡張は作らない。bundle id は後続で `dev.hibiki-cube.Todo-train.watchkitapp.` の下に 1 つだけ足し、そこで 5 個目になる。

シミュレータ向けの Watch ターゲットは ad-hoc で署名し、Development Team を空にする。シミュレータのビルドでは App ID は増えない。

App ID が新しく 1 個登録されるのは、Personal Team `NPSM864R9U` で iPhone に上書きインストールし、埋め込まれた Watch アプリを実機向けに最初に署名したときである。登録される ID は `dev.hibiki-cube.Todo-train.watchkitapp` だけ。Mac の ID は新しく作らない。7 日 10 個の残りは、その 1 回で 1 個減る。

入れる前に、AltStore の My Apps →「View App IDs」で残りを控える。アプリは消さず、同じ bundle id のまま上書きする（[21](21-device-overwrite.md)）。

最初の実機インストールで、次を記録する。数値は推測で埋めない。

- Watch アプリが、親の iPhone アプリと合わせて 1 端末 3 本の 1 本になるか。Watch 側に別の 3 本枠があるか。
- すでに登録してある Mac の App ID が、7 日 10 個の枠に入っているか。
- Watch から `sendMessage` したとき、iOS 27 で iPhone のアプリが裏で起きるか。
