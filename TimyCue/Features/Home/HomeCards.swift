import SwiftUI

/// ［予定を登録］：3 分割の新規予定画面（初期日付は今日、開始時刻は未設定。Q42-8）。
/// カレンダーを許可しなくても、TimyCue の中に予定を作れる（Q45）。予定がないときに出す（Q43。通常の Home に常設の＋は置かない：Q21）
struct HomeRegisterButton: View {
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("予定を登録")
                .foregroundStyle(Theme.Colors.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.Colors.accent)
        .controlSize(prominent ? .large : .regular)
    }
}

/// 使い始めるための入り口（Q42-8・Q115）：まだ連携していない・許可がないときだけ出す。わざと OFF にしたとき・確かめられないときは出さない
/// （Q102・2026-10-19 決定 3。出すかは CalendarConnection.showsSetupCard のまま）。
/// 文言は今の Home のまま。Home を縦にスクロールさせないため、ボタンを横に並べて低くした
struct HomeSetupCard: View {
    let state: CalendarConnection.State
    let onConnect: () -> Void
    let onOpenSettings: () -> Void
    let onRegister: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("カレンダーを連携、または予定を登録すると、次の出発時刻を計算できます")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if state == .denied {
                // 一度断られたら、自分からは何度も求めず、iPhone の設定へ案内する（Q38）
                Text("カレンダーへのアクセスは、iPhone の設定から許可してください")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Spacing.s) {
                if state == .denied {
                    Button(action: onOpenSettings) {
                        Text("設定アプリで許可する")
                            .foregroundStyle(Theme.Colors.onAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.accent)
                } else if state == .notAsked {
                    Button(action: onConnect) {
                        Text("カレンダーを連携")
                            .foregroundStyle(Theme.Colors.onAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accentFill)
                }
                HomeRegisterButton(prominent: false, action: onRegister)
            }
            .controlSize(.regular)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.medium).fill(Theme.Colors.surface)
        }
    }
}

/// 重複候補の案内（Q50）：新しい重複候補が見つかったら、一度だけ強制しない案内を出す。［確認］で一覧へ。閉じたらもう出さない
struct HomeDuplicateNotice: View {
    let count: Int
    let onConfirm: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text("重複している可能性のある予定が\(count)件あります")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onConfirm) {
                Text("確認").foregroundStyle(Theme.Colors.onAccent)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.accent)
            .controlSize(.small)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.medium).fill(Theme.Colors.surface)
        }
    }
}
