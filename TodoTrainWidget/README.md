# Home Screen Widget — Xcode セットアップ

`TodoTrainWidget/` のソースはリポジトリに置いてあります。Mac で次を実行してください。

1. Xcode → File → New → Target → **Widget Extension**
2. Product Name: `Todo trainWidget`、Include Live Activity: 任意（LA は別ターゲットでも可）
3. 生成されたテンプレートを削除し、`TodoTrainWidget/` 内のファイルをターゲットに追加
4. App Group（任意）: 将来の共有データ用。v1 では Timeline が `.never` でプレースホルダ表示
5. `Todo train` メインターゲットの **Embed Foundation Extensions** に Widget を含める

## v1 表示

- 小: 運行中 / 運休、停車 n 件
- 中: 上記 + 今日の集中ざっくり（プレースホルダ）

実データ連携は App Group + `WidgetCenter.reloadTimelines` を後続で接続してください。

## AlarmKit カウントダウン（v2）

`TodoTrainAlarmLiveActivity.swift` を同じ Extension に追加し、Widget Bundle で束ねてください。手順は [docs/11-v2-alarmkit-setup.md](../docs/11-v2-alarmkit-setup.md) を参照。
