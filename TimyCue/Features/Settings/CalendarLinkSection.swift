import EventKit
import SwiftUI

/// 設定 ＞ カレンダー連携 のいちばん上（spec §89.6・Q101・Q115。S6）。
/// フルアクセスがあれば「Appleカレンダー連携」の ON/OFF のスイッチを出す。OFF はエラーではない正常な選択なので、OFF にするたびの確認は出さない。
/// フルアクセスがなくても項目は隠さず、「Appleカレンダーを連携する」の入口を出す。連携 OFF のあいだに許可が外れても警告は出さない（Q101）。
/// 説明の文は仮（例文の「Appleカレンダー連携」「Appleカレンダーを連携する」は決定のまま）
struct CalendarLinkSection: View {
    @Environment(CalendarConnection.self) private var connection
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if connection.hasFullAccess {
                Toggle(isOn: Binding(get: { connection.isLinkEnabled },
                                     set: { enabled in _ = connection.setAppleLinkEnabled(enabled) })) {
                    Text("Appleカレンダー連携")
                }
                .tint(Theme.Colors.accent)
                // 保存できずに戻したとき、スイッチの見た目も戻す（spec §89.9）
                .id(connection.settingsRevision)
            } else if connection.authorization == .restricted {
                Text("この端末では Apple カレンダーを使えません。新しい予定は \(SaveTargetRules.timyCueOnlyLabel)に保存します。")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                // 連携 ON のまま許可がない（拒否・追加のみ）ときだけ、許可の説明を出す。わざと OFF にしているときは出さない（Q101）
                if connection.isLinkEnabled && connection.state == .denied {
                    Text(permissionText)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Button("Appleカレンダーを連携する") { link() }
            }
        } header: {
            Text("Apple カレンダー")
        } footer: {
            if connection.hasFullAccess {
                Text(connection.isLinkEnabled ? Self.onNote : Self.offNote)
            }
        }
    }

    /// 連携を ON として保存してから、まだ許可を求めていなければ iOS の許可を求め、拒否・追加のみなら設定アプリを開く
    /// （OFF のあいだに許可が外れていたら、ON に戻そうとしたこのときに許可を案内する。Q101）
    private func link() {
        guard connection.setAppleLinkEnabled(true) else { return }
        switch connection.authorization {
        case .notDetermined:
            Task { await connection.connect() }
        case .denied, .writeOnly:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        default:
            break
        }
    }

    private var permissionText: String {
        connection.authorization == .writeOnly
            ? "予定の追加だけが許可されています。Apple カレンダーの予定を読み込むには、iPhone の設定でカレンダーを「フルアクセス」にしてください。それまで新しい予定は \(SaveTargetRules.timyCueOnlyLabel)に保存します。"
            : "カレンダーへのアクセスが許可されていません。iPhone の設定から許可してください。それまで新しい予定は \(SaveTargetRules.timyCueOnlyLabel)に保存します。"
    }

    /// 連携 ON の説明（Apple の予定が TimyCue で非表示になること・Apple 側では削除されないこと。spec §89.6）
    private static let onNote = "OFF にすると、TimyCue は Apple カレンダーの予定を読み込まず、書き込みもしません。Apple カレンダーの予定は削除されません。iPhone のカレンダーの許可や iCloud の設定は変わりません。"
    /// 連携 OFF の説明
    private static let offNote = "Appleカレンダー連携は OFF です。Apple カレンダーの予定は TimyCue に表示していませんが、Apple カレンダーからは削除されていません。新しい予定は TimyCue のみ（このiPhone）に保存します。"
}

/// 連携していないとき（連携 OFF・許可なし）の新しい予定の保存先（spec §89.2：連携 OFF・許可なしのときは「TimyCue のみ」だけ）。
/// 選べない 1 行で出す。前に選んでいた Apple の保存先は消さずに覚えていて、連携すると戻ることを案内する（spec §89.6・§89.8・Q103。文言は仮）
struct UnlinkedSaveTargetSection: View {
    @Environment(CalendarConnection.self) private var connection

    var body: some View {
        Section {
            LabeledContent("新しい予定の保存先", value: SaveTargetRules.timyCueOnlyLabel)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(SaveTargetRules.timyCueOnlyNote)
                if let note = returnNote {
                    Text(note)
                }
            }
        }
    }

    /// 連携したときの保存先の案内（覚えている保存先の種類による）
    private var returnNote: String? {
        let action = connection.hasFullAccess ? "連携を ON にすると" : "カレンダーへのアクセスを許可して連携すると"
        switch connection.preferences.saveTargetKind {
        case .appleCalendar?:
            return "\(action)、前に選んでいた Apple カレンダーの保存先に戻ります。"
        case .askBeforeSaving?:
            return "連携したあと、初めて予定を保存するときに保存先を選びます。"
        case .timyCueOnly?, nil:
            return nil
        }
    }
}
