import SwiftUI

/// 新規予定の「＋」（Q21。2026-10-12 に右下から右上へ移し、少し小さくした）
struct NewEventButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(CalendarMetrics.newEventButtonFont)
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: CalendarMetrics.newEventButtonSize, height: CalendarMetrics.newEventButtonSize)
                .background(Circle().fill(Theme.Colors.accentFill))
        }
        .accessibilityLabel("新規予定")
    }
}
