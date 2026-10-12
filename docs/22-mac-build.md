# 22 — Mac の配布ビルド

Apple Developer Program には入っていない。Developer ID 署名と公証はしない。配るのは `CODE_SIGNING_ALLOWED=NO` の Release。リンカが付ける ad-hoc の印は残る。Developer ID ではない。Apple silicon ではこの印を外すと起動できない。

束ねたファイルは `TodoTrainCompanion.app`。Finder の表示名は「Todo train」。スキームは `TodoTrainCompanion`。

PR と `develop` への push では、Mac アプリに関係する変更のときだけ Actions が zip を artifact にする。タグの push では同じ zip を GitHub Release に添付する。ランナーは `xcode-27`（プレビュー、Apple silicon）。開発に使っている Xcode 27.2 に最も近い版を選び、選んだ版をログに出す。

ビルド情報は手元と同じ仕組みで入る。コミット 7 桁、ブランチ、未コミットの有無、作られた時刻（Asia/Tokyo）がメニューの「このビルド」に出る。

Checks から落とす zip の中に、もう一段 zip がある。内側を展開すると `TodoTrainCompanion.app` が出る。Release に付くファイルは内側の zip。

## 初回の起動

ダウンロードした app には macOS が quarantine を付ける。署名も公証もないので、Gatekeeper が初回の起動を止める。手元の Xcode ビルドには quarantine が付かない。

初回だけ、次のどちらか。

1. Finder で `TodoTrainCompanion.app` を右クリックし、「開く」を選ぶ。
2. ターミナルで quarantine を外す。Applications に置いたときは、ファイルのパスが次になる。

```
xattr -d com.apple.quarantine "/Applications/TodoTrainCompanion.app"
```

別の場所に置いたときは、そのファイルのパスにする。

## プレビュー版ランナーが使えないとき

`xcode-27` はプレビューなので、イメージの変更や提供終了でビルドが通らなくなることがある。そのときは自分の Mac をセルフホストランナーにする。

1. リポジトリの Settings → Actions → Runners → New self-hosted runner で macOS の手順を出し、案内どおりに `config.sh` を実行する。
2. ラベル（例: `self-hosted-mac`）を付け、ワークフローの `runs-on` をそのラベルに変える。
3. 公開リポジトリでは、fork からの pull_request をセルフホストで動かさない。ジョブの条件を `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` にする。
4. `run.sh` は必要なときだけ起動する。常駐させるときは `svc.sh install`。

その Mac には Xcode 27 系を入れておく。ワークフローは 27.2 に最も近い版を `xcode-select` で選ぶ。
