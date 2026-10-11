# iOS アプリ「TimyCue」を Mac なしで App Store へ出す手順

Windows だけで開発し、ビルドはクラウドの Mac（Codemagic）で行い、App Store Connect → TestFlight → App Store へ進める。
Apple と Codemagic の操作は、すべてブラウザでできる（Mac も Xcode も使わない）。
JWWミテハカールで通した手順（iphone-app-release）に合わせている。違いは「Web を Capacitor で包む」代わりに SwiftUI で直接作る点だけ。

```
Windows（コードを書く） → GitHub（push） → Codemagic（クラウドの Mac でビルド・署名）
  → App Store Connect（ビルドを受け取る） → TestFlight（iPhone で試す） → 審査 → App Store
```

## 仕組み

- Xcode プロジェクト（`TimyCue.xcodeproj`）は Git に入れない。文字だけの `project.yml` を書き、Codemagic の Mac で
  `xcodegen generate` を実行して毎回作る（`.pbxproj` を手で直すと壊れやすいため）。
- Windows では動かせないので、確認は Codemagic の「iOS ビルド確認（署名なし）」で行う。ビルド・自動テスト・シミュレータの
  画面写真（6.9 インチの Pro Max）まで撮る。触り心地は TestFlight で iPhone に入れて確かめる。

## 決まっている値

| 項目 | 値 |
|---|---|
| Bundle ID | `io.github.takejiyuuri.timycue`（最初のアップロード後は変えられない） |
| App Store での名前 | `TimyCue` |
| ホーム画面の名前（CFBundleDisplayName） | `TimyCue` |
| 最小 iOS | 17.0 |
| 対応端末 | iPhone のみ（`TARGETED_DEVICE_FAMILY=1`） |
| SKU | `timycue-app`（管理用。iPhone / iOS の文字を入れない） |
| Codemagic の API キーの名前 | `codemagic-asc`（JWWミテハカールと共通） |

## 1. Codemagic でビルドを確かめる（最初に 1 回）

1. https://codemagic.io を開き、ミテハカールと同じ GitHub アカウントでログインする。
2. 左の **Apps** → 右上の **Add application**。
3. Git provider で **GitHub** を選び、一覧から **`takejiyuuri/timycue`** を選ぶ。
   - 出てこないときは **Configure GitHub App**（または Manage repository access）を押し、GitHub の画面で `timycue` を許可して戻る。
4. Project type は **Other**（codemagic.yaml を使う）→ **Finish: Add application**。
5. アプリの画面で右上の **Start new build**。
6. Branch を選び、Workflow で **iOS ビルド確認（署名なし）** を選ぶ。一覧が切れて見えないときは、検索欄に「iOS ビルド確認」と打つ。
7. **Start new build**。全部の行に緑のチェックが付けば成功。終わった画面の **Artifacts** に画面写真（home / calendar / settings）とテストのログが並ぶ。

## 2. Apple 側の準備（最初に 1 回）

JWWミテハカールで済んでいるもの（流用する）：Apple Developer Program、App Store Connect API キー、Apple Distribution の証明書、
ビジネス（有料 App 契約・口座・税務）、EU DSA の申告。**API キーの .p8 はチャットにもリポジトリにも置かない。**

### 2-1. Bundle ID を登録する
1. https://developer.apple.com/account → **Certificates, IDs & Profiles** → 左の **Identifiers**。
2. 「Identifiers」の横の青い **＋** → **App IDs** → **Continue** → **App** → **Continue**。
3. Description：`TimyCue`／Bundle ID：**Explicit** で `io.github.takejiyuuri.timycue`／Capabilities：何も付けない。
4. **Continue** → **Register**。

Live Activity を入れる段階で、ウィジェット用の Bundle ID（例：`io.github.takejiyuuri.timycue.widgets`）とプロファイルをもう 1 組作る。

### 2-2. App Store Connect にアプリを登録する
1. https://appstoreconnect.apple.com → **アプリ** → 左上の青い **＋** → **新規 App**。
2. プラットフォーム：**iOS**／名前：`TimyCue`／プライマリ言語：**日本語**／バンドル ID：2-1 のもの／SKU：`timycue-app`／
   ユーザアクセス：**フルアクセス** → **作成**。
   - **名前・サブタイトル・キーワード・画面写真の文字に iPhone / iPad / iOS / Apple を入れない**（ミテハカールは 5.2.5 で一度却下された）。
3. 左の **App 情報** → 「一般情報」の **Apple ID**（数字）を控える。最初の 1 本が TestFlight に届いたら、
   `codemagic.yaml` の `APP_STORE_APPLE_ID` の行の `#` を消して数字を入れ、push する。

### 2-3. Codemagic に App Store 用プロファイルを取り込む
1. Codemagic 左下のチーム名 → **Team settings** → **codemagic.yaml settings** → **Code signing identities**。
2. **iOS certificates** に Apple Distribution の証明書があるのを確かめる（無ければ **Generate certificate**）。
3. **iOS provisioning profiles** → **Fetch profiles** → `io.github.takejiyuuri.timycue` の **App Store** 用を取り込む。
   - 出ないとき：Apple Developer の **Profiles** → **＋** → Distribution の **App Store Connect** → **Continue** →
     App ID に TimyCue → 証明書を選ぶ → 名前 `TimyCue App Store` → **Generate**。その後もう一度 **Fetch profiles**。

## 3. TestFlight で iPhone に入れる（版ごと）

1. Codemagic の TimyCue → **Start new build** → Workflow に **iOS → TestFlight**（見えなければ検索欄に「TestFlight」）→ 開始。
2. 成功すると App Store Connect にビルドが届く。使えるようになるまで数分〜数十分。
3. 初回だけ：App Store Connect → TimyCue → **TestFlight** → 左の **内部テスト** の横の **＋** でグループを作り、自分を追加。
   **グループの「自動配信」をオンにする**（オフだと新しいビルドが iPhone に届かない）。
4. iPhone の **TestFlight** アプリで TimyCue の **インストール**。「1.0 (3)」の括弧がビルド番号（番号は飛んでよい）。

## 4. 版を上げる

- 版番号は `project.yml` の `MARKETING_VERSION`（今は `1.0`）。新しい版を出すときに上げてコミットする。
- ビルド番号は Codemagic が自動で決める（TestFlight の最新＋1 と Codemagic の通し番号の大きいほう）。

## 5. 審査に出す前に

- 審査の人が触れるように、カレンダーの許可が無くても見本の予定で 3 分割画面を使えるようにする。
- カレンダー・位置情報・通知の許可は使う時に聞き（Just-in-Time）、断られてもアプリ全体は使えるようにする。説明文は日本語で具体的に。
- 画面写真は 6.9 インチ（1320×2868）。見本データだけで撮り、個人の予定は写さない。
- サポート URL・プライバシーポリシーは、別の公開リポジトリ（例：`timycue-support`）の GitHub Pages に置き、問い合わせは Google フォーム。
- App のプライバシー：位置履歴は端末の中で使い外へ送らない設計なので「データを収集しない」の見込み。iCloud 同期を入れる段階でもう一度確かめる。
- 年齢制限は全部「いいえ」で 4+、EULA は Apple 標準、ルーティングアプリカバレッジファイルは空、リリースは「手動でリリース」。
- 2.1 Information Needed になったら、iPhone 実機・最新 iOS の画面収録（ホーム画面から起動して普段の使い方）を撮り、英文で返信する。

## うまくいかないとき

- まず「iOS ビルド確認（署名なし）」で通るかを見る。通るなら署名の設定（API キーの名前、証明書、プロファイルの Bundle ID）を見直す。
- 「無効な yaml 設定」と出たら `codemagic.yaml` の書き方の誤り。赤い印を押すと場所が出る（`""` の空の値は書けない）。
- `xcodegen generate` で失敗したら `project.yml` の書き方の誤り。ログの行番号を見る。
