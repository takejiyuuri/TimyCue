# TimyCue（仮）

iPhone アプリ。「何時に出ればいいか」を伝える（README を参照）。構想は ChatGPT、作るのは Claude Code。仕様は `docs/spec.md`。
作り方：ネイティブ（SwiftUI、iOS 17 以上、iPhone のみ）。Xcode プロジェクトは Git に入れず、`project.yml` から XcodeGen で作る。
iPhone アプリの手順は iphone-app-release スキル（見つからなければ C:\Users\takej\OneDrive\Desktop\iPhoneアプリ手順書.md）。

## 仕様の扱い
- 何を作るかは `docs/spec.md`（v1.2）と、そのあとに確定した `docs/spec-addendum.md`（追加仕様書。食い違えばこちらが最新）が正。見た目の調整は `docs/design-notes.md`。仕様にないことを勝手に決めない。コードやテストに書く「仕様 §N」は spec.md の番号にする（段階B のコードには前の版の番号が残っているので、触るときに直す）。
- 仕様の【未決】は勝手に決めず、確認してから作る。決めないと進めない点は仮に決めて進めてよいが、必ず「仮に置いた点」として一覧で報告する。ユーザーが ChatGPT と相談して決め、spec.md に書き足す。
- 決めた結果を受け取ったら、spec.md・コード・テストをそろえて直す。
- ChatGPT の差分（変える §、足す §、決まった Q、新しい未決）を貼られたら、spec.md に反映する。§・Q の番号は変えず、新しいものは続きから振る。決まった Q は「決まったことの記録」に日付つきで足す。反映後、コードやテストに関わる点を知らせる。
- コードの構成・ライブラリ・ファイル分けは Claude に任されている。
- ロゴ・アプリアイコン・起動画面・App Store 素材は、`docs/brand/timycue-brand-board.webp`（ブランドボード）が基準（追加仕様書 §46）。独自判断で別案を作らない。手書き調の「TimyCue」はブランド表現だけで、アプリの UI の文字には使わない。

## このアプリの作り方の決まり
- 月カレンダーの吹き出し間のドラッグ＆ドロップによるコピーは廃止。作らない。予定の新規・編集・移動・コピーは 3 分割画面に集める。
- 状態は画面に直書きせず、Store に置く。大きな View を 1 ファイルに詰め込まない。
- 色・フォントサイズ・3 分割の比率・目盛りの間隔などは未決なので、`TimyCue/DesignSystem/` などにまとめて、あとで変えやすい形にしておく。
- 予定は見本のデータ（`TimyCue/Data/SampleEvents.swift`）で動かす。個人の予定を画面写真や審査に使わない。

## 進め方
- 段階に分けて進める。1 段階＝Codemagic で 1 回ビルドして、画面写真で確かめられる大きさ。
- GitHub は takejiyuuri/TimyCue（非公開）。段階ごとにブランチを切る。main へのマージはユーザーの了解を取ってから。
- spec.md の「決まりごと」は自動テスト（`TimyCueTests/`）にする。
- 段階が終わるたびに、Chrome（Claude in Chrome）で Codemagic の「iOS ビルド確認（署名なし）」を始め、結果・テストの件数・画面写真を報告する。赤ならログから直す。

## Codemagic
- アプリ：https://codemagic.io/app/6acb1f56bdf16b04f9d8fc2a （ビルドするブランチを選ぶ。TestFlight へは「iOS → TestFlight」。アプリの Apple ID は 6821819934 で codemagic.yaml に入れてある）
- ワークフロー：`ios-check`「iOS ビルド確認（署名なし）」（テスト・画面写真）と `ios-testflight`「iOS → TestFlight」。どちらも手動で始める。
- 結果：test.log の `Executed N tests` と `** TEST SUCCEEDED **`、画面写真は home / calendar / settings（1320×2868）。Artifacts は 1 つの ZIP で落ちる。ダウンロードはユーザーの了解を取ってから。
- 無料プランは始まるまで 20 分ほど待つことがある。

## してはいけないこと
- 鍵・証明書・パスワード・API キーをチャットにもリポジトリにも置かない。必要なときは、ユーザーが自分で設定する手順を教える。
- Apple・GitHub・Codemagic の本人確認や許可の画面は、ユーザーがやる。そこで止まって知らせる。

## 説明のしかた
- 日本語で、画面のボタン名どおりに書く。途中の一言も含めて、英語で話しかけない。
- ChatGPT や Claude（ほかのセッション）に渡す文章（仮に置いた点・質問・依頼など）は、必ずコードブロック（```）に入れて、そのままコピーできる形で出す。説明の文と混ぜない。
- 大きな作業の前に使用量を確かめ、区切って進める。
