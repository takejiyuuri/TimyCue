# TimyCue（仮）

カレンダーは予定を書く。TimyCue は予定に間に合わせる。

予定時刻・場所・現在地・移動手段などから「何時に出ればいいか」を伝える iPhone アプリ（SwiftUI、iOS 17 以上、iPhone のみ）。

仕様は [docs/spec.md](docs/spec.md)（v1.0）。コードの「仕様 §N」はその番号、「Q1」などは spec.md の「決まったことの記録」を指す。

## いまの段階

第 2 段階：カレンダータブの月カレンダー（週を途切れず縦に連続表示・左端の月表示列と固定表示・上部の年・曜日固定・今日の丸・予定の出し方・重ならない吹き出し 2 つ）と 1 日タイムライン（指の位置を中心にピンチで拡大・現在時刻の線・重なる予定の横分け・終日専用帯）、予定詳細（見るだけ）まで。
予定登録・編集・コピーの 3 分割画面は**状態管理**だけで、画面はまだ。ホームと設定は仮の画面。
予定は見本のモックデータ（`TimyCue/Data/SampleEvents.swift`）。Apple カレンダー・位置情報・天気・Live Activity にはまだ繋いでいない。

## 構成

| 場所 | 役割 |
|---|---|
| `project.yml` | XcodeGen の設定。Xcode プロジェクトは Git に入れず、ここから作る |
| `TimyCue/App/` | 入口と下部タブ |
| `TimyCue/DesignSystem/` | 色・角丸・余白（値は仮。決まったらここだけ差し替える） |
| `TimyCue/Model/` | 予定のデータ。Apple カレンダーと共有する部分（`CalendarEvent`）と TimyCue だけの情報（`TimyCueEventMetadata`）を分けて持つ（仕様 §84） |
| `TimyCue/Data/` | 予定の読み書き（今はメモリ上のモック。後で EventKit 版に差し替え） |
| `TimyCue/Prediction/` | 「予測で一括」の入口（今はモック） |
| `TimyCue/Features/Calendar/` | カレンダータブ：週を縦につなげる月カレンダー・日付吹き出し・1 日タイムライン（`CalendarStore`。仕様 §18〜§30・v1.1・Q8〜Q20） |
| `TimyCue/Features/EventDetail/` | 予定詳細（見るだけ。編集は「編集」から 3 分割画面へ。v1.1・Q17） |
| `TimyCue/Features/ScheduleEditor/` | 3 分割画面の状態管理（`ScheduleEditorStore`） |
| `TimyCueTests/` | 自動テスト |
| `tools/make_icon.py` | 仮のアプリアイコンを作る（`python tools/make_icon.py`） |
| `codemagic.yaml` | クラウドの Mac でのビルド・テスト・画面写真・TestFlight 送信 |
| `docs/ios-release.md` | Mac なしで App Store に出す手順 |

## 作り方の決まり

- 仕様にない画面や動きは足さない。仕様の【未決】は勝手に決めず、確認してから作る。
- 月カレンダーの吹き出し間のドラッグ＆ドロップによるコピーは**廃止。作らない**。予定の新規・編集・移動・コピーは 3 分割画面に集める。
- 状態は画面に直書きせず、Store に置く。大きな View を 1 ファイルに詰め込まない。
- 色・フォントサイズ・3 分割の比率・目盛りの間隔などは未決なので、あとで変えやすい形にしておく。

## ビルドと確認

Mac がないので、Codemagic の「iOS ビルド確認（署名なし）」でビルド・自動テスト・シミュレータの画面写真まで確かめる。
iPhone で触るときは「iOS → TestFlight」。手順は `docs/ios-release.md`。
