# 車内案内パネル — 視覚品質の棒とリファレンス

日付: 2026-10-06  
用途: 乗客モード（[#66](https://github.com/HIBIKI-CUBE/Todo-Train/issues/66)）実装・レビュー時に、「マルス切符と同じく元ネタが一瞬で分かるか」を揃える。商標の複製ではなく公共の視覚文法の密度を測る。

方向は [18](18-passenger-cabin-direction.md)。設計と受け入れは [19](19-passenger-interval-design.md)。同梱ファイルと「置いてよいもの」の線引きは [references/passenger-lcd/README.md](references/passenger-lcd/README.md)。この文書は乗客 UI を実装しない。

---

## 切符側との対応（品質の型）

マルス切符は JR ロゴを描かずに分かる。やっていることは比率・水色紙・角・縦シリアル・印字階層・排出モーションである。

車内案内も同じ型にする。

| 切符 | 車内案内 |
|---|---|
| 85×57.5 比率 | 16:9 寄りの横長パネル |
| 水色固定紙 | 白〜淡色の情報面＋固定インク色 |
| ほぼ直角の角 | 薄いベゼル感・角ほぼ直角（iOS カード角丸にしない） |
| 縦紫シリアル | 端の細いメタ帯（非中心情報） |
| スロット排出 | 状態切替フェード／開扉矢印アニメ |
| JR ロゴ地紋なし | 実路線図・ロゴなし／自作ストリップのみ |

---

## 一瞥チェック（必須）

レビュー時、実機またはシミュレータで次が **一目で** 成立していること。

1. 状態語が **次は / まもなく / ただいま** のいずれか（旅客視点。運転台語彙ではない）
2. 横長二帯: 上＝状態＋大きな区間名（予定題名）、下＝進捗または開扉矢印
3. 路線色の進捗ストリップ（自作色可。実 JR 路線色のトレース禁止）
4. JP 大 + EN 小
5. 「まもなく」または終盤で **開扉側の矢印** が見える
6. `.rounded` フォントやマルス水色紙を案内背景に流用していない
7. 非常用ドアコックが隅にあり、ラベルが読める

不合格の例: SaaS カードっぽい縦リスト、状態語なしのタイトルだけ、切符券面の流用、JR ウグイス色の直写し、発車メロディ。

---

## 公開リファレンス（設計メモ用）

アプリのアセットには画像を同梱しない。設計・レビューの照合用に、記事自身が図として出しているもののうち引用として置ける最小限だけを `docs/references/passenger-lcd/` に置く。二次利用を禁じるファンサイトはリンクのみ（画像は置かない）。

### 一次・準一次

- [日立評論・E235 ドア上 LCD（日本語）](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/index.html) — 画面分担、異常時、円弧案内の思想
- [Hitachi Review 英語 PDF（現行）](https://www.hitachi.com/content/dam/hitachi/global/en/insights/media/hitachihyoron/2021/r2021_05/05a09.pdf) — 同記事の英語版。旧 HTML（`hitachihyoron.com/rev/.../05a09/`）は移設案内になることがある
- [三菱電機 トレインビジョン PR PDF（2017）](https://www.mitsubishielectric.co.jp/ja/pr/pdf/2017/1121-b.pdf)
- [JEKI トレインチャンネル媒体](https://www.jr-ad.net/tokyo/digital-signage/train-channel/)
- [Wikipedia トレインチャンネル](https://ja.wikipedia.org/wiki/トレインチャンネル) — 右案内／左広告、時間帯での情報削減
- [Wikipedia VIS（鉄道システム）](https://ja.wikipedia.org/wiki/VIS_(鉄道システム))

### 構図・フォント観察（二次。直リンク複製禁止の記載に従う）

- [藝術書庫・E235 山手 LCD 再現](https://artificium.blog.fc2.com/blog-entry-126.html)
- [FreedomTrain・フォント整理（三菱 vs 日立）](https://freedomtrain.jp/mamouna_owo/10245/)
- [FreedomTrain・E233「新」LCD](https://freedomtrain.jp/mamouna_owo/48152/)

### 取る文法 / 取らないもの

**取る:** 次は→まもなく→ただいま、横一列進捗で通過済みグレー、残り分、状況に応じた情報削減、案内と広告の画面分担（案内は乗っ取られない）。

**取らない:** JR／トレインビジョンロゴ、実メロディ・チャイム、実路線図・駅ナンバリング、4言語切替アニメ、ドアイラストの過剰再現、運転台 TIMS UI。

---

## 完成比較の手順（レビュー用）

1. マルス切符の発行画面を一枚撮る（「元ネタが分かる」基準の感覚合わせ）。
2. 乗客案内の「ただいま」（乗車中）を一枚撮る。
3. 「まもなく」＋開扉矢印を一枚撮る。
4. Hub 切符面と並べ、色温度・角・紙／液晶の材質感が混ざっていないか見る。
5. 上の一瞥チェック 1–7 を全部通す。
6. 同梱の引用図（下の一覧）と並べ、状態語・横長・大きな題名・進捗・開扉方向が同型か見る。路線・駅番号・ロゴは写さない。

数字の点数やコンボ表示は通常画面に出さない（既存契約）。品質は見た目の文法密度で測る。

---

## 添付・参照一覧

取得日はすべて **2026-10-06**。同梱図の但し書きは「引用・参照用。商標・路線図のトレース用途ではない」。アプリの画像アセットにはしない。詳細な線引きは [references/passenger-lcd/README.md](references/passenger-lcd/README.md)。

### リポジトリ内（引用図）

| ファイル | 何を見るか | 出典 |
|----------|------------|------|
| [hitachi-hyoron-2021-fig05-tsugiha.png](references/passenger-lcd/hitachi-hyoron-2021-fig05-tsugiha.png) | 「次は」、大きな行先、円弧の進捗、開扉方向 | 日立評論 2021年3月 図5。元ファイル [fig_05.png](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_05.png)。記事 [日本語](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/index.html) |
| [hitachi-hyoron-2021-fig06-tadaima.png](references/passenger-lcd/hitachi-hyoron-2021-fig06-tadaima.png) | 「ただいま」、状態帯＋大きな駅名、下段の補助 | 同記事 図6。元ファイル [fig_06.png](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_06.png) |

図5・図6には実在の駅名と駅ナンバリングが写る。図6には路線記号も写る。文法の照合だけに使い、トレース・切り出し・色の写しはしない。

### 外部 URL（リンクのみ。ファイルは置かない）

| 参照 | URL | 見てよいこと |
|------|-----|----------------|
| 日立評論・同記事の図1 | [記事](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/index.html) / [fig_01.png](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_01.png) | ドア上の二画面（案内と広告の分担）、「ただいま」。左画面に社名ロゴが写るため同梱しない |
| 同・図2 | [fig_02.png](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_02.png) | 車上システムの構成。視覚文法の原画ではない |
| 同・図3 | [fig_03.png](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_03.png) | 窓上広告の掲出。広告写真のため同梱しない |
| 同・図4 | [fig_04.png](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_04.png) | 異常時に案内が広告を上回る思想。4言語全面は取らない |
| 同・図7・図8 | [fig_07](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_07.png) / [fig_08](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_08.png) | 向きと分岐の見せ方。実路線図のため同梱しない |
| 同・図9 | [fig_09.png](https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_09.png) | 掲出位置。乗客面の画面文法ではない |
| Hitachi Review 英語 PDF | [05a09.pdf](https://www.hitachi.com/content/dam/hitachi/global/en/insights/media/hitachihyoron/2021/r2021_05/05a09.pdf) | 同内容の英語。PDF 自体は置かない |
| 三菱電機トレインビジョン PR | [1121-b.pdf](https://www.mitsubishielectric.co.jp/ja/pr/pdf/2017/1121-b.pdf) | 車内 LCD の製品説明。PDF・ロゴは置かない |
| JEKI トレインチャンネル | [媒体ページ](https://www.jr-ad.net/tokyo/digital-signage/train-channel/) | 媒体としての画面分担。ブランド素材は置かない |
| Wikipedia トレインチャンネル | [記事](https://ja.wikipedia.org/wiki/トレインチャンネル) | 右案内／左広告、時間帯で情報を減らす、という公開された説明 |
| Wikipedia VIS | [記事](https://ja.wikipedia.org/wiki/VIS_(鉄道システム)) | 車内案内システムの系譜。本文の引き写しはしない |
| 藝術書庫 | [E235 山手 LCD 再現](https://artificium.blog.fc2.com/blog-entry-126.html) | レイアウト観察のみ。画像は取得しない |
| FreedomTrain | [フォント整理](https://freedomtrain.jp/mamouna_owo/10245/) / [E233 LCD](https://freedomtrain.jp/mamouna_owo/48152/) | 書体の違いの観察のみ。画像・フォントファイルは取得しない |
