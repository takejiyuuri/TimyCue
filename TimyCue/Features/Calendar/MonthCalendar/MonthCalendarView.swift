import SwiftUI

/// 画面上部の固定領域：年（Q20）と曜日の見出し（仕様 §19）
struct CalendarHeaderView: View {
    let year: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(year)
                .font(CalendarMetrics.yearFont)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.leading, CalendarMetrics.horizontalPadding + 6)
                .frame(height: CalendarMetrics.yearHeaderHeight)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: CalendarMetrics.monthColumnWidth)
                ForEach(Weekday.symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(CalendarMetrics.weekdayHeaderFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: CalendarMetrics.weekdayHeaderHeight)
        }
        .padding(.horizontal, CalendarMetrics.horizontalPadding)
        .background(Theme.Colors.background)
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
    }
}

/// 通常の月カレンダー。週を途切れず縦に連続表示し、月ごとの箱は作らない（v1.1・§19）。
/// 左端の細い列に、その月の 1 日を含む週の高さで月を出し、一番上の月は列の上に固定する（Q18・Q19）
struct MonthCalendarView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.weeks) { week in
                    WeekRowView(week: week)
                        .id(week.id)
                        .onAppear { store.weekDidAppear(week) }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, CalendarMetrics.horizontalPadding)
            // 吹き出しの外（日付以外）を押したら、開いている吹き出しを閉じる（Q9）
            .contentShape(Rectangle())
            .onTapGesture { store.closeAllPopovers() }
        }
        .scrollPosition(id: $store.topWeekID, anchor: .top)
        .overlay(alignment: .topLeading) {
            StickyMonthLabel(month: store.stickyMonth)
                .padding(.leading, CalendarMetrics.horizontalPadding)
        }
        .overlayPreferenceValue(OpenDayAnchorKey.self) { anchors in
            DayPopoverLayer(anchors: anchors)
        }
    }
}

/// 1 週間分の行。左端は月表示列（Q18）
private struct WeekRowView: View {
    let week: CalendarWeek
    @Environment(CalendarStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            MonthLabelCell(month: week.monthStartingInWeek)
            ForEach(week.days, id: \.self) { day in
                DayCellView(day: day,
                            summary: store.summary(on: day),
                            isToday: day == store.today,
                            isOpen: store.isOpen(day))
                    .onTapGesture { store.tapDay(day) }
            }
        }
        .overlay(alignment: .top) {
            Theme.Colors.separator
                .frame(height: 1)
                .padding(.leading, CalendarMetrics.monthColumnWidth)
        }
    }
}

/// 月表示列の 1 週ぶん。1 日を含む週だけ「10月」のように出す（Q18）
private struct MonthLabelCell: View {
    let month: CalendarMonth?

    var body: some View {
        Text(month?.monthLabel ?? "")
            .font(CalendarMetrics.monthLabelFont)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, CalendarMetrics.monthLabelTopPadding)
            .frame(width: CalendarMetrics.monthColumnWidth,
                   height: CalendarMetrics.cellHeight,
                   alignment: .top)
    }
}

/// 月表示列の上に固定する、一番上の週の月（Q19）。下を流れてくる月表示を隠すため背景を塗る
private struct StickyMonthLabel: View {
    let month: CalendarMonth

    var body: some View {
        Text(month.monthLabel)
            .font(CalendarMetrics.monthLabelFont)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, CalendarMetrics.monthLabelTopPadding)
            .frame(width: CalendarMetrics.monthColumnWidth,
                   height: CalendarMetrics.stickyMonthHeight,
                   alignment: .top)
            .background(Theme.Colors.background)
            .allowsHitTesting(false)
    }
}
