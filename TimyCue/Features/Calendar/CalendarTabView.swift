import SwiftUI

/// カレンダータブ。月表示が主役で、編集の画面は常に出さない（仕様 §18）。予定検索は設けない（v1.1）。
/// 吹き出しの日付を押すとその日の 1 日タイムラインへ（仕様 §25）、タイムラインの予定を押すと予定詳細へ移る（Q17）
struct CalendarTabView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            VStack(spacing: 0) {
                CalendarHeaderView(year: store.stickyMonth.yearLabel)
                    .contentShape(Rectangle())
                    .onTapGesture { store.closeAllPopovers() }
                MonthCalendarView()
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CalendarRoute.self) { route in
                switch route {
                case .timeline(let day):
                    DayTimelineView(day: day)
                case .eventDetail(let eventID):
                    EventDetailView(eventID: eventID)
                }
            }
        }
        .onAppear {
            store.updateToday()
            openForScreenshot()
        }
    }

    /// Codemagic で画面写真を撮るときの起動引数（DEBUG のときだけ）。
    /// `-TimyCueOpenDays "0,4"`：今日から 0 日後・4 日後の吹き出しを開く。`-TimyCueTimelineDay 0`：その日の 1 日タイムラインを開く。
    /// `-TimyCueDetailOfFirstEventToday YES`：今日の最初の時間指定の予定の詳細を開く
    private func openForScreenshot() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "TimyCueOpenDays"), store.openDays.isEmpty {
            for offset in raw.split(separator: ",").compactMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                store.tapDay(store.today.adding(days: offset))
            }
        }
        if let raw = defaults.string(forKey: "TimyCueTimelineDay"), let offset = Int(raw), store.path.isEmpty {
            store.openTimeline(store.today.adding(days: offset))
        }
        if defaults.bool(forKey: "TimyCueDetailOfFirstEventToday"), store.path.isEmpty,
           let first = store.timedEvents(on: store.today).first {
            store.openTimeline(store.today)
            store.openEventDetail(first.id)
        }
        #endif
    }
}
