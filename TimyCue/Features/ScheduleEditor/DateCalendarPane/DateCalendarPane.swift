import SwiftUI

/// 3 分割画面の下の日付カレンダー（2026-10-13 ユーザー決定「3 分割画面のカレンダー」）。
/// 曜日の上の真ん中に年。月ごとに区切り、月の初めに 1 行空けて月を出す（月をまたぐ週は 2 行に分ける）。
/// 見える高さは日付の行 6 行ぶん（月の行は別）。左右にスクロールバーを置き、どちらをなぞってもカレンダーが動く。
/// カレンダー本体は指で縦スクロールさせない。本体：タップで 1 日選択／解除、指でなぞると複数日選択（仕様 §34）
struct DateCalendarPane: View {
    @Environment(ScheduleEditorStore.self) private var store

    @State private var axis: EditorCalendarAxis
    /// いちばん上に見えている所（日付の行の高さを 1 とした位置）
    @State private var offset: Double = 0

    init(initialMonth: CalendarMonth) {
        _axis = State(initialValue: EditorCalendarAxis(around: initialMonth,
                                                       monthRowRatio: EditorMetrics.calendarMonthRowRatio))
    }

    var body: some View {
        GeometryReader { geometry in
            let gridHeight = max(geometry.size.height - EditorMetrics.calendarYearHeight - EditorMetrics.calendarWeekdayHeight, 1)
            let rowHeight = gridHeight / EditorMetrics.calendarVisibleWeeks
            HStack(spacing: 0) {
                CalendarScrollBar(axis: axis, offset: $offset, rowHeight: rowHeight)
                VStack(spacing: 0) {
                    // 年は曜日の上の真ん中。いちばん上に見えている月の年（次の年の 1 月が上に来たら変わる）
                    Text(verbatim: axis.topMonth(at: offset).yearLabel)
                        .font(EditorMetrics.calendarYearFont)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: EditorMetrics.calendarYearHeight)
                    EditorWeekdayHeader()
                    DateGrid(axis: axis, offset: offset, rowHeight: rowHeight)
                }
                CalendarScrollBar(axis: axis, offset: $offset, rowHeight: rowHeight)
            }
        }
        .background(Theme.Colors.surface)
        // 年が変わった時だけ軽く振動する。月が変わるたびには振動させない（v1.1「ハプティクス」）
        .sensoryFeedback(.impact(weight: .light), trigger: axis.topMonth(at: offset).year)
    }
}

/// 下カレンダーの曜日（月〜日）。土曜は淡い青、日曜は淡い赤（月カレンダーと同じ。2026-10-12 デザインの指摘）
private struct EditorWeekdayHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Weekday.symbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(EditorMetrics.calendarWeekdayFont)
                    .foregroundStyle(Theme.Colors.weekdayText(index, normal: Theme.Colors.textSecondary))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: EditorMetrics.calendarWeekdayHeight)
    }
}

/// 日付の並び。指でのスクロールはせず、タップとなぞりだけを受ける
private struct DateGrid: View {
    let axis: EditorCalendarAxis
    let offset: Double
    let rowHeight: CGFloat
    @Environment(ScheduleEditorStore.self) private var store

    /// なぞって選んでいる間に通った日（同じ日を何度も選び直さない）
    @State private var touchedDays: Set<CalendarDay> = []
    @State private var isDragSelecting = false

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            let lines = axis.visibleLines(offset: offset, visibleRows: Double(geometry.size.height / max(rowHeight, 1)))
            ZStack(alignment: .topLeading) {
                ForEach(lines, id: \.id) { placed in
                    Group {
                        switch placed.line {
                        case .month(let month):
                            EditorMonthRow(month: month)
                        case .week(let month, let week):
                            EditorWeekRow(month: month, week: week)
                        }
                    }
                    .frame(width: geometry.size.width, height: CGFloat(placed.height) * rowHeight)
                    .offset(y: CGFloat(placed.top - offset) * rowHeight)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let moved = hypot(value.translation.width, value.translation.height)
                        if moved > EditorMetrics.dragSelectThreshold { isDragSelecting = true }
                        guard isDragSelecting, store.mode.allowsMultipleDays,
                              let day = dayAt(value.location, columnWidth: columnWidth),
                              !touchedDays.contains(day) else { return }
                        touchedDays.insert(day)
                        store.selectDay(day)
                    }
                    .onEnded { value in
                        if !isDragSelecting, let day = dayAt(value.startLocation, columnWidth: columnWidth) {
                            tap(day)
                        }
                        touchedDays = []
                        isDragSelecting = false
                    }
            )
        }
    }

    private func dayAt(_ point: CGPoint, columnWidth: CGFloat) -> CalendarDay? {
        axis.day(atX: Double(point.x), y: Double(point.y), offset: offset,
                 rowHeight: Double(rowHeight), columnWidth: Double(columnWidth))
    }

    /// タップ：新規・コピーでは 1 日選択／解除。編集ではその日へ移動（仕様 §34・§61）
    private func tap(_ day: CalendarDay) {
        if store.mode.allowsMultipleDays && store.selectedDays.contains(day) {
            store.deselectDay(day)
        } else {
            store.selectDay(day)
        }
    }
}

private extension EditorCalendarAxis.PlacedLine {
    var id: String {
        switch line {
        case .month(let month): "m\(month.id)"
        case .week(let month, let week): "w\(month.id)-\(week.start.year)-\(week.start.month)-\(week.start.day)"
        }
    }
}

/// 月の初めに 1 行空けて出す月（2026-10-13 ユーザー決定）
private struct EditorMonthRow: View {
    let month: CalendarMonth

    var body: some View {
        Text(month.monthLabel)
            .font(EditorMetrics.calendarMonthFont)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Theme.Colors.separator.frame(height: 1)
            }
    }
}

/// 下カレンダーの 1 週。その月の日だけを出し、ほかの月の日は空ける（月をまたぐ週は 2 行に分ける）
private struct EditorWeekRow: View {
    let month: CalendarMonth
    let week: CalendarWeek
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week.days, id: \.self) { day in
                if CalendarMonth(day) == month {
                    let dots = store.eventDots(on: day)
                    EditorDayCell(day: day,
                                  isSelected: store.selectedDays.contains(day),
                                  isDisplayed: store.displayedDay == day,
                                  isToday: day == CalendarDay(Date()),
                                  dotColors: dots.colors,
                                  moreCount: dots.more)
                        .frame(maxWidth: .infinity)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// 左右に置くスクロールバー（2026-10-13 ユーザー決定）。月や数字は出さず、バーだとわかる色とマーク（上下の矢印とつまみ）だけ。
/// なぞった分だけカレンダーが動く（指と同じ向き。慣性はつけない）。左右どちらでも同じように動く
private struct CalendarScrollBar: View {
    let axis: EditorCalendarAxis
    @Binding var offset: Double
    let rowHeight: CGFloat

    /// なぞり始めた時の位置
    @State private var dragStart: Double?

    var body: some View {
        RoundedRectangle(cornerRadius: EditorMetrics.scrollBarCornerRadius)
            .fill(dragStart == nil ? Theme.Colors.scrollBarTrack : Theme.Colors.scrollBarTrackActive)
            .overlay {
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up")
                        .font(EditorMetrics.scrollBarMarkFont)
                    Spacer(minLength: 0)
                    Image(systemName: "line.3.horizontal")
                        .font(EditorMetrics.scrollBarGripFont)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(EditorMetrics.scrollBarMarkFont)
                }
                .foregroundStyle(Theme.Colors.scrollBarMark)
                .padding(.vertical, Theme.Spacing.s)
            }
            .padding(3)
            .frame(width: EditorMetrics.scrollBarWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStart ?? offset
                        dragStart = start
                        offset = axis.clamp(EditorCalendarAxis.offset(afterDragging: Double(value.translation.height),
                                                                      from: start,
                                                                      rowHeight: Double(rowHeight),
                                                                      speed: EditorMetrics.scrollBarDragSpeed))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityLabel("カレンダーを上下に動かす")
    }
}

/// 下カレンダーの 1 日。選んだ日は塗り、時間画面に出している日は枠。今日は数字の後ろに淡いオレンジ。
/// 予定がある日は、数字の下に予定色のドットを最大 3 個（4 件以上は「+N」）。丸・塗り・枠とは重ならない所に置く（Q23）
private struct EditorDayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let isDisplayed: Bool
    let isToday: Bool
    let dotColors: [EventColor]
    let moreCount: Int

    var body: some View {
        VStack(spacing: EditorMetrics.eventDotSpacing) {
            Text(verbatim: "\(day.day)")
                .font(EditorMetrics.calendarDayFont)
                .foregroundStyle(isSelected
                                 ? Color.white
                                 : Theme.Colors.weekdayText(day.weekdayIndexFromMonday(), normal: Theme.Colors.textPrimary))
                .frame(width: EditorMetrics.selectedCircleSize, height: EditorMetrics.selectedCircleSize)
                .background {
                    if isSelected {
                        Circle().fill(Theme.Colors.accent)
                    } else if isToday {
                        Circle().fill(Theme.Colors.todayCircle)
                    }
                }
                .overlay {
                    if isDisplayed {
                        Circle().strokeBorder(Theme.Colors.textPrimary, lineWidth: 1.5)
                            .padding(-2)
                    }
                }
            HStack(spacing: EditorMetrics.eventDotSpacing) {
                ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(EventPalette.color(for: color))
                        .frame(width: EditorMetrics.eventDotSize, height: EditorMetrics.eventDotSize)
                }
                if moreCount > 0 {
                    Text("+\(moreCount)")
                        .font(EditorMetrics.eventMoreFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize()
                }
            }
            .frame(height: EditorMetrics.eventDotSize + 2)
        }
    }
}
