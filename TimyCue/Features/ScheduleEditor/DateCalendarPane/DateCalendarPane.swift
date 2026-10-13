import SwiftUI

/// 3 分割画面の下の日付カレンダー（2026-10-13 ユーザー決定「3 分割画面のカレンダー」）。
/// いちばん上の真ん中に年月（例：2026年　10月）を固定。月ごとに区切り、月の初めに 1 行空けて月帯を出す（月をまたぐ週は 2 行に分ける）。
/// 月帯がいちばん上に重なったら、上の年月が切り替わる。
/// 見える高さは日付の行 6 行ぶん（月の行は別）。左右にスクロールバーを置き、どちらをなぞってもカレンダーが動く。
/// カレンダー本体は指で縦スクロールさせない。本体：タップで左上に出す日を選ぶ（選んでいない日なら左上の日をその日へ動かす）。
/// 右の「同じ内容で追加」を開いている間だけ、タップ・なぞりで日を足す・外す（仕様 §34、2026-10-14 ユーザー決定）
struct DateCalendarPane: View {
    @Environment(ScheduleEditorStore.self) private var store

    @State private var axis: EditorCalendarAxis
    /// いちばん上に見えている所と、左右のバーでの動き
    @State private var scroller = EditorCalendarScroller()

    init(initialMonth: CalendarMonth) {
        _axis = State(initialValue: EditorCalendarAxis(around: initialMonth,
                                                       monthRowRatio: EditorMetrics.calendarMonthRowRatio))
    }

    var body: some View {
        GeometryReader { geometry in
            let gridHeight = max(geometry.size.height - EditorMetrics.calendarYearHeight - EditorMetrics.calendarWeekdayHeight, 1)
            let rowHeight = CGFloat(EditorCalendarAxis.rowHeight(gridHeight: Double(gridHeight),
                                                                 visibleWeeks: Double(EditorMetrics.calendarVisibleWeeks),
                                                                 minimum: Double(EditorMetrics.calendarMinRowHeight)))
            let offset = scroller.offset
            HStack(spacing: 0) {
                CalendarScrollBar(axis: axis, scroller: scroller, rowHeight: rowHeight)
                VStack(spacing: 0) {
                    // 年月は曜日の上の真ん中に固定。月帯がいちばん上に重なったら次の月へ、下へ抜けたら前の月へ（2026-10-13）
                    Text(verbatim: EditorCalendarAxis.headerText(for: axis.topMonth(at: offset)))
                        .font(EditorMetrics.calendarYearFont)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: EditorMetrics.calendarYearHeight)
                    EditorWeekdayHeader()
                    DateGrid(axis: axis, offset: offset, rowHeight: rowHeight)
                }
                CalendarScrollBar(axis: axis, scroller: scroller, rowHeight: rowHeight)
            }
        }
        .background(Theme.Colors.surface)
        // 年が変わった時だけ軽く振動する。月が変わるたびには振動させない（v1.1「ハプティクス」）
        .sensoryFeedback(.impact(weight: .light), trigger: axis.topMonth(at: scroller.offset).year)
        .onDisappear { scroller.stopInertia() }
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
    /// なぞって足していくか（false なら外していく）。なぞり始めた日で決める（2026-10-14 ユーザー指摘「なぞって選択解除ができない」）
    @State private var paintsSelection = true

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
                        // なぞって日を足す・外すのは「同じ内容で追加」を開いている間だけ（2026-10-14 ユーザー決定）
                        guard store.isAddingDays else { return }
                        if !isDragSelecting {
                            guard hypot(value.translation.width, value.translation.height) > EditorMetrics.dragSelectThreshold else { return }
                            isDragSelecting = true
                            // なぞり始めた日が足してある日なら外していき、そうでなければ足していく
                            let first = dayAt(value.startLocation, columnWidth: columnWidth)
                            paintsSelection = !(first.map { store.additionalDays.contains($0) } ?? false)
                            if let first { paint(first) }
                        }
                        if let day = dayAt(value.location, columnWidth: columnWidth) { paint(day) }
                    }
                    .onEnded { value in
                        let isTap = !isDragSelecting
                            && hypot(value.translation.width, value.translation.height) <= EditorMetrics.dragSelectThreshold
                        if isTap, let day = dayAt(value.startLocation, columnWidth: columnWidth) {
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

    /// タップ：「同じ内容で追加」を開いている間は 1 日ずつ足す・外す。ふだんは左上に出す日を選ぶ
    /// （選んでいない日なら左上の日をその日へ動かす。編集の移動も同じ。仕様 §34・§61）
    private func tap(_ day: CalendarDay) {
        if store.isAddingDays {
            if store.additionalDays.contains(day) {
                store.removeDay(day)
            } else {
                store.addDay(day)
            }
        } else {
            store.selectDay(day)
        }
    }

    /// なぞって通った日を足す、または外す（1 回のなぞりで同じ日は 1 度だけ）
    private func paint(_ day: CalendarDay) {
        guard !touchedDays.contains(day) else { return }
        touchedDays.insert(day)
        if paintsSelection {
            store.addDay(day)
        } else {
            store.removeDay(day)
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

/// 月の初めに 1 行空けて出す月帯。高さは日付の行の半分くらい、文字は真ん中。1 月だけは年も出す（2026-10-13 ユーザー決定）
private struct EditorMonthRow: View {
    let month: CalendarMonth

    var body: some View {
        Text(verbatim: EditorCalendarAxis.bandText(for: month))
            .font(EditorMetrics.calendarMonthFont)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
/// なぞっている間は指と同じだけ動き、離したら iPhone のふつうのスクロールのように滑って止まる。左右どちらでも同じように動く
private struct CalendarScrollBar: View {
    let axis: EditorCalendarAxis
    let scroller: EditorCalendarScroller
    let rowHeight: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: EditorMetrics.scrollBarCornerRadius)
            .fill(scroller.isDragging ? Theme.Colors.scrollBarTrackActive : Theme.Colors.scrollBarTrack)
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
                        scroller.drag(translation: Double(value.translation.height), rowHeight: Double(rowHeight), axis: axis)
                    }
                    .onEnded { value in
                        scroller.endDrag(velocity: Double(value.velocity.height), rowHeight: Double(rowHeight), axis: axis)
                    }
            )
            .accessibilityLabel("カレンダーを上下に動かす")
    }
}

/// 下カレンダーの 1 日。選んだ日は塗り、時間画面に出している日は枠。今日は数字の後ろに淡いグレー（2026-10-14 実機の指摘）。
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
                        Circle().fill(Theme.Colors.editorTodayCircle)
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
