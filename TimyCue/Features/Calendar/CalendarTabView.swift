import SwiftUI

/// カレンダータブ。月表示が主役で、編集の画面は常に出さない（仕様 §18）。予定検索は設けない（v1.1）
struct CalendarTabView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            CalendarHeaderView(year: store.stickyMonth.yearLabel)
                .contentShape(Rectangle())
                .onTapGesture { store.closeAllPopovers() }
            MonthCalendarView()
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .onAppear {
            store.updateToday()
            openPopoversForScreenshot()
        }
    }

    /// Codemagic で吹き出しの画面写真を撮るとき、起動引数 `-TimyCueOpenDays "0,4"`（今日からの日数）で吹き出しを開く
    private func openPopoversForScreenshot() {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "TimyCueOpenDays"), store.openDays.isEmpty else { return }
        for offset in raw.split(separator: ",").compactMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
            store.tapDay(store.today.adding(days: offset))
        }
        #endif
    }
}
