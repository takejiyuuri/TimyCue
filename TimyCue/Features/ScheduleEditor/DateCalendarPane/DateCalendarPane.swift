import SwiftUI

/// 3 分割画面の下の日付カレンダー（v1.1「3 分割予定編集画面：下部カレンダーの大幅変更」）。
/// 週を途切れず縦に並べる。カレンダー本体は指で縦スクロールさせず、左の年月バーでだけ動かす。
/// 本体：タップで 1 日選択／解除、指でなぞると複数日選択（仕様 §34）
struct DateCalendarPane: View {
    @Environment(ScheduleEditorStore.self) private var store

    @State private var axis: EditorCalendarAxis
    /// いちばん上に見えている週の番号（小数あり）
    @State private var offset: Double = 0

    init(initialMonth: CalendarMonth) {
        _axis = State(initialValue: EditorCalendarAxis(around: initialMonth))
    }

    var body: some View {
        GeometryReader { geometry in
            let gridHeight = max(geometry.size.height - EditorMetrics.calendarWeekdayHeight, 1)
            let visibleRows = max(3, Int(gridHeight / EditorMetrics.calendarMinRowHeight))
            HStack(spacing: 0) {
                YearMonthBar(axis: axis, offset: $offset, visibleRows: visibleRows)
                    .frame(width: EditorMetrics.yearMonthBarWidth)
                VStack(spacing: 0) {
                    EditorWeekdayHeader()
                    DateGrid(axis: axis,
                             offset: offset,
                             visibleRows: visibleRows,
                             rowHeight: gridHeight / CGFloat(visibleRows))
                }
            }
        }
        .background(Theme.Colors.surface)
        // 年が変わった時だけ軽く振動する。月が変わるたびには振動させない（v1.1「ハプティクス」）
        .sensoryFeedback(.impact(weight: .light), trigger: axis.topWeek(at: offset).stickyMonth.year)
    }
}

/// 下カレンダーの曜日（月〜日）
private struct EditorWeekdayHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Weekday.symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(EditorMetrics.calendarWeekdayFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
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
    let visibleRows: Int
    let rowHeight: CGFloat
    @Environment(ScheduleEditorStore.self) private var store

    /// なぞって選んでいる間に通った日（同じ日を何度も選び直さない）
    @State private var touchedDays: Set<CalendarDay> = []
    @State private var isDragSelecting = false

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            ZStack(alignment: .topLeading) {
                ForEach(Array(axis.visibleWeekIndices(offset: offset, visibleRows: visibleRows)), id: \.self) { index in
                    EditorWeekRow(week: axis.week(at: index), rowHeight: rowHeight)
                        .offset(y: (CGFloat(index) - CGFloat(offset)) * rowHeight)
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

/// 下カレンダーの 1 週。月の境目の飾りは付けない（v1.1「月境界表現」）
private struct EditorWeekRow: View {
    let week: CalendarWeek
    let rowHeight: CGFloat
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week.days, id: \.self) { day in
                EditorDayCell(day: day,
                              isSelected: store.selectedDays.contains(day),
                              isDisplayed: store.displayedDay == day,
                              isToday: day == CalendarDay(Date()))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: rowHeight)
    }
}

/// 下カレンダーの 1 日。選んだ日は塗り、時間画面に出している日は枠。今日は数字の後ろに淡いオレンジ
private struct EditorDayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let isDisplayed: Bool
    let isToday: Bool

    var body: some View {
        Text("\(day.day)")
            .font(EditorMetrics.calendarDayFont)
            .foregroundStyle(isSelected ? Color.white : Theme.Colors.textPrimary)
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
                        .padding(-3)
                }
            }
    }
}

/// 年月一体の縦スクロールバー（v1.1「独自年月スクロールバー」）。
/// 左に年、右に月。上下にスライドすると慣性で回る（月にはスナップしない）。真ん中の固定帯は動かず、年月ラベルがその下を流れる。
/// 月をタップするとその月へ飛び、その月の 1 日を含む週がカレンダーのいちばん上に来る
private struct YearMonthBar: View {
    let axis: EditorCalendarAxis
    @Binding var offset: Double
    let visibleRows: Int

    @State private var dragStartOffset: Double?
    @State private var inertia: Task<Void, Never>?

    private let weekHeight = Double(EditorMetrics.barWeekHeight)
    private let labelHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let height = Double(geometry.size.height)
            let bandHeight = Double(visibleRows) * weekHeight
            let bandTop = (height - bandHeight) / 2
            let span = Int(height / weekHeight / 2) + 6
            let months = axis.barMonths(offset: offset, spanWeeks: span)

            ZStack(alignment: .topLeading) {
                // 固定帯：右のカレンダーで今見えている範囲。帯そのものは動かさない
                RoundedRectangle(cornerRadius: EditorMetrics.barBandCornerRadius)
                    .fill(Theme.Colors.accent.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: EditorMetrics.barBandCornerRadius)
                            .strokeBorder(Theme.Colors.accent, lineWidth: 1)
                    }
                    .frame(width: geometry.size.width - 4, height: CGFloat(bandHeight))
                    .offset(x: 2, y: CGFloat(bandTop))

                ForEach(months, id: \.month) { item in
                    let y = EditorCalendarAxis.barY(weekIndex: item.weekIndex, offset: offset,
                                                    bandTop: bandTop, weekHeight: weekHeight)
                    let isFocused = y >= bandTop - 1 && y < bandTop + bandHeight
                    YearMonthLabel(month: item.month, showsYear: item.month.month == 1, isFocused: isFocused)
                        .frame(width: geometry.size.width, height: labelHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { jump(to: item.month) }
                        .offset(y: CGFloat(y))
                }

                // いちばん上には、今見えている年を出しておく（例：2026 | 10月 の 2026）
                Text("\(axis.topWeek(at: offset).stickyMonth.year)")
                    .font(EditorMetrics.barYearFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, 4)
                    .frame(width: geometry.size.width, height: labelHeight, alignment: .leading)
                    .background(Theme.Colors.surface)
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        inertia?.cancel()
                        let start = dragStartOffset ?? offset
                        if dragStartOffset == nil { dragStartOffset = offset }
                        offset = axis.clamp(EditorCalendarAxis.offset(afterDragging: Double(value.translation.height),
                                                                      from: start, weekHeight: weekHeight))
                    }
                    .onEnded { value in
                        dragStartOffset = nil
                        let remaining = -Double(value.predictedEndTranslation.height - value.translation.height) / weekHeight
                        startInertia(remainingWeeks: remaining)
                    }
            )
        }
        .background(Theme.Colors.background)
    }

    /// 指を離したあと、慣性で回し続ける
    private func startInertia(remainingWeeks: Double) {
        inertia?.cancel()
        inertia = Task { @MainActor in
            var speed = EditorCalendarAxis.initialInertiaSpeed(remainingWeeks: remainingWeeks)
            while !Task.isCancelled, let step = EditorCalendarAxis.inertiaStep(offset: offset, speed: speed) {
                offset = axis.clamp(step.offset)
                speed = step.speed
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func jump(to month: CalendarMonth) {
        inertia?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) {
            offset = axis.offset(jumpingTo: month)
        }
    }
}

/// バーの 1 か月ぶんのラベル。左に年（1 月のときだけ）、右に月
private struct YearMonthLabel: View {
    let month: CalendarMonth
    let showsYear: Bool
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            Text(showsYear ? "\(month.year)" : "")
                .font(EditorMetrics.barYearFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(month.monthLabel)
                .font(isFocused ? EditorMetrics.barMonthFocusedFont : EditorMetrics.barMonthFont)
                .foregroundStyle(isFocused ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 4)
    }
}
