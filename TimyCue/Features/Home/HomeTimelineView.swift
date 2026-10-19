import SwiftUI

/// タイムラインの点の位置を、縦の線を描く層へ渡す
struct HomeRailDotKey: PreferenceKey {
    static let defaultValue: [HomeRailDot: Anchor<CGRect>] = [:]

    static func reduce(value: inout [HomeRailDot: Anchor<CGRect>], nextValue: () -> [HomeRailDot: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 吹き出しを出す行（予定の行・出発の点・「終わった予定 ○件」）の位置を、吹き出しの層へ渡す
struct HomeBubbleAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// タイムラインの点（縦の線でつなぐ）
    func homeRailDot(_ dot: HomeRailDot) -> some View {
        anchorPreference(key: HomeRailDotKey.self, value: .bounds) { [dot: $0] }
    }

    /// 吹き出しを出す位置
    func homeBubbleAnchor(_ id: String) -> some View {
        anchorPreference(key: HomeBubbleAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// 左のタイムライン（spec §88.2・Q81〜Q84・Q87）：（過ぎた出発の点）→「いま」→ これからの出発・予定の点。
/// 人型は、この上（演出帯の左の列のいちばん下）にいる。縦にスクロールしない：使える高さに合わせて密度を変え、入らない予定は「ほか○件」
struct HomeRailSection: View {
    let timeline: HomeTimeline
    /// 文字の大きさの設定に合わせた行の高さの倍率
    let scale: CGFloat
    /// 案内する予定が替わるときに行を上へ詰める動きをするか（「視差効果を減らす」・低電力モードでは動かさない：§88.8）
    let animates: Bool
    /// 予定がないときの［予定を登録］（Q43）
    let showsRegister: Bool
    let color: (CalendarEvent) -> EventColor
    let transport: (CalendarEvent) -> String
    let onTapRow: (HomeTimeline.Item) -> Void
    let onTapPastDeparture: (HomeTimeline.PastDeparture) -> Void
    let onMore: () -> Void
    let onRegister: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(timeline.aboveNow.filter { $0 != .figure }, id: \.self) { item in
                switch item {
                case .pastDeparture:
                    if let past = timeline.pastDeparture {
                        HomePastDepartureRow(past: past, transport: transport(past.event), color: color(past.event)) {
                            onTapPastDeparture(past)
                        }
                        .frame(height: HomeLayoutMetrics.pastDepartureRowHeight * scale)
                    }
                case .now:
                    HomeNowRow(now: timeline.now)
                        .frame(height: HomeLayoutMetrics.nowRowHeight * scale)
                case .figure:
                    // 人型は演出帯の左の列のいちばん下（このすぐ上）に置く
                    EmptyView()
                }
            }
            GeometryReader { proxy in
                let reserve = showsRegister ? HomeLayoutMetrics.registerReserve * scale : 0
                rows(HomeTimelineLayout.plan(items: timeline.items, availableHeight: proxy.size.height - reserve, scale: scale))
            }
            // 万一入りきらなくても、下の案内（連携のカードなど）に重ねない（Home はスクロールさせない）
            .clipped()
        }
        // 点どうしを縦の線でつなぐ（線は点の後ろ）
        .backgroundPreferenceValue(HomeRailDotKey.self) { dots in
            HomeRailLines(dots: dots)
        }
    }

    private func rows(_ plan: HomeTimelineLayout.Plan) -> some View {
        let fonts = HomeLayoutMetrics.fonts(plan.density)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(plan.rows) { row in
                HomeTimelineRowView(item: row.item,
                                    today: timeline.today,
                                    fonts: fonts,
                                    color: row.item.event.map(color) ?? .orange,
                                    transport: row.item.event.map(transport) ?? "") {
                    onTapRow(row.item)
                }
                .frame(height: row.height)
                .padding(.bottom, row.spacingAfter)
            }
            if plan.showsMore {
                moreRow(count: plan.hiddenEventCount, fonts: fonts)
                    .frame(height: plan.moreRowHeight)
            }
            if showsRegister {
                HomeRegisterButton(action: onRegister)
                    .padding(.top, Theme.Spacing.m)
            }
        }
        // 案内する予定が替わったら、行を自然に上へ詰める（§88.2）
        .animation(animates ? .easeInOut(duration: HomeLayoutMetrics.rowAnimation) : nil, value: plan.rows.map(\.id))
    }

    /// 入りきらない予定（Q84）。押すとカレンダーの今日を開く
    private func moreRow(count: Int, fonts: HomeRowFonts) -> some View {
        HStack(spacing: HomeLayoutMetrics.railGap) {
            Color.clear.frame(width: HomeLayoutMetrics.railWidth, height: 1)
            Text("ほか\(count)件")
                .font(fonts.title)
            Image(systemName: "chevron.right")
                .font(fonts.detail)
        }
        .foregroundStyle(Theme.Colors.actionText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onMore)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("カレンダーで今日の予定を開きます")
    }
}

/// 「いま 8:52」（左の縦のタイムラインの起点。§88.2）
struct HomeNowRow: View {
    let now: Date

    var body: some View {
        HStack(spacing: HomeLayoutMetrics.railGap) {
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: HomeLayoutMetrics.nowDot, height: HomeLayoutMetrics.nowDot)
                .homeRailDot(HomeRailDot(rowID: "now", role: .now, eventID: nil, color: nil))
                .frame(width: HomeLayoutMetrics.railWidth)
            Text("いま")
            Text(TimeText.hourMinute(Clock.minuteOfDay(now)))
        }
        .font(HomeLayoutMetrics.nowFont)
        .foregroundStyle(Theme.Colors.actionText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 過ぎた出発の点（Q83・Q87）：人型と「いま」のあいだに、控えめな 1 行で。出発時刻を過ぎただけで「出発済み」の印にはしない
struct HomePastDepartureRow: View {
    let past: HomeTimeline.PastDeparture
    let transport: String
    let color: EventColor
    let onTap: () -> Void

    static let anchorID = "past-departure"

    var body: some View {
        HStack(spacing: HomeLayoutMetrics.railGap) {
            Circle()
                .strokeBorder(Theme.Colors.textSecondary, lineWidth: 1.5)
                .background(Circle().fill(Theme.Colors.homeBackground))
                .frame(width: HomeLayoutMetrics.departureDot, height: HomeLayoutMetrics.departureDot)
                .homeRailDot(HomeRailDot(rowID: Self.anchorID, role: .pastDeparture, eventID: past.event.id, color: color))
                .frame(width: HomeLayoutMetrics.railWidth)
            Text(TimeText.hourMinute(Clock.minuteOfDay(past.leaveAt)))
                .monospacedDigit()
            Text("出発・\(transport)")
        }
        .font(.footnote)
        .foregroundStyle(Theme.Colors.textSecondary)
        .opacity(HomeLayoutMetrics.pastDepartureOpacity)
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .homeBubbleAnchor(Self.anchorID)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// タイムラインの 1 行（出発の点・予定開始の点・進行中・日付の区切り・文）。
/// 主状態の予定は予定名と場所の 2 行の札で強調し、ほかの予定と出発の点は 1 行（§88.2・Q84）
struct HomeTimelineRowView: View {
    let item: HomeTimeline.Item
    let today: CalendarDay
    let fonts: HomeRowFonts
    let color: EventColor
    /// 移動手段（設定どおり。「自動」は「自動」のまま：Q81・Q77-5）
    let transport: String
    let onTap: () -> Void

    var body: some View {
        switch item.kind {
        case .daySeparator(let day):
            Text(HomeTimeline.separatorText(day, today: today))
                .font(fonts.detail.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .padding(.leading, HomeLayoutMetrics.railWidth + HomeLayoutMetrics.railGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .message(let text):
            Text(text)
                .font(.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.leading, HomeLayoutMetrics.railWidth + HomeLayoutMetrics.railGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .departure, .start, .inProgress:
            HStack(spacing: HomeLayoutMetrics.railGap) {
                dot
                    .frame(width: HomeLayoutMetrics.railWidth)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // 押したら、別画面へ移らず Home の上に予定詳細の吹き出しを出す（v1.2「予定詳細の表示方式」）
            .onTapGesture(perform: onTap)
            .homeBubbleAnchor(item.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
        }
    }

    private var timeText: String {
        TimeText.hourMinute(Clock.minuteOfDay(item.date))
    }

    private var title: String {
        item.event?.displayTitle ?? ""
    }

    private var place: String? {
        guard let place = item.event?.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty else {
            return nil
        }
        return place
    }

    /// 進行中の予定の終わりの時刻（「14:30まで」）
    private var endText: String? {
        if case .inProgress(let end?) = item.kind {
            return "\(TimeText.hourMinute(Clock.minuteOfDay(end)))まで"
        }
        return nil
    }

    /// 主状態の予定の 2 行目（場所。進行中なら終わりの時刻も）
    private var mainDetail: String? {
        let parts = [place, endText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "　")
    }

    private var dotSize: CGFloat {
        item.isMain ? HomeLayoutMetrics.mainEventDot : HomeLayoutMetrics.eventDot
    }

    @ViewBuilder
    private var dot: some View {
        if item.isDeparture {
            Circle()
                .strokeBorder(Theme.Colors.textSecondary, lineWidth: 1.5)
                .background(Circle().fill(Theme.Colors.homeBackground))
                .frame(width: HomeLayoutMetrics.departureDot, height: HomeLayoutMetrics.departureDot)
                .homeRailDot(HomeRailDot(rowID: item.id, role: .departure, eventID: item.event?.id, color: color))
        } else {
            Circle()
                .fill(EventPalette.color(for: color))
                .overlay {
                    Circle().strokeBorder(item.isMain ? Theme.Colors.accent : Theme.Colors.separator, lineWidth: item.isMain ? 1.5 : 1)
                }
                .frame(width: dotSize, height: dotSize)
                .homeRailDot(HomeRailDot(rowID: item.id, role: .start, eventID: item.event?.id, color: color))
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.isDeparture {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                time(fonts.time)
                Text("出発・\(transport)")
                    .font(fonts.departure)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        } else if item.isMain {
            mainCard
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                time(fonts.time)
                Text(title)
                    .font(fonts.title)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let endText {
                    Text(endText)
                        .font(fonts.detail)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    /// 主状態の予定：予定名と場所の 2 行の札（場所がなければ 1 行。§88.2）
    private var mainCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            time(fonts.time)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(fonts.mainTitle)
                    .lineLimit(1)
                if let mainDetail {
                    Text(mainDetail)
                        .font(fonts.mainDetail)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, HomeLayoutMetrics.mainCardHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HomeLayoutMetrics.mainCardRadius)
                .fill(HomeLayoutMetrics.mainCardFill)
        }
        .padding(.vertical, HomeLayoutMetrics.mainCardInset)
    }

    /// 時刻の欄（文字を大きくしたときは広がる）
    private func time(_ font: Font) -> some View {
        Text(timeText)
            .font(font)
            .fixedSize()
            .frame(minWidth: HomeLayoutMetrics.timeColumnWidth, alignment: .leading)
    }

    private var accessibilityText: String {
        switch item.kind {
        case .departure:
            return "\(timeText) 出発、\(transport)、\(title)"
        case .inProgress:
            return ["進行中", title, place, endText].compactMap { $0 }.joined(separator: "、")
        default:
            return ["\(timeText)", title, place].compactMap { $0 }.joined(separator: "、")
        }
    }
}

/// 点どうしをつなぐ縦の線と、同じ予定の出発の点と予定開始の点を結ぶ線（Q81・Q83）
struct HomeRailLines: View {
    let dots: [HomeRailDot: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            let rects = dots.mapValues { proxy[$0] }
            ZStack(alignment: .topLeading) {
                if let base = HomeRailGeometry.base(rects) {
                    Self.path(base)
                        .stroke(Theme.Colors.separator, lineWidth: HomeLayoutMetrics.railLineWidth)
                }
                ForEach(HomeRailGeometry.pairs(rects)) { pair in
                    Self.path(pair)
                        .stroke(EventPalette.color(for: pair.color ?? .orange),
                                style: StrokeStyle(lineWidth: HomeLayoutMetrics.pairLineWidth, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func path(_ segment: HomeRailGeometry.Segment) -> Path {
        var path = Path()
        path.move(to: segment.top)
        path.addLine(to: segment.bottom)
        return path
    }
}
