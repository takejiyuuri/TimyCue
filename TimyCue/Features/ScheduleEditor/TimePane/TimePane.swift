import SwiftUI

/// 3 分割画面の左上：時間画面（仕様 §35〜§43）。上に日付タブ、その下にその日の縦タイムライン。
/// 「時」を押すとその位置に分ホイール（§38）。仮予定は上下にドラッグして開始時刻を変え（§40）、下端のハンドルで終了時刻を決める（§41）
struct TimePane: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            DateTabs()
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

/// 複数日を選んだときの日付タブ（§35）。入りきらなければ横スクロール。押した日の時間軸を出す。
/// 1 日だけのときは、その日を見出しとして出す。「予測で一括」は 2026-10-13 にやめた（ユーザー決定）
private struct DateTabs: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if store.selectedDays.count <= 1, let day = store.displayedDay ?? store.selectedDays.first {
                        Text("\(day.month)月\(day.day)日（\(day.weekdaySymbol())）")
                            .font(EditorMetrics.dateTabFont)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.horizontal, 6)
                    } else {
                        ForEach(store.selectedDays, id: \.self) { day in
                            let isShown = store.displayedDay == day
                            let hasTime = store.startMinutes[day] != nil
                            Text(day.shortLabel)
                                .font(EditorMetrics.dateTabFont)
                                .foregroundStyle(isShown ? Color.white : (hasTime ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(isShown ? Theme.Colors.accent : Theme.Colors.surface))
                                .onTapGesture { store.displayDay(day) }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: EditorMetrics.dateTabHeight)
        }
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
    /// 仮予定を動かしている間の開始時刻・終了時刻（§40・§41）。指を離したら store に入れる
    @State private var dragStart: MinuteOfDay?
    @State private var dragEnd: MinuteOfDay?

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
                            EditorEventBlock(event: event,
                                             color: store.metadata(for: event.id)?.color ?? .orange,
                                             isDraft: false)
                                .frame(width: max(columnWidth - 2, 0), height: blockHeight(duration: event.durationMinutes))
                                .opacity(isEditing ? 0.5 : 1)
                                .allowsHitTesting(false)
                                .alignmentGuide(.leading) { _ in -(EditorMetrics.hourLabelWidth + columnWidth * CGFloat(placement.column)) }
                                .alignmentGuide(.top) { _ in -y(event.startMinute) }
                        }

                        // 仮予定（新規・コピーの予定、編集中の予定）。上下にドラッグ、下端のハンドルで終了
                        ForEach(drafts) { event in
                            let placement = placements[event.id] ?? TimelinePlacement(column: 0, columnCount: 1)
                            let columnWidth = laneWidth / CGFloat(max(placement.columnCount, 1))
                            draftBlock(event, width: max(columnWidth - 2, 0))
                                .alignmentGuide(.leading) { _ in -(EditorMetrics.hourLabelWidth + columnWidth * CGFloat(placement.column)) }
                                .alignmentGuide(.top) { _ in -y(dragStart ?? event.startMinute) }
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

    @ViewBuilder
    private func draftBlock(_ event: CalendarEvent, width: CGFloat) -> some View {
        let start = dragStart ?? event.startMinute
        let end = dragEnd ?? store.endMinute(on: day)
        let duration = end.map { $0 - start }
        let height = blockHeight(duration: duration)

        EditorEventBlock(event: event, color: store.content.metadata.color, isDraft: true)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            // ブロックを動かす操作は、下端のハンドルより内側にだけ付ける（ハンドルの操作を奪わないように）
            .highPriorityGesture(moveDrag(for: event))
            .overlay(alignment: .topTrailing) {
                // 動かしている間は正確な時刻を出す（§40・§41）
                if dragStart != nil || dragEnd != nil {
                    Text(dragEnd != nil ? "〜\(TimeText.hourMinute(end ?? start))" : TimeText.hourMinute(start))
                        .font(EditorMetrics.dragTimeFont)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Colors.textPrimary.opacity(0.85)))
                        .offset(y: dragEnd != nil ? height - 6 : -18)
                        .fixedSize()
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
                        .offset(y: EditorMetrics.endHandleHeight + 4)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                // 書き込めない Apple カレンダーの予定は、時刻を動かせない（§1.7）
                if !store.areAppleFieldsLocked {
                    EndHandle()
                        .offset(y: EditorMetrics.endHandleHeight / 2)
                        .highPriorityGesture(endDrag(for: event))
                }
            }
    }

    /// 仮予定を上下に動かす：開始時刻を変える。所要時間は保つ（§40）
    private func moveDrag(for event: CalendarEvent) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.timelineSpace))
            .onChanged { value in
                guard !store.areAppleFieldsLocked else { return }
                wheelHour = nil
                dragStart = TimeDragMath.startMinute(afterDragging: Double(value.translation.height),
                                                     from: event.startMinute, hourHeight: Double(hourHeight))
            }
            .onEnded { _ in
                if let start = dragStart { store.setStartMinute(start, on: day) }
                dragStart = nil
            }
    }

    /// 下端のハンドルを伸ばす：終了時刻を決める。何もしなければ終了なし。右の「終了」の行と同じ値（§41・Q24）
    private func endDrag(for event: CalendarEvent) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.timelineSpace))
            .onChanged { value in
                wheelHour = nil
                let start = store.startMinutes[day] ?? event.startMinute
                // 終了がまだなければ、低い固定のブロックの下端から伸ばし始める
                let base = store.endMinute(on: day)
                    ?? start + Int((EditorMetrics.noEndBlockHeight / hourHeight * 60).rounded())
                dragEnd = TimeDragMath.endMinute(afterDragging: Double(value.translation.height),
                                                 from: base, start: start, hourHeight: Double(hourHeight))
            }
            .onEnded { _ in
                if let end = dragEnd { store.setEndMinute(end, on: day) }
                dragEnd = nil
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

    /// 初めの位置（§43）：予定がある日は最初の予定の少し前、今日で予定がなければ現在時刻付近、ほかは 8:00（未来日の「適切な時間帯」は仮）
    private func scroll(_ proxy: ScrollViewProxy) {
        let minute = store.suggestedScrollMinute(for: day)
            ?? (day == CalendarDay(Date()) ? max(Clock.minuteOfDay(Date()) - 60, 0) : 8 * 60)
        proxy.scrollTo(min(max(minute / 60, 0), 23), anchor: .top)
    }
}

/// 仮予定の下端のハンドル（§41）
private struct EndHandle: View {
    var body: some View {
        Capsule()
            .fill(Theme.Colors.textPrimary.opacity(0.7))
            .frame(width: EditorMetrics.endHandleWidth, height: 4)
            .frame(width: EditorMetrics.endHandleWidth + 20, height: EditorMetrics.endHandleHeight)
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
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.Colors.accent))
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

/// 時間画面の予定ブロック。保存前の仮予定は淡く・少し透明に・点線の枠（§39）
private struct EditorEventBlock: View {
    let event: CalendarEvent
    let color: EventColor
    let isDraft: Bool

    private var text: String {
        // 予定名がまだなら「14:30 新規予定」（§39）
        let name = event.title.isEmpty && isDraft ? "新規予定" : event.displayTitle
        return "\(TimeText.hourMinute(event.startMinute)) \(name)"
    }

    var body: some View {
        Text(text)
            .font(EditorMetrics.blockFont)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
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
