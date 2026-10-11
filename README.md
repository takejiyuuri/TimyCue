# TimyCue（仮）

カレンダーは予定を書く。TimyCue は予定に間に合わせる。

予定時刻・場所・現在地・移動手段などから「何時に出ればいいか」を伝える iPhone アプリ（SwiftUI、iOS 17 以上、iPhone のみ）。

## いまの段階

段階 C-1：**カレンダータブそのものが 3 分割画面**（左上：時間画面／右上：入力画面／下：カレンダー）。予定の閲覧・新規・編集・コピーをこの 1 画面で行い、
閲覧／編集の切り替えは作らない（内部の状態として new / edit / copy を持つ）。今は 3 領域の配置・別々のスクロール・キーボード表示時の比率まで。
ホームと設定は仮の画面。予定は見本のモックデータ（`TimyCue/Data/SampleEvents.swift`）。Apple カレンダー・位置情報・天気・Live Activity にはまだ繋いでいない。

## 構成

| 場所 | 役割 |
|---|---|
| `project.yml` | XcodeGen の設定。Xcode プロジェクトは Git に入れず、ここから作る |
| `TimyCue/App/` | 入口と下部タブ |
| `TimyCue/DesignSystem/` | 色・角丸・余白（値は仮。決まったらここだけ差し替える） |
| `TimyCue/Model/` | 予定・日付・予定色などのデータ |
| `TimyCue/Data/` | 予定の読み書き（今はメモリ上のモック。後で EventKit 版に差し替え） |
| `TimyCue/Prediction/` | 「予測で一括」の入口（今はモック） |
| `TimyCue/Features/ScheduleEditor/` | カレンダータブの 3 分割画面。状態管理（`ScheduleEditorStore`）、比率（`EditorLayout`、値は仮）、時間画面・入力画面・カレンダー |
| `TimyCueTests/` | 自動テスト |
| `tools/make_icon.py` | 仮のアプリアイコンを作る（`python tools/make_icon.py`） |
| `codemagic.yaml` | クラウドの Mac でのビルド・テスト・画面写真・TestFlight 送信 |
| `docs/ios-release.md` | Mac なしで App Store に出す手順 |

## 作り方の決まり

- 仕様にない画面や動きは足さない。仕様の【未決】は勝手に決めず、確認してから作る。
- 月カレンダーの吹き出し間のドラッグ＆ドロップによるコピーは**廃止。作らない**。予定の新規・編集・移動・コピーは 3 分割画面に集める。
- カレンダータブと予定編集画面を別の画面に分けない。閲覧モード／編集モードの切り替えも作らない。
- 状態は画面に直書きせず、Store に置く。大きな View を 1 ファイルに詰め込まない。
- 色・フォントサイズ・3 分割の比率・目盛りの間隔などは未決なので、あとで変えやすい形にしておく。

## ビルドと確認

Mac がないので、Codemagic の「iOS ビルド確認（署名なし）」でビルド・自動テスト・シミュレータの画面写真まで確かめる。
iPhone で触るときは「iOS → TestFlight」。手順は `docs/ios-release.md`。
