import SwiftUI

/// 曜日の見出し。画面上部に固定する（仕様 §19）
struct WeekdayHeaderView: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Weekday.symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(CalendarMetrics.weekdayHeaderFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: CalendarMetrics.weekdayHeaderHeight)
        .padding(.horizontal, CalendarMetrics.horizontalPadding)
        .background(Theme.Colors.background)
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
    }
}

/// 月を縦方向に連続スクロールで並べる（仕様 §19）
struct MonthCalendarView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CalendarMetrics.monthSpacing) {
                    ForEach(store.months) { month in
                        MonthSectionView(month: month)
                            .id(month.id)
                    }
                }
                .padding(.horizontal, CalendarMetrics.horizontalPadding)
                .padding(.vertical, CalendarMetrics.monthSpacing / 2)
            }
            .overlayPreferenceValue(OpenDayAnchorKey.self) { anchors in
                DayPopoverLayer(anchors: anchors)
            }
            .onAppear {
                proxy.scrollTo(store.currentMonth.id, anchor: .top)
            }
        }
    }
}

/// 1 か月分
struct MonthSectionView: View {
    let month: CalendarMonth
    @Environment(CalendarStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(month.title)
                .font(CalendarMetrics.monthTitleFont)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.leading, 6)
            ForEach(Array(month.weeks().enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        if let day = week[index] {
                            DayCellView(day: day,
                                        summary: store.summary(on: day),
                                        isToday: day == store.today,
                                        isOpen: store.isOpen(day))
                                .onTapGesture { store.tapDay(day) }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: CalendarMetrics.cellHeight, maxHeight: CalendarMetrics.cellHeight)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    Theme.Colors.separator.frame(height: 1)
                }
            }
        }
    }
}
