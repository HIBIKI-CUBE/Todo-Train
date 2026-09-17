# 原画（祝祭・行先票の参照）

実装は骨格だけ借りる。社名・地紋・ナンバリング・ローマ字は複製しない。

## 切符

| ファイル | 種別 | 使い方 |
|----------|------|--------|
| [mars-joshaken.png](mars-joshaken.png) | マルス 8.5cm 乗車券 | **発行・到着の主原画**（水色地紋・発着主役・使用済みは穴と印） |
| [edmondson-shizuoka.png](edmondson-shizuoka.png) | 近距離エドモンソン | サイズ・鮭色は使わない。端の縦組みと未使用の清潔さだけ借りる |

実装定数: `MarsTicketSpec` / `MarsTicketView`。JR ロゴ地紋は複製しない。

## 駅名標

Commons の写真。借りるのは **題名が主、番号欄、路線色の帯**。隣駅・社名・駅コード・ローマ字・路線図は使わない。実装は `OccupancyDestinationSign`。

| ファイル | 出典 | 借りる点 |
|----------|------|----------|
| [station-sign-jr-shimbashi.jpg](station-sign-jr-shimbashi.jpg) | JR 山手線 新橋（吊下） [Wikimedia](https://commons.wikimedia.org/wiki/File:JREast-Yamanote-line-JY29-Shimbashi-station-sign-20170928-151916.jpg) MaedaAkihiko, CC BY-SA 4.0 | 字間の開いた駅名、左の番号欄、路線色の横帯 |
| [station-sign-keikyu-shinagawa.jpg](station-sign-keikyu-shinagawa.jpg) | 京急 品川（吊下） [Wikimedia](https://commons.wikimedia.org/wiki/File:Keikyu-KK01-Shinagawa-station-sign-20251011-134353.jpg) MaedaAkihiko, CC BY-SA 4.0 | 暗い地に白い駅名。帯の代わりに罫 |
| [station-sign-hankyu-sannomiya.jpg](station-sign-hankyu-sannomiya.jpg) | 阪急 神戸三宮（吊下） [Wikimedia](https://commons.wikimedia.org/wiki/File:Kobe-Sannomiya_Station_Sign_(Hankyu).jpg) そらみみ, CC BY-SA 3.0 | 暗い板、駅名が主、番号は円 |
| [station-sign-metro-akasaka.jpg](station-sign-metro-akasaka.jpg) | 東京メトロ 赤坂（壁） [Wikimedia](https://commons.wikimedia.org/wiki/File:TokyoMetro-C06-Akasaka-station-sign-20220315-151712.jpg) MaedaAkihiko, CC BY-SA 4.0 | 上段の駅名帯と番号だけ。下の路線図は使わない |

## 運行の機体（起動／シャットダウン）

原画ファイルは置かない。密度と間は演出として借りてよい。意味は運行中・占有・今日の跡。マスコン・社名・英語の POST は複製しない。実装は `ServiceCabinChrome`。

| 参照 | 借りる点 | 借りない点 |
|------|----------|------------|
| JR E233 運転台・TIMS（グラスコックピット。計器モニタの上段が [表示灯](https://ja.wikipedia.org/wiki/TIMS)） | ランプバンク、沈んだ井戸、画面の下にキー | マスコン、列番、社名、実画面の複製 |
| 戦闘機 HUD のコーナブラケット（Cobra / HUD combiner） | 井戸の L 字枠 | 照準・数値の洪水、英語ステータス |
| *Alien* のノーストロモ、*Alien: Isolation* の CRT | 燐光、走査線、暗い間をおいて灯る | 英語 SYSTEMS ONLINE、故障ウィザード |
| *2001* の Discovery、*Interstellar* の Endurance | 長めの暗転、幾何のパネル、落とすキー | オレンジ HUD、点数 |
