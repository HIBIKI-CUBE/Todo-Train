# 車内案内の引用（乗客モード）

実装の原画フォルダではない。乗客案内の視覚文法を、公開記事と照合するための引用だけを置く。アプリのアセットにはコピーしない。

但し書き（同梱図すべて）: **引用・参照用。商標・路線図のトレース用途ではない。**

方向・設計・一瞥チェックは [18](../../18-passenger-cabin-direction.md)・[19](../../19-passenger-interval-design.md)・[20](../../20-passenger-lcd-quality-refs.md)。実装は [Issue #66](https://github.com/HIBIKI-CUBE/Todo-Train/issues/66) の別作業。

## 置いてよいもの

著作権法上の引用として、記事自身が図として掲出している画像のうち、状態語（次は／ただいま）と横長の情報階層を見るのに必要な最小限。改変しない。出所と取得日をこの表に残す。

| ファイル | 出典 URL | 取得日 | 見てよいこと | 使わないこと |
|----------|----------|--------|--------------|--------------|
| [hitachi-hyoron-2021-fig05-tsugiha.png](hitachi-hyoron-2021-fig05-tsugiha.png) | 日立評論 2021年3月「高機能型LCD表示器を活用した鉄道車内案内におけるDXの推進」図5。元画像 <https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_05.png>。記事 <https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/index.html> | 2026-10-06 | 「次は」、大きな行先、円弧の進捗、開扉方向 | 駅名・ナンバリング・路線形状のトレース |
| [hitachi-hyoron-2021-fig06-tadaima.png](hitachi-hyoron-2021-fig06-tadaima.png) | 同記事 図6。元画像 <https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/image/fig_06.png> | 2026-10-06 | 「ただいま」、上段の状態＋大きな駅名、下段は補助 | 駅設備図・路線記号・ナンバリングの切り出し |

著作権は日立評論社（日立製作所）に帰属する。日立のサイト利用条件は、私的使用その他著作権法で認められる場合を除き、許諾のない複製・公衆送信を禁じている。ここでの図は、乗客案内の文法を批評・照合する本文（docs/18–20）に従属する引用であり、記事の転載ではない。

## リンクだけ（ファイルは置かない）

| 出典 | URL | 条件のメモ | 見てよいこと |
|------|-----|------------|--------------|
| 日立評論・同記事（図1・2・3・4・7・8・9） | <https://www.hitachihyoron.com/jp/archive/2020s/2021/03/03a09/index.html> | 上と同じ。図1は社名ロゴが画面に写る。図3は広告の掲出写真。図7・図8は実路線図が主題 | 二画面の分担、異常時に案内が勝つこと、分岐の考え方。ロゴと路線図は持ってこない |
| Hitachi Review 英語 PDF | <https://www.hitachi.com/content/dam/hitachi/global/en/insights/media/hitachihyoron/2021/r2021_05/05a09.pdf> | 英語版の現行ファイル。旧 HTML は移設案内になることがある | 同内容の英語での照合。PDF は同梱しない |
| 三菱電機・トレインビジョン PR（2017-11-21） | <https://www.mitsubishielectric.co.jp/ja/pr/pdf/2017/1121-b.pdf> | 広報 PDF。製品名は三菱電機の商標 | 車内 LCD という製品カテゴリの説明。ロゴ・図版・PDF は同梱しない |
| JEKI・トレインチャンネル | <https://www.jr-ad.net/tokyo/digital-signage/train-channel/> | 広告媒体の営業ページ。ブランド資産の再配布はしない | 案内と広告が画面を分ける、という媒体の説明。ロゴ・キービジュアルは持ってこない |
| Wikipedia・トレインチャンネル | <https://ja.wikipedia.org/wiki/トレインチャンネル> | 本文は CC BY-SA 4.0。記事本文の引き写しはしない。ページ内画像のライセンスはファイルごとに別 | 右が案内、左が広告、時間帯で情報を減らす、という公開された説明へのリンク |
| Wikipedia・VIS | <https://ja.wikipedia.org/wiki/VIS_(鉄道システム)> | 同上 | 車内映像情報システムの系譜へのリンク |
| 藝術書庫（artificium） | <https://artificium.blog.fc2.com/blog-entry-126.html> | ファンサイト。画像の再配布はしない | 画面割りの観察だけ。画像は取得しない |
| FreedomTrain・フォント整理 | <https://freedomtrain.jp/mamouna_owo/10245/> | ファンサイト。画像・フォントの再配布はしない | 案内書体がメーカーで違う、という観察だけ |
| FreedomTrain・E233 LCD | <https://freedomtrain.jp/mamouna_owo/48152/> | 同上 | 世代による画面の違いの観察だけ |

## 置かないもの

- JR の社名ロゴ、トレインチャンネル／トレインビジョンのブランド資産
- 商用フォント、発車メロディ、チャイム
- ファンサイトの画像（上の二サイトはリンクのみ）
- 実路線図・駅ナンバリングをなぞるためのトレース元としての利用
- このリポジトリが作った偽の JR 画面

同梱の図5・図6にそれらが写り込んでいても、切り出さない。実装が借りるのは状態語・横長・大きな題名・進捗・開扉方向だけである。
