import SwiftUI

/// 1 日タイムライン（仕様 §25〜§30）。カレンダーで予定を見るための画面で、ここでは編集しない。
struct DayTimelineView: View {
    let day: CalendarDay
    @Environment(CalendarStore.self) private var store

    /// ピンチで変えた倍率。保存せず、開き直したら標準の倍率に戻る（仕様 §27）
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat?
    /// 現在時刻の線が画面の中に見えているか（仕様 §28）
    @State private var isNowVisible = true
    /// 現在時刻。開いている間、30 秒ごとに更新する
    @State private var now = Date()

    static let scrollSpace = "DayTimelineScroll"

    var body: some View {
        let isToday = day == store.today
        let events = store.timedEvents(on: day)
        let allDay = store.allDayEvents(on: day)
        let colors = Dictionary(uniqueKeysWithValues: (events + allDay).map { ($0.id, store.color(for: $0)) })

        VStack(spacing: 0) {
            if !allDay.isEmpty {
                AllDayBandView(events: allDay, colors: colors)
            }
            GeometryReader { outer in
                ScrollViewReader { proxy in
                    ScrollView {
                        DayTimelineCanvas(events: events,
                                          placements: TimelineLayout.placements(for: events),
                                          colors: colors,
                                          zoom: zoom,
                                          width: outer.size.width,
                                          nowMinute: isToday ? Clock.minuteOfDay(now) : nil)
                    }
                    .coordinateSpace(name: Self.scrollSpace)
                    .onPreferenceChange(NowLineYKey.self) { y in
                        isNowVisible = y.map { $0 >= 0 && $0 <= outer.size.height } ?? true
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isToday && !isNowVisible {
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
                    .onAppear {
                        let minute = TimelineLayout.initialMinute(events: events, isToday: isToday, now: Clock.minuteOfDay(now))
                        proxy.scrollTo(TimelineAnchor.hour(minute / 60), anchor: .top)
                    }
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? zoom
                        if pinchBase == nil { pinchBase = zoom }
                        zoom = min(max(base * value.magnification, TimelineMetrics.zoomRange.lowerBound),
                                   TimelineMetrics.zoomRange.upperBound)
                    }
                    .onEnded { _ in pinchBase = nil }
            )
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
    }
}

/// スクロールで移るときの目印
enum TimelineAnchor {
    static let now = "now"

    static func hour(_ hour: Int) -> String { "hour-\(min(max(hour, 0), 23))" }
}

/// 現在時刻の線の、スクロール画面の中での高さの位置
struct NowLineYKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
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

    /// 0:00 の文字が上で切れないための余白
    private let topInset: CGFloat = 10
    private var hourHeight: CGFloat { TimelineMetrics.hourHeight * zoom }

    private func y(_ minute: MinuteOfDay) -> CGFloat {
        topInset + CGFloat(minute) / 60 * hourHeight
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
            .padding(.top, topInset)

            ForEach(events) { event in
                let placement = placements[event.id] ?? TimelinePlacement(column: 0, columnCount: 1)
                let columnWidth = laneWidth / CGFloat(max(placement.columnCount, 1))
                let height = event.durationMinutes.map { max(CGFloat($0) / 60 * hourHeight, TimelineMetrics.noEndBlockHeight) }
                    ?? TimelineMetrics.noEndBlockHeight
                EventBlockView(event: event, color: colors[event.id] ?? .orange, height: height)
                    .frame(width: max(columnWidth - TimelineMetrics.blockColumnGap, 0), height: height)
                    .alignmentGuide(.leading) { _ in -(TimelineMetrics.hourLabelWidth + columnWidth * CGFloat(placement.column)) }
                    .alignmentGuide(.top) { _ in -y(event.startMinute) }
            }

            if let nowMinute {
                NowLineView(minute: nowMinute)
                    .frame(width: width)
                    .alignmentGuide(.top) { dimensions in -(y(nowMinute) - dimensions.height / 2) }
                    .id(TimelineAnchor.now)
            }
        }
        .frame(width: width, height: y(24 * 60) + topInset, alignment: .topLeading)
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

    private var timeText: String {
        let start = TimeText.hourMinute(event.startMinute)
        guard let end = event.endMinute else { return start }
        return "\(start)–\(TimeText.hourMinute(end))"
    }

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
                    Text(timeText)
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
