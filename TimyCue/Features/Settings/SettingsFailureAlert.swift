import SwiftUI

/// カレンダー連携の設定を保存できなかったときの知らせ（変更は戻してある。spec §89.9）。
/// アラートは、出ている画面の上にしか出せないので、元の画面（タブ）と、設定を変えられるシートの両方に付ける。
/// 出せなかった側が知らせを消さないよう、消すのは「OK」を押したときだけ
struct SettingsFailureAlert: ViewModifier {
    @Environment(CalendarConnection.self) private var connection

    func body(content: Content) -> some View {
        content
            .alert("設定を保存できませんでした",
                   isPresented: Binding(get: { connection.settingsFailure != nil }, set: { _ in }),
                   presenting: connection.settingsFailure) { _ in
                Button("OK", role: .cancel) { connection.dismissSettingsFailure() }
            } message: { failure in
                Text(failure.message)
            }
    }
}

extension View {
    func settingsFailureAlert() -> some View {
        modifier(SettingsFailureAlert())
    }
}
