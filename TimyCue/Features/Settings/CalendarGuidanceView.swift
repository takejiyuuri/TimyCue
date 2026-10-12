import SwiftUI

/// 未連携のときだけ出す「カレンダーを連携」の案内（Q38）。TimyCue が Apple カレンダーを使う理由を説明し、
/// 「カレンダーを連携」を押したときに初めて iOS の許可のダイアログを出す。通常のカレンダー画面に常設するボタンではない
struct CalendarGuidanceView: View {
    let onConnect: () -> Void
    let onLater: () -> Void
    var laterTitle = "あとで"

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.accent)
            VStack(spacing: Theme.Spacing.s) {
                Text("カレンダーを連携")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("カレンダーを連携すると、予定から出発時刻を計算できます。\nApple カレンダーの予定を TimyCue に表示し、TimyCue で作った予定を Apple カレンダーに保存します。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Theme.Spacing.s) {
                Button(action: onConnect) {
                    Text("カレンダーを連携")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .controlSize(.large)
                Button(laterTitle, action: onLater)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 360)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .fill(Theme.Colors.surface)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.opacity(0.6).ignoresSafeArea())
    }
}
