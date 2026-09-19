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

原画ファイルは置かない。借りるのは Focus と同じ盤と、実機の **初期化の手順**。マスコン・社名・英語の POST・走査線・燐光ブルームは複製しない。実装は `ServiceCabinChrome`。

| 参照 | 借りる点 | 借りない点 |
|------|----------|------------|
| Focus の計器盤 | 格子、ヘッダ、今日の時計、占有の行先票、編成、下の手 | 乗車の残り時間 |
| E233 計器モニタの表示灯（速度計の上。文字が灯） | 矩形の表示灯。運行・占有・停車だけ | ATS 灯、列番、マスコン |
| Garmin G1000 PFD power-up（[Pilots Guide 1.5](https://static.garmin.com/pumac/190-00498-08_0A_Web.pdf)） | 表示灯が順に点いてため、一つずつ実状態へ落ちる。時計は実時刻のまま灯る | ロゴ、AHRS 英文、赤い X、無効のダッシュ桁 |
| 自動車クラスタの BIT | 針が振り切ってため、実値に戻る。秒尺も別の速さで同じ手順 | 888888、ダミーランプの洪水 |
