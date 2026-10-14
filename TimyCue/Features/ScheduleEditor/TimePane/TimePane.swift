import SwiftUI

/// 3 分割画面の左上：時間画面（仕様 §35〜§43）。上に表示中の 1 日の日付、その下にその日の縦タイムライン。
/// 「時」を押すとその位置に分ホイール（§38）。仮予定は上下にドラッグして開始時刻を変え（§40）、下端のハンドルで終了時刻を決める（§41）
struct TimePane: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            DateHeader()
            if let day = store.displayedDay {
                EditorTimeAxis(day: day)
                    .id(day)
            } else {
                Text("下のカレンダーで日付を選んでください")
                    .font(EditorMetrics.inputLabelFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Colors.background)
    }
}

/// 時間画面の上の日付。複数日を選んでいても、表示中の 1 日だけを「10月2日（金）」のように、時間画面の幅の真ん中に出す。色は付けない
/// （2026-10-14 ユーザー決定。前の日付タブの一覧はやめた。別の日は下のカレンダーでその日をタップして出す。真ん中は 2026-10-14 実機の指摘）
private struct DateHeader: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        Group {
            if let day = store.displayedDay {
                Text("\(day.month)月\(day.day)日（\(day.weekdaySymbol())）")
                    .font(EditorMetrics.dateTabFont)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: EditorMetrics.dateTabHeight)
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
    }
}

/// その日の縦タイムライン（§37）。既存の予定と、保存前の仮予定（§39）を出す
private struct EditorTimeAxis: View {
    let day: CalendarDay
    @Environment(ScheduleEditorStore.self) private var store

    /// 分ホイールを出している「時」（§38。ホイールを置く位置）と、ホイールで選んでいる時刻（0:00 からの分。5 分おき）
    @State private var wheelHour: Int?
    @State private var wheelMinute = 0
    /// 仮予定を動かしている間・下端のハンドルを伸ばしている間の指の動き（時間軸の上で測る。§40・§41）。
    /// 指を離したら store に入れる。iOS に操作を止められても自然に消える
    @GestureState private var moveDistance: CGFloat? = nil
    @GestureState private var endDistance: CGFloat? = nil

    private let hourHeight = EditorMetrics.hourRowHeight
    private let topInset: CGFloat = 6
    private static let timelineSpace = "editorTimeline"

    private func y(_ minute: MinuteOfDay) -> CGFloat {
        CGFloat(minute) / 60 * hourHeight + topInset
    }

    var body: some View {
        let existing = store.timedEvents(on: day)
        let drafts = store.draftEvents.filter { $0.day == day }
        let isEditing: Bool = {
            if case .edit = store.mode { return true }
            return false
        }()
        let placements = TimelineLayout.placements(
            for: existing + drafts,
            minimumVisualMinutes: TimelineLayout.minimumVisualMinutes(blockHeight: Double(EditorMetrics.noEndBlockHeight),
                                                                     hourHeight: Double(hourHeight)))

        GeometryReader { geometry in
            let laneWidth = max(geometry.size.width - EditorMetrics.hourLabelWidth - 4, 0)
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                EditorHourRow(hour: hour, height: hourHeight)
                                    .id(hour)
                                    .contentShape(Rectangle())
                                    .onTapGesture { tapHour(hour) }
                            }
                        }
                        .padding(.top, topInset)

                        // 既存の予定。編集しているときは、ほかの予定を少し弱く出す（§42）
                        ForEach(existing) { event in
                            let placement = placements[event.id] ?? TimelinePlacement(column: 0, columnCount: 1)
                            let columnWidth = laneWidth / CGFloat(max(placement.columnCount, 1))
                            let height = blockHeight(duration: event.durationMinutes)
                            EditorEventBlock(event: event,
                                             color: store.metadata(for: event.id)?.color ?? .orange,
                                             isDraft: false,
                                             start: event.startMinute,
                                             end: event.endMinute,
                                             showsEnd: height >= EditorMetrics.blockTwoLineHeight)
                                .frame(width: max(columnWidth - 2, 0), height: height)
                                .opacity(isEditing ? 0.5 : 1)
                                .allowsHitTesting(false)
                                .alignmentGuide(.leading) { _ in -(EditorMetrics.hourLabelWidth + columnWidth * CGFloat(placement.column)) }
                                .alignmentGuide(.top) { _ in -y(event.startMinute) }
                        }

                        // 仮予定（新規・コピーの予定、編集中の予定）。上下にドラッグ、下端のハンドルで終了。
                        // 仮予定は描き直すたびに id が新しくなるので、日で見分ける（id で見分けると、指で動かしている途中で
                        // 別の物に置き換わり、操作が切れていた。2026-10-14 実機の「終了がうまく伸ばせない」）
                        ForEach(drafts, id: \.day) { event in
                            let placement = placements[event.id] ?? TimelinePlacement(column: 0, columnCount: 1)
                            let columnWidth = laneWidth / CGFloat(max(placement.columnCount, 1))
                            draftBlock(event, width: max(columnWidth - 2, 0))
                                .alignmentGuide(.leading) { _ in -(EditorMetrics.hourLabelWidth + columnWidth * CGFloat(placement.column)) }
                                .alignmentGuide(.top) { _ in -y(draggedStart(of: event) ?? event.startMinute) }
                        }

                        if let hour = wheelHour {
                            MinuteWheelCard(value: $wheelMinute, onConfirm: confirmWheel)
                                .alignmentGuide(.leading) { _ in -(EditorMetrics.hourLabelWidth + 4) }
                                .alignmentGuide(.top) { _ in -(y(hour * 60) + 2) }
                                .zIndex(1)
                        }
                    }
                    .frame(width: geometry.size.width, alignment: .topLeading)
                    // 指の動きは、この時間軸の上で測る（伸びていくブロックやハンドルの上で測ると、動きに合わせて基準もずれる）
                    .coordinateSpace(name: Self.timelineSpace)
                }
                // 仮予定を動かしている間・終了を伸ばしている間は、時間軸をスクロールさせない（指の動きを取り合わない）
                .scrollDisabled(moveDistance != nil || endDistance != nil)
                .onAppear { scroll(proxy) }
                .onChange(of: wheelMinute) { _, minute in
                    // ホイールを回すと、その場で仮予定の開始時刻が変わる（§38・§39）。0 分をまたげば時も変わる
                    if wheelHour != nil {
                        store.setStartMinute(minute, on: day)
                    }
                }
            }
        }
    }

    // MARK: - 仮予定

    private func blockHeight(duration: Int?) -> CGFloat {
        duration.map { max(CGFloat($0) / 60 * hourHeight, EditorMetrics.noEndBlockHeight) } ?? EditorMetrics.noEndBlockHeight
    }

    /// 動かしている途中の開始時刻（動かしていなければ nil）
    private func draggedStart(of event: CalendarEvent) -> MinuteOfDay? {
        moveDistance.map {
            TimeDragMath.startMinute(afterDragging: Double($0), from: event.startMinute, hourHeight: Double(hourHeight))
        }
    }

    /// 伸ばしている途中の終了時刻（伸ばしていなければ nil）
    private func draggedEnd(of event: CalendarEvent) -> MinuteOfDay? {
        endDistance.map { endMinute(of: event, afterDragging: $0) }
    }

    /// 下端のハンドルを dy だけ動かしたときの終了時刻。終了がまだなければ、低い固定のブロックの下端から伸ばし始める
    private func endMinute(of event: CalendarEvent, afterDragging dy: CGFloat) -> MinuteOfDay {
        let start = store.startMinutes[day] ?? event.startMinute
        let base = store.endMinute(on: day)
            ?? start + Int((EditorMetrics.noEndBlockHeight / hourHeight * 60).rounded())
        return TimeDragMath.endMinute(afterDragging: Double(dy), from: base, start: start, hourHeight: Double(hourHeight))
    }

    @ViewBuilder
    private func draftBlock(_ event: CalendarEvent, width: CGFloat) -> some View {
        let dragStart = draggedStart(of: event)
        let dragEnd = draggedEnd(of: event)
        let start = dragStart ?? event.startMinute
        // 上下に動かしている間も所要時間は保つ（終了も一緒に動く。2026-10-14 実機の不具合）。終了を伸ばしている間だけ、終了から長さを出す
        let duration = dragEnd.map { $0 - start } ?? store.durationMinutes(on: day)
        let end = duration.map { start + $0 }
        let height = blockHeight(duration: duration)

        EditorEventBlock(event: event, color: store.content.metadata.color, isDraft: true,
                         start: start, end: end, showsEnd: height >= EditorMetrics.blockTwoLineHeight)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            // ブロックを上下に動かす。書き込めない Apple カレンダーの予定は動かさない（§1.7）
            .highPriorityGesture(moveDrag(for: event), including: store.areAppleFieldsLocked ? .subviews : .all)
            .overlay(alignment: .topTrailing) {
                // 動かしている間は正確な時刻を出す（§40）。ブロックの上に出す
                if dragStart != nil && dragEnd == nil {
                    DragTimeLabel(text: TimeText.hourMinute(start))
                        .offset(y: -18)
                }
            }
            .overlay(alignment: .topLeading) {
                // 終了を伸ばしている間は、終了の時刻を出す（§41）。下端を押さえている指で隠れないよう、
                // 指より上・左寄りに出す（2026-10-14 実機の指摘。どれだけ上げるかは仮）
                if let dragEnd {
                    DragTimeLabel(text: "〜\(TimeText.hourMinute(dragEnd))")
                        .offset(x: 2, y: height - EditorMetrics.dragEndLabelLift)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // 動かしている間もその場で判定する。警告だけで保存は止めない（§58）
                if let warning = store.warnings(on: day, start: start).first {
                    Text(warning.message)
                        .font(EditorMetrics.warningFont)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Colors.warning.opacity(0.9)))
                        .fixedSize()
                        .offset(y: EditorMetrics.warningOffsetBelowBlock)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                // 書き込めない Apple カレンダーの予定は、時刻を動かせない（§1.7）。
                // 指で押さえやすいように、ブロックの幅いっぱい・下端の少し上からブロックの下まで広く取る（2026-10-14。大きさは仮）
                if !store.areAppleFieldsLocked {
                    EndHandle(width: width)
                        .offset(y: height - EditorMetrics.endHandleOverlap)
                        .highPriorityGesture(endDrag(for: event))
                }
            }
    }

    /// 仮予定を上下に動かす：開始時刻を変える。所要時間は保つ（§40）
    private func moveDrag(for event: CalendarEvent) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.timelineSpace))
            .updating($moveDistance) { value, distance, _ in
                distance = value.translation.height
            }
            .onChanged { _ in
                if wheelHour != nil { wheelHour = nil }
            }
            .onEnded { value in
                store.setStartMinute(TimeDragMath.startMinute(afterDragging: Double(value.translation.height),
                                                              from: event.startMinute, hourHeight: Double(hourHeight)),
                                     on: day)
            }
    }

    /// 下端のハンドルを伸ばす：終了時刻を決める。何もしなければ終了なし。右の「終了」の行と同じ値（§41・Q24）。
    /// 触れたらすぐ時間軸のスクロールを止める。触れただけで離したときは何もしない（終了のない予定に、触れただけで終了を入れない）
    private func endDrag(for event: CalendarEvent) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.timelineSpace))
            .updating($endDistance) { value, distance, _ in
                distance = value.translation.height
            }
            .onChanged { _ in
                if wheelHour != nil { wheelHour = nil }
            }
            .onEnded { value in
                guard abs(value.translation.height) >= EditorMetrics.endHandleMinimumMove else { return }
                store.setEndMinute(endMinute(of: event, afterDragging: value.translation.height), on: day)
            }
    }

    // MARK: - 「時」と分ホイール

    /// 「時」を押す：その時刻の 00 分を入れ、その位置に分ホイールを出す（§38）
    private func tapHour(_ hour: Int) {
        guard !store.areAppleFieldsLocked else { return }
        wheelHour = hour
        wheelMinute = TimeDragMath.startMinute(hour: hour, minute: 0)
        store.setStartMinute(wheelMinute, on: day)
    }

    /// 分を決める：時刻のまだない次の日へ移る（§36）
    private func confirmWheel() {
        wheelHour = nil
        store.confirmStartTime()
    }

    /// 初めの位置（§43）：予定がある日は最初の予定の少し前（未来の日は約 1 時間前が見える位置）、今日で予定がなければ現在時刻付近、
    /// 予定のない未来の日は 8:00（2026-10-14 決定 E8。未来日の「適切な時間帯」の正式な定義）
    private func scroll(_ proxy: ScrollViewProxy) {
        let today = CalendarDay(Date())
        let lead = day > today ? EditorMetrics.futureDayScrollLeadMinutes : EditorMetrics.dayScrollLeadMinutes
        let minute = store.suggestedScrollMinute(for: day, leadMinutes: lead)
            ?? (day == today ? max(Clock.minuteOfDay(Date()) - 60, 0) : EditorMetrics.emptyDayScrollMinute)
        proxy.scrollTo(min(max(minute / 60, 0), 23), anchor: .top)
    }
}

/// 仮予定を動かしている間・終了を伸ばしている間に出す、正確な時刻（§40・§41）
private struct DragTimeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(EditorMetrics.dragTimeFont)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.Colors.textPrimary.opacity(0.85)))
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// 仮予定の下端のハンドル（§41）。見た目は下端の小さなつまみだけ。押さえられる所はブロックの幅いっぱいで、下へ広く取る
private struct EndHandle: View {
    let width: CGFloat

    var body: some View {
        Color.clear
            .frame(width: width, height: EditorMetrics.endHandleHitHeight)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Theme.Colors.textPrimary.opacity(0.7))
                    .frame(width: EditorMetrics.endHandleWidth, height: 4)
                    .padding(.top, EditorMetrics.endHandleOverlap - 2)
            }
            .contentShape(Rectangle())
            .accessibilityLabel("終了時刻")
    }
}

/// 「時」を押した位置に出す、小さな分ホイール（§38）。初めは 00。標準の Picker を大きく出さず、TimyCue に馴染む小ささにする
private struct MinuteWheelCard: View {
    /// 0:00 からの分（5 分おき）
    @Binding var value: Int
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            // 時は、ホイールで選んでいる時刻に合わせて変わる
            Text("\(value / 60):")
                .font(EditorMetrics.wheelFont)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
            MinuteWheel(value: $value)
            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.Colors.accentFill))
            }
            .accessibilityLabel("決定")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .fill(Theme.Colors.surface)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
    }
}

/// 分の小さなホイール。5 分おき。上下に回して止まった位置の分を選ぶ。0 分をまたぐと時も変わる（2026-10-13 実機の指摘）
private struct MinuteWheel: View {
    /// 0:00 からの分
    @Binding var value: Int

    private let rowHeight = EditorMetrics.wheelRowHeight
    private let visibleRows: CGFloat = 3

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(TimeDragMath.wheelMinutes, id: \.self) { item in
                    Text(String(format: "%02d", item % 60))
                        .font(item == value ? EditorMetrics.wheelSelectedFont : EditorMetrics.wheelFont)
                        .foregroundStyle(item == value ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .frame(width: EditorMetrics.wheelWidth, height: rowHeight)
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding<Int?>(get: { value }, set: { if let new = $0 { value = new } }), anchor: .center)
        .contentMargins(.vertical, rowHeight * (visibleRows - 1) / 2, for: .scrollContent)
        .frame(width: EditorMetrics.wheelWidth, height: rowHeight * visibleRows)
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.Colors.accent.opacity(0.6), lineWidth: 1)
                .frame(height: rowHeight)
                .allowsHitTesting(false)
        }
    }
}

/// 1 時間の行
private struct EditorHourRow: View {
    let hour: Int
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("\(hour)")
                .font(EditorMetrics.hourLabelFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: EditorMetrics.hourLabelWidth - 6, alignment: .trailing)
                .offset(y: -6)
            Theme.Colors.separator
                .frame(height: 1)
                .padding(.leading, EditorMetrics.hourLabelWidth)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
    }
}

/// 時間画面の予定ブロック。保存前の仮予定は淡く・少し透明に・点線の枠（§39）。
/// 終了を決めてあって 2 段で書ける高さがあれば、2 段目に終了の時刻も出す（2026-10-14 ユーザー決定。書き方は仮）
private struct EditorEventBlock: View {
    let event: CalendarEvent
    let color: EventColor
    let isDraft: Bool
    /// 出す開始・終了（動かしている間は、動かした先）
    let start: MinuteOfDay
    let end: MinuteOfDay?
    let showsEnd: Bool

    private var text: String {
        // 予定名がまだなら「14:30 新規予定」（§39）
        let name = event.title.isEmpty && isDraft ? "新規予定" : event.displayTitle
        return "\(TimeText.hourMinute(start)) \(name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .lineLimit(1)
            if showsEnd, let end {
                Text("〜\(TimeText.hourMinute(end))")
                    .lineLimit(1)
            }
        }
        .font(EditorMetrics.blockFont)
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EventPalette.color(for: color).opacity(isDraft ? EditorMetrics.draftOpacity : 0.8))
        .overlay {
            if isDraft {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.Colors.textPrimary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
