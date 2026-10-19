import EventKit
import SwiftUI

/// 設定 ＞ カレンダー連携 のいちばん上（spec §89.6・Q101・Q115。S6）。
/// 「Appleカレンダー連携」の ON/OFF のスイッチは、iPhone のカレンダーの許可の状態によらず出す（許可がなくても OFF にできる。2026-10-19 決定 2）。
/// OFF はエラーではない正常な選択なので、OFF にするたびの確認は出さない。フルアクセスがなければ「Appleカレンダーを連携する」の入口も出す。
/// TimyCue の連携の設定と iPhone のカレンダーの許可は別の状態として、両方を出す（2026-10-19 ユーザー指示 4）。ON でもフルアクセスがなければ、
/// Apple を読み書きしていないことと許可のしかたを出す。連携 OFF のあいだに許可が外れても警告は出さない（Q101）。
/// 説明の文は仮（例文の「Appleカレンダー連携」「Appleカレンダーを連携する」は決定のまま）
struct CalendarLinkSection: View {
    @Environment(CalendarConnection.self) private var connection
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { connection.isLinkEnabled },
                                 set: { enabled in _ = connection.switchAppleLink(enabled) })) {
                Text("Appleカレンダー連携")
            }
            .tint(Theme.Colors.accent)
            // 保存できずに戻したとき、スイッチの見た目も戻す（spec §89.9）
            .id(connection.settingsRevision)
            // iPhone のカレンダーの許可（TimyCue の連携の設定とは別の状態）
            LabeledContent("iPhone のカレンダーの許可", value: connection.permissionStateLabel)
            if let note = connection.permissionNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if !connection.hasFullAccess && connection.authorization != .restricted {
                Button("Appleカレンダーを連携する") { link() }
            }
        } header: {
            Text("Apple カレンダー")
        } footer: {
            // OFF の説明は許可の状態によらず出す。ON の説明はフルアクセスがあるとき（ないときは上に許可の説明を出す）
            if !connection.isLinkEnabled {
                Text(Self.offNote)
            } else if connection.hasFullAccess {
                Text(Self.onNote)
            }
        }
    }

    /// 連携を ON として保存してから、まだ許可を求めていなければ iOS の許可を求め（switchAppleLink）、拒否・追加のみなら設定アプリを開く
    /// （OFF のあいだに許可が外れていたら、ON に戻そうとしたこのときに許可を案内する。Q101）
    private func link() {
        guard connection.switchAppleLink(true) else { return }
        switch connection.authorization {
        case .denied, .writeOnly:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        default:
            break
        }
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
