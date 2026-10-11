import SwiftUI

/// 新規予定の「＋」（Q21：月カレンダーの右下）
struct NewEventButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Theme.Colors.accent))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .accessibilityLabel("新規予定")
    }
}
