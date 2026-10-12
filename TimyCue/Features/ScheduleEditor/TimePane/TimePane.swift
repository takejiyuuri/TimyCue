import SwiftUI

/// 3 分割画面の左上：時間画面（仕様 §35〜§43）。上に日付タブ、その下にその日の縦タイムライン。
/// 今は「時」を押すとその時刻ちょうどの開始時刻が入る。分ホイール（§38）・仮予定のドラッグ（§40）・終了のハンドル（§41）は次の段階で作る
struct TimePane: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            DateTabs()
            if let day = store.displayedDay {
                EditorTimeAxis(day: day)
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
/// 1 日だけのときは、その日を見出しとして出す
private struct DateTabs: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
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
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
    }
}

/// その日の縦タイムライン（§37）。既存の予定と、保存前の仮予定（§39）を出す
private struct EditorTimeAxis: View {
    let day: CalendarDay
    @Environment(ScheduleEditorStore.self) private var store

    private let hourHeight = EditorMetrics.hourRowHeight

    private func y(_ minute: MinuteOfDay) -> CGFloat {
        CGFloat(minute) / 60 * hourHeight + 6
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
                                    // 「時」を押す（§38）。分ホイールは次の段階。今はその時刻ちょうどを入れる
                                    .onTapGesture { store.setStartMinute(hour * 60, on: day) }
                            }
                        }
                        .padding(.top, 6)

                        ForEach(existing + drafts) { event in
                            let isDraft = drafts.contains { $0.id == event.id }
                            let placement = placements[event.id] ?? TimelinePlacement(column: 0, columnCount: 1)
                            let columnWidth = laneWidth / CGFloat(max(placement.columnCount, 1))
                            let height = event.durationMinutes.map { max(CGFloat($0) / 60 * hourHeight, EditorMetrics.noEndBlockHeight) }
                                ?? EditorMetrics.noEndBlockHeight
                            EditorEventBlock(event: event,
                                             color: isDraft ? store.content.metadata.color : (store.metadata(for: event.id)?.color ?? .orange),
                                             isDraft: isDraft)
                                .frame(width: max(columnWidth - 2, 0), height: height)
                                // 既存の予定を編集しているときは、ほかの予定を少し弱く出す（§42）
                                .opacity(!isDraft && isEditing ? 0.5 : 1)
                                .allowsHitTesting(false)
                                .alignmentGuide(.leading) { _ in -(EditorMetrics.hourLabelWidth + columnWidth * CGFloat(placement.column)) }
                                .alignmentGuide(.top) { _ in -y(event.startMinute) }
                        }
                    }
                    .frame(width: geometry.size.width, alignment: .topLeading)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: day) { _, _ in scroll(proxy) }
            }
        }
    }

    /// 初めの位置（§43）：予定がある日は最初の予定の少し前、今日で予定がなければ現在時刻付近、ほかは 8:00（未来日の「適切な時間帯」は仮）
    private func scroll(_ proxy: ScrollViewProxy) {
        let minute = store.suggestedScrollMinute(for: day)
            ?? (day == CalendarDay(Date()) ? max(Clock.minuteOfDay(Date()) - 60, 0) : 8 * 60)
        proxy.scrollTo(min(max(minute / 60, 0), 23), anchor: .top)
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
