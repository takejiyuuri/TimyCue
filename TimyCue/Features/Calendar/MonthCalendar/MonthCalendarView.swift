import SwiftUI

/// 画面上部の固定領域：年（Q20）と曜日の見出し（仕様 §19）。
/// 年は真ん中に置く。土曜は淡い青、日曜は淡い赤（2026-10-12 デザインの指摘）。
/// 右上に少し小さめの「＋」と、今日が見えていないときだけの「今日」（Q21 を 2026-10-12 に変更）
struct CalendarHeaderView: View {
    let year: String
    let showsToday: Bool
    let onToday: () -> Void
    let onNewEvent: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(year)
                .font(CalendarMetrics.yearFont)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: CalendarMetrics.yearHeaderHeight)
                .overlay(alignment: .trailing) {
                    HStack(spacing: CalendarMetrics.headerButtonSpacing) {
                        if showsToday {
                            // 「＋」と同じ丸（2026-10-13 デザインの指摘）
                            Button(action: onToday) {
                                Text("今日")
                                    .font(CalendarMetrics.todayButtonFont)
                                    .foregroundStyle(.white)
                                    .frame(width: CalendarMetrics.newEventButtonSize, height: CalendarMetrics.newEventButtonSize)
                                    .background(Circle().fill(Theme.Colors.accent))
                            }
                            .accessibilityLabel("今日へ移動")
                        }
                        NewEventButton(action: onNewEvent)
                    }
                    .padding(.trailing, CalendarMetrics.headerButtonsTrailingInset)
                }
            HStack(spacing: 0) {
                ForEach(Array(Weekday.symbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(CalendarMetrics.weekdayHeaderFont)
                        .foregroundStyle(Theme.Colors.weekdayText(index, normal: Theme.Colors.textSecondary))
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
/// 月は、その月の 1 日のセルに「10/1」と出す。左端の月の列と月の固定表示はやめた（2026-10-12 ユーザー決定。Q18・Q19 を変更）。
/// 画面の真ん中にある月を「見ている月」とし、それ以外の日は見た目だけ薄くする
struct MonthCalendarView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        GeometryReader { proxy in
            let visibleRows = Int(proxy.size.height / CalendarMetrics.cellHeight)
            let focusMonth = store.focusMonth(visibleRows: visibleRows)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.weeks) { week in
                        WeekRowView(week: week, focusMonth: focusMonth)
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
            // 見えている週の数を覚えておく（「今日」を出すかに使う。画面の処理の中では書き換えない）
            .onAppear { store.setVisibleRows(visibleRows) }
            .onChange(of: visibleRows) { _, rows in store.setVisibleRows(rows) }
            .overlayPreferenceValue(OpenDayAnchorKey.self) { anchors in
                DayPopoverLayer(anchors: anchors)
            }
        }
    }
}

/// 1 週間分の行
private struct WeekRowView: View {
    let week: CalendarWeek
    let focusMonth: CalendarMonth
    @Environment(CalendarStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week.days, id: \.self) { day in
                DayCellView(day: day,
                            summary: store.summary(on: day),
                            isToday: day == store.today,
                            isOpen: store.isOpen(day),
                            isOutsideFocusMonth: CalendarMonth(day) != focusMonth)
                    .onTapGesture { store.tapDay(day) }
            }
        }
        .overlay(alignment: .top) {
            Theme.Colors.separator
                .frame(height: 1)
        }
    }
}
