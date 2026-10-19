import SwiftUI

/// Home の上に出す吹き出し（予定詳細・「終わった予定」の一覧）。押した行の近くに、行を隠さないように置く
/// （置き場所の決まりは月カレンダー・1 日タイムラインと同じ PopoverPlacement）。吹き出しの外を押すと閉じる（Q29）。
/// Home の中で行を広げないので、Home は縦にスクロールしない（Q84）
struct HomeBubbleLayer: View {
    let anchors: [String: Anchor<CGRect>]
    let home: HomeStore
    let finishedEvents: [CalendarEvent]
    /// 予定詳細の「編集」（3 分割画面を開く。Q30）
    let onEdit: (CalendarEvent) -> Void
    @Environment(CalendarStore.self) private var store
    @State private var measuredHeight: CGFloat? = nil

    init(anchors: [String: Anchor<CGRect>], home: HomeStore, finishedEvents: [CalendarEvent],
         onEdit: @escaping (CalendarEvent) -> Void) {
        self.anchors = anchors
        self.home = home
        self.finishedEvents = finishedEvents
        self.onEdit = onEdit
    }

    var body: some View {
        GeometryReader { proxy in
            if let anchorID = home.bubbleAnchorID, let anchor = anchors[anchorID] {
                let width = min(CalendarMetrics.popoverMaxWidth, proxy.size.width * CalendarMetrics.popoverWidthRatio)
                let frame = PopoverPlacement.frames(
                    container: proxy.size,
                    anchors: [proxy[anchor]],
                    sizes: [CGSize(width: width, height: measuredHeight ?? HomeLayoutMetrics.estimatedBubbleHeight)],
                    gap: CalendarMetrics.popoverGap,
                    margin: CalendarMetrics.popoverMargin)[0]
                ZStack(alignment: .topLeading) {
                    // 吹き出しの外を押したら閉じる
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { home.closeBubble() }
                    bubbleContent
                        .popoverBubble()
                        .frame(width: width)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: HomeBubbleHeightKey.self, value: geometry.size.height)
                            }
                        }
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .onPreferenceChange(HomeBubbleHeightKey.self) { height in
            measuredHeight = height
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch home.bubble {
        case .detail(let eventID, _)?:
            if let event = store.event(id: eventID) {
                detail(event)
            }
        case .finished(let selected)?:
            if let selected, let event = store.event(id: selected) {
                // 一覧から開いた予定詳細。中をもう一度押すと一覧へ戻る（Q29）
                detail(event)
                    .contentShape(Rectangle())
                    .onTapGesture { home.backToFinishedList() }
            } else {
                finishedList
            }
        case nil:
            EmptyView()
        }
    }

    private func detail(_ event: CalendarEvent) -> some View {
        EventDetailCard(event: event, metadata: store.metadata(for: event.id), isViewOnly: store.isViewOnly(event)) {
            onEdit(event)
        }
    }

    /// 「終わった予定」の一覧（時刻・予定名）。押すと同じ吹き出しの中で予定詳細に切り替える（Q28(a)）
    private var finishedList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("終わった予定")
                .font(CalendarMetrics.popoverTitleFont)
                .foregroundStyle(Theme.Colors.textPrimary)
            if finishedEvents.count > HomeLayoutMetrics.finishedListMaxRows {
                // 吹き出しの中だけスクロールする（Home そのものはスクロールしない）
                ScrollView {
                    finishedRows
                }
                .frame(height: HomeLayoutMetrics.finishedListHeight)
            } else {
                finishedRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var finishedRows: some View {
        VStack(alignment: .leading, spacing: CalendarMetrics.popoverRowSpacing) {
            ForEach(finishedEvents) { event in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Circle()
                        .fill(EventPalette.color(for: store.color(for: event)))
                        .frame(width: 8, height: 8)
                    Text(CalendarStore.timeText(for: event))
                        .font(CalendarMetrics.popoverTimeFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: CalendarMetrics.popoverTimeWidth, alignment: .leading)
                    Text(event.displayTitle)
                        .font(CalendarMetrics.popoverPrimaryFont)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { home.showFinishedDetail(event.id) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

private struct HomeBubbleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}
