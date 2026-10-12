import SwiftUI

/// 1 日タイムライン（仕様 §25〜§30）。カレンダーで予定を見るための画面で、ここでは編集しない。
/// 予定ブロックを押すと、そのブロックの近くに予定詳細の吹き出しを出す（Q17・Q27・Q28(b)）
struct DayTimelineView: View {
    let day: CalendarDay
    @Environment(CalendarStore.self) private var store
    @Environment(ScheduleEditorStore.self) private var editorStore
    @Environment(CalendarConnection.self) private var connection
    /// 「＋」で開いた新規の 3 分割画面（Q21）。この画面は残るので、ズームの倍率もそのまま（Q22）
    @State private var showsNewEvent = false

    /// ピンチで変えた倍率。保存せず、開き直したら標準の倍率に戻る（仕様 §27）
    @State private var zoom: CGFloat = 1
    /// ピンチを始めたときの倍率・指の高さ・指の下にあった時刻（Q16：指の位置を中心に伸び縮みさせる）
    @State private var pinchBase: CGFloat?
    @State private var pinchFingerY: CGFloat = 0
    @State private var pinchMinute: Double?
    /// タイムラインの中身の上端が、スクロール画面の上からどれだけずれているか（上へスクロールすると負）
    @State private var contentMinY: CGFloat = 0
    /// 現在時刻の線が画面の中に見えているか（仕様 §28）
    @State private var isNowVisible = true
    /// 現在時刻。開いている間、30 秒ごとに更新する
    @State private var now = Date()

    static let scrollSpace = "DayTimelineScroll"

    var body: some View {
        let isToday = day == store.today
        let events = store.timedEvents(on: day)
        let allDay = store.allDayEvents(on: day)
        // 同じ予定が 2 つ届いても落ちないように（uniqueKeysWithValues は重なると止まる）
        let colors = Dictionary((events + allDay).map { ($0.id, store.color(for: $0)) }, uniquingKeysWith: { first, _ in first })
        let hourHeight = TimelineMetrics.hourHeight * zoom
        let placements = TimelineLayout.placements(
            for: events,
            minimumVisualMinutes: TimelineLayout.minimumVisualMinutes(blockHeight: Double(TimelineMetrics.noEndBlockHeight),
                                                                     hourHeight: Double(hourHeight)))

        VStack(spacing: 0) {
            if !allDay.isEmpty {
                AllDayBandView(events: allDay, colors: colors)
            }
            GeometryReader { outer in
                ScrollViewReader { proxy in
                    ScrollView {
                        DayTimelineCanvas(events: events,
                                          placements: placements,
                                          colors: colors,
                                          zoom: zoom,
                                          width: outer.size.width,
                                          nowMinute: isToday ? Clock.minuteOfDay(now) : nil)
                    }
                    .coordinateSpace(name: Self.scrollSpace)
                    .onPreferenceChange(NowLineYKey.self) { y in
                        isNowVisible = y.map { $0 >= 0 && $0 <= outer.size.height } ?? true
                    }
                    .onPreferenceChange(TimelineContentMinYKey.self) { minY in
                        contentMinY = minY
                    }
                    .simultaneousGesture(pinchGesture(proxy: proxy, viewportHeight: outer.size.height))
                    .overlay(alignment: .bottomTrailing) {
                        if isToday && !isNowVisible {
                            nowButton(proxy: proxy)
                        }
                    }
                    .onAppear {
                        let minute = TimelineLayout.initialMinute(events: events, isToday: isToday, now: Clock.minuteOfDay(now))
                        proxy.scrollTo(TimelineAnchor.hour(minute / 60), anchor: .top)
                    }
                    // 「＋」から保存したら、作った予定が見える位置までスクロールする（Q22）
                    .onChange(of: store.timelineFocus) { _, focus in
                        guard let focus, focus.day == day else { return }
                        withAnimation {
                            proxy.scrollTo(TimelineAnchor.marker(nearest: Double(max(focus.minute - 30, 0))), anchor: .top)
                        }
                        store.clearTimelineFocus()
                    }
                }
            }
        }
        .overlayPreferenceValue(TimelineDetailAnchorKey.self) { anchor in
            TimelineDetailLayer(anchor: anchor)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .navigationTitle("\(day.month)月\(day.day)日（\(day.weekdaySymbol())）")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 1 日タイムラインの「＋」（Q21）：表示中の日を選んだ新規。開始時刻は未設定
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorStore.refresh()
                    editorStore.startNew(on: day)
                    showsNewEvent = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新規予定")
            }
        }
        .fullScreenCover(isPresented: $showsNewEvent) {
            ScheduleEditorView(initialMonth: CalendarMonth(day), onSaved: { saved in
                // この日に作った予定があればそれ、なければ最初の予定の時刻へ（Q22）
                let target = saved.filter { $0.day == day }.min { $0.startMinute < $1.startMinute } ?? saved.first
                if let target {
                    store.focusTimeline(on: day, minute: target.startMinute)
                }
            })
            .environment(editorStore)
            .environment(store)
            .environment(connection)
        }
    }
}

extension DayTimelineView {
    /// 縦のピンチで拡大・縮小する。つまみ始めに指の下にあった時刻を、指の高さに保つ（仕様 §27・Q16）
    private func pinchGesture(proxy: ScrollViewProxy, viewportHeight: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBase == nil {
                    pinchBase = zoom
                    pinchFingerY = value.startLocation.y
                    pinchMinute = TimelineLayout.minute(atContentY: Double(value.startLocation.y - contentMinY),
                                                        hourHeight: Double(TimelineMetrics.hourHeight * zoom),
                                                        topInset: Double(TimelineMetrics.topInset))
                }
                let base = pinchBase ?? zoom
                zoom = min(max(base * value.magnification, TimelineMetrics.zoomRange.lowerBound),
                           TimelineMetrics.zoomRange.upperBound)
                guard let minute = pinchMinute, viewportHeight > 0 else { return }
                let marker = TimelineAnchor.marker(nearest: minute)
                let anchor = UnitPoint(x: 0.5, y: min(max(pinchFingerY / viewportHeight, 0), 1))
                // 倍率を変えたあとの並びで合わせるため、次の描画で動かす
                DispatchQueue.main.async {
                    proxy.scrollTo(marker, anchor: anchor)
                }
            }
            .onEnded { _ in
                pinchBase = nil
                pinchMinute = nil
            }
    }

    /// 現在時刻の線が画面の外にあるときの「今へ」（仕様 §28）
    private func nowButton(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation { proxy.scrollTo(TimelineAnchor.now, anchor: .center) }
        } label: {
            Label("今へ", systemImage: "arrow.uturn.down")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.Colors.accent))
                .foregroundStyle(.white)
        }
        .padding(16)
    }
}

/// スクロールで移るときの目印
enum TimelineAnchor {
    static let now = "now"

    static func hour(_ hour: Int) -> String { "hour-\(min(max(hour, 0), 23))" }

    /// ピンチの中心を合わせる目印（TimelineMetrics.pinchMarkerMinutes 分ごと）
    static func marker(_ minute: Int) -> String { "minute-\(minute)" }

    static func marker(nearest minute: Double) -> String {
        let step = Double(TimelineMetrics.pinchMarkerMinutes)
        let rounded = Int((minute / step).rounded()) * TimelineMetrics.pinchMarkerMinutes
        return marker(min(max(rounded, 0), MinuteOfDay.minutesPerDay))
    }
}

/// 現在時刻の線の、スクロール画面の中での高さの位置
struct NowLineYKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// 予定詳細の吹き出しを出している予定ブロックの位置
struct TimelineDetailAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// 予定ブロックの近くに出す予定詳細の吹き出し（Q28(b)）。
/// ブロックを隠さないことを優先し、画面の空きに応じて上下左右に置く（置き場所の決まりは PopoverPlacement）
private struct TimelineDetailLayer: View {
    let anchor: Anchor<CGRect>?
    @Environment(CalendarStore.self) private var store
    @Environment(ScheduleEditorStore.self) private var editorStore
    @State private var measuredHeight: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            if let anchor, let id = store.timelineDetailEventID, let event = store.event(id: id) {
                let width = min(CalendarMetrics.popoverMaxWidth, proxy.size.width * CalendarMetrics.popoverWidthRatio)
                let frame = PopoverPlacement.frames(
                    container: proxy.size,
                    anchors: [proxy[anchor]],
                    sizes: [CGSize(width: width, height: measuredHeight ?? DayPopoverLayer.estimatedDetailHeight)],
                    gap: CalendarMetrics.popoverGap,
                    margin: CalendarMetrics.popoverMargin)[0]
                EventDetailCard(event: event, metadata: store.metadata(for: id)) {
                    editorStore.beginEditing(id, from: store)
                }
                .popoverBubble()
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: TimelineDetailHeightKey.self, value: geometry.size.height)
                    }
                }
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .onPreferenceChange(TimelineDetailHeightKey.self) { height in
            measuredHeight = height
        }
    }
}

private struct TimelineDetailHeightKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// タイムラインの中身の上端の、スクロール画面の中での位置
struct TimelineContentMinYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 時間軸と予定ブロック（仕様 §26・§29）
private struct DayTimelineCanvas: View {
    let events: [CalendarEvent]
    let placements: [UUID: TimelinePlacement]
    let colors: [UUID: EventColor]
    let zoom: CGFloat
    let width: CGFloat
    /// 今日なら現在時刻（分）。ほかの日は nil
    let nowMinute: MinuteOfDay?
    @Environment(CalendarStore.self) private var store

    private var hourHeight: CGFloat { TimelineMetrics.hourHeight * zoom }

    private func y(_ minute: MinuteOfDay) -> CGFloat {
        TimelineMetrics.topInset + CGFloat(minute) / 60 * hourHeight
    }

    var body: some View {
        let laneWidth = max(width - TimelineMetrics.hourLabelWidth - 8, 0)

        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HourRowView(hour: hour, height: hourHeight)
                        .id(TimelineAnchor.hour(hour))
                }
                HourRowView(hour: 24, height: 0)
            }
            .padding(.top, TimelineMetrics.topInset)

            // ピンチの中心を合わせるための、見えない目印（Q16）
            ForEach(Array(stride(from: 0, through: MinuteOfDay.minutesPerDay, by: TimelineMetrics.pinchMarkerMinutes)), id: \.self) { minute in
                Color.clear
                    .frame(width: 1, height: 1)
                    .alignmentGuide(.top) { _ in -y(minute) }
                    .id(TimelineAnchor.marker(minute))
            }

            ForEach(events) { event in
                let placement = placements[event.id] ?? TimelinePlacement(column: 0, columnCount: 1)
                let columnWidth = laneWidth / CGFloat(max(placement.columnCount, 1))
                // 終了時刻のない予定は低い固定の高さ。見た目だけで、終了時刻としては扱わない（Q15）
                let height = event.durationMinutes.map { max(CGFloat($0) / 60 * hourHeight, TimelineMetrics.noEndBlockHeight) }
                    ?? TimelineMetrics.noEndBlockHeight
                let isSelected = store.timelineDetailEventID == event.id
                EventBlockView(event: event, color: colors[event.id] ?? .orange, height: height)
                    .frame(width: max(columnWidth - TimelineMetrics.blockColumnGap, 0), height: height)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: TimelineMetrics.blockCornerRadius)
                                .strokeBorder(Theme.Colors.accent, lineWidth: 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.tapTimelineEvent(event.id) }
                    .anchorPreference(key: TimelineDetailAnchorKey.self, value: .bounds) { isSelected ? $0 : nil }
                    .alignmentGuide(.leading) { _ in -(TimelineMetrics.hourLabelWidth + columnWidth * CGFloat(placement.column)) }
                    .alignmentGuide(.top) { _ in -y(event.startMinute) }
            }

            if let nowMinute {
                NowLineView(minute: nowMinute)
                    .frame(width: width)
                    .alignmentGuide(.top) { dimensions in -(y(nowMinute) - dimensions.height / 2) }
                    .id(TimelineAnchor.now)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: y(24 * 60) + TimelineMetrics.topInset, alignment: .topLeading)
        // 予定ブロックの外を押したら、予定詳細の吹き出しを閉じる（Q29）
        .contentShape(Rectangle())
        .onTapGesture { store.closeTimelineDetail() }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: TimelineContentMinYKey.self,
                                       value: geometry.frame(in: .named(DayTimelineView.scrollSpace)).minY)
            }
        }
    }
}

/// 1 時間分の行。上端に主線、真ん中に 30 分の薄い補助線（仕様 §26。5 分線などは出さない）
private struct HourRowView: View {
    let hour: Int
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("\(hour):00")
                .font(TimelineMetrics.hourLabelFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: TimelineMetrics.hourLabelWidth - 6, alignment: .trailing)
                .offset(y: -7)
            Theme.Colors.separator
                .frame(height: TimelineMetrics.hourLineWidth)
                .padding(.leading, TimelineMetrics.hourLabelWidth)
            if height > 0 {
                Theme.Colors.separator
                    .opacity(TimelineMetrics.halfHourLineOpacity)
                    .frame(height: TimelineMetrics.halfHourLineWidth)
                    .padding(.leading, TimelineMetrics.hourLabelWidth)
                    .offset(y: height / 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
    }
}

/// 予定ブロック
private struct EventBlockView: View {
    let event: CalendarEvent
    let color: EventColor
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            EventPalette.color(for: color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.displayTitle)
                    .font(TimelineMetrics.blockTitleFont)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(height < 40 ? 1 : 2)
                if height >= 40 {
                    Text(CalendarStore.timeText(for: event))
                        .font(TimelineMetrics.blockTimeFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(EventPalette.color(for: color).opacity(TimelineMetrics.blockFillOpacity))
        .clipShape(RoundedRectangle(cornerRadius: TimelineMetrics.blockCornerRadius))
    }
}

/// 現在時刻の線（仕様 §28。例：現在 14:18）
private struct NowLineView: View {
    let minute: MinuteOfDay

    var body: some View {
        HStack(spacing: 4) {
            Text("現在 \(TimeText.hourMinute(minute))")
                .font(TimelineMetrics.nowLabelFont)
                .foregroundStyle(Theme.Colors.danger)
                .fixedSize()
                .frame(width: TimelineMetrics.hourLabelWidth + 20, alignment: .trailing)
            Theme.Colors.danger
                .frame(height: TimelineMetrics.nowLineWidth)
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: NowLineYKey.self,
                                       value: geometry.frame(in: .named(DayTimelineView.scrollSpace)).midY)
            }
        }
    }
}

/// 終日専用帯。終日の予定はタイムラインの 0:00〜24:00 を使わず、上にまとめる（仕様 §30）
private struct AllDayBandView: View {
    let events: [CalendarEvent]
    let colors: [UUID: EventColor]
    @Environment(CalendarStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("終日")
                .font(TimelineMetrics.hourLabelFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: TimelineMetrics.hourLabelWidth - 6, alignment: .trailing)
                .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(events) { event in
                        let color = EventPalette.color(for: colors[event.id] ?? .orange)
                        let isSelected = store.timelineDetailEventID == event.id
                        HStack(spacing: 4) {
                            Circle()
                                .fill(color)
                                .frame(width: 7, height: 7)
                            Text(event.displayTitle)
                                .font(TimelineMetrics.allDayChipFont)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(color.opacity(TimelineMetrics.blockFillOpacity)))
                        .overlay {
                            if isSelected {
                                Capsule().strokeBorder(Theme.Colors.accent, lineWidth: 2)
                            }
                        }
                        .contentShape(Capsule())
                        .onTapGesture { store.tapTimelineEvent(event.id) }
                        .anchorPreference(key: TimelineDetailAnchorKey.self, value: .bounds) { isSelected ? $0 : nil }
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.vertical, 6)
        .frame(maxHeight: TimelineMetrics.allDayBandMaxHeight)
        .background(Theme.Colors.surface)
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
    }
}
