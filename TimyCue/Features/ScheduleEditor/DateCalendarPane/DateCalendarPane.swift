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
                let dots = store.eventDots(on: day)
                EditorDayCell(day: day,
                              isSelected: store.selectedDays.contains(day),
                              isDisplayed: store.displayedDay == day,
                              isToday: day == CalendarDay(Date()),
                              dotColors: dots.colors,
                              moreCount: dots.more)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: rowHeight)
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

/// 年月一体の縦スクロールバー（v1.1「独自年月スクロールバー」・2026-10-12 ユーザー決定）。
/// 左に年、右に月。真ん中の固定帯は動かず、年月ラベルがその下を流れる。
/// 帯より上を長押しすると、押している間ずっと一定のゆっくりした速さで上（過去）へ、下を長押しすると下（未来）へ動く。
/// 指を離したらすぐ止まる（滑らせて慣性で回すのはやめた）。月を短く押すとその月へ飛び、その月の 1 日を含む週がいちばん上に来る
private struct YearMonthBar: View {
    let axis: EditorCalendarAxis
    @Binding var offset: Double
    let visibleRows: Int

    /// 長押しで動かしている間の処理
    @State private var hold: Task<Void, Never>?
    /// 押し始めたか（指を置いた最初の 1 回だけ長押しの準備をする）
    @State private var isPressing = false
    /// 長押しで動き始めたか（動いたら、指を離しても月へは飛ばない）
    @State private var isHolding = false

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
                        .offset(y: CGFloat(y))
                }

                // いちばん上には、今見えている年を出しておく（例：2026 | 10月 の 2026）
                Text(verbatim: String(axis.topWeek(at: offset).stickyMonth.year))
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
            // 指を置いたら長押しの準備。少し押し続けたら動き始め、離したら止まる。短く押しただけなら、その月へ飛ぶ
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isPressing else { return }
                        isPressing = true
                        startHolding(direction: EditorCalendarAxis.holdDirection(pressY: Double(value.startLocation.y),
                                                                                 barHeight: height))
                    }
                    .onEnded { value in
                        let moved = isHolding
                        stopHolding()
                        guard !moved, abs(value.translation.height) < 10 else { return }
                        let tappedY = Double(value.location.y)
                        let tapped = months.first { item in
                            let y = EditorCalendarAxis.barY(weekIndex: item.weekIndex, offset: offset,
                                                            bandTop: bandTop, weekHeight: weekHeight)
                            return tappedY >= y && tappedY < y + Double(labelHeight)
                        }
                        if let tapped { jump(to: tapped.month) }
                    }
            )
        }
        .background(Theme.Colors.background)
        .onDisappear { stopHolding() }
    }

    /// 長押しで動かす。押し始めて少したってから、一定の速さで動かし続ける
    private func startHolding(direction: Double) {
        hold?.cancel()
        hold = Task { @MainActor in
            try? await Task.sleep(for: .seconds(EditorMetrics.barHoldDelay))
            guard !Task.isCancelled else { return }
            isHolding = true
            let start = offset
            let began = Date()
            while !Task.isCancelled {
                offset = axis.clamp(EditorCalendarAxis.offset(afterHolding: Date().timeIntervalSince(began),
                                                              from: start, direction: direction,
                                                              weeksPerSecond: Double(EditorMetrics.barHoldWeeksPerSecond)))
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// 指を離したらすぐ止める
    private func stopHolding() {
        hold?.cancel()
        hold = nil
        isPressing = false
        isHolding = false
    }

    private func jump(to month: CalendarMonth) {
        stopHolding()
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
            if showsYear {
                // 年は桁区切りを付けない（「2,026」にしない）
                Text(verbatim: String(month.year))
                    .font(EditorMetrics.barYearFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            // 月は「1…」と切らずに出す
            Text(month.monthLabel)
                .font(isFocused ? EditorMetrics.barMonthFocusedFont : EditorMetrics.barMonthFont)
                .foregroundStyle(isFocused ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.horizontal, 4)
    }
}
