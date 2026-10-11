import SwiftUI

/// 吹き出しを開いている日のセルの近くに、吹き出しを並べる層（仕様 §22・§23）。
/// 2 つの吹き出しは重ならないように置く（Q11。置き場所の決まりは PopoverPlacement）
struct DayPopoverLayer: View {
    let anchors: [CalendarDay: Anchor<CGRect>]
    @Environment(CalendarStore.self) private var store
    /// 実際に描いた吹き出しの高さ。描く前は行の数から見積もる
    @State private var measuredHeights: [CalendarDay: CGFloat] = [:]

    var body: some View {
        GeometryReader { proxy in
            let width = min(CalendarMetrics.popoverMaxWidth, proxy.size.width * CalendarMetrics.popoverWidthRatio)
            let days = store.openDays.filter { anchors[$0] != nil }
            let frames = PopoverPlacement.frames(
                container: proxy.size,
                anchors: days.compactMap { day in anchors[day].map { proxy[$0] } },
                sizes: days.map { day in
                    CGSize(width: width,
                           height: measuredHeights[day] ?? Self.estimatedHeight(rowCount: store.popoverRows(on: day).count))
                },
                gap: CalendarMetrics.popoverGap,
                margin: CalendarMetrics.popoverMargin)

            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let frame = frames[index]
                DayPopoverView(day: day, rows: store.popoverRows(on: day))
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: PopoverHeightKey.self, value: [day: geometry.size.height])
                        }
                    }
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .onPreferenceChange(PopoverHeightKey.self) { heights in
            measuredHeights = heights
        }
    }

    /// 描く前の高さの見積もり（見出し＋行。6 行以上は中でスクロールする高さ）
    static func estimatedHeight(rowCount: Int) -> CGFloat {
        let chrome: CGFloat = 24 + 20 + 6
        switch rowCount {
        case 0:
            return chrome + 16
        case 1...CalendarMetrics.popoverMaxVisibleRows:
            return chrome + CGFloat(rowCount) * 32 + CGFloat(rowCount - 1) * CalendarMetrics.popoverRowSpacing
        default:
            return chrome + CalendarMetrics.popoverListHeight
        }
    }
}

/// 吹き出しの実際の高さを層へ渡す
struct PopoverHeightKey: PreferenceKey {
    static let defaultValue: [CalendarDay: CGFloat] = [:]

    static func reduce(value: inout [CalendarDay: CGFloat], nextValue: () -> [CalendarDay: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 日付吹き出し（仕様 §22）。予定は開始時刻順。予定名が主、場所が補助。多いときは中で縦スクロール
struct DayPopoverView: View {
    let day: CalendarDay
    let rows: [DayPopoverRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 押すと 1 日タイムラインへ移る（仕様 §25）。タイムラインは次の段階で作る
            Text("\(day.month)月\(day.day)日（\(day.weekdaySymbol())）")
                .font(CalendarMetrics.popoverTitleFont)
                .foregroundStyle(Theme.Colors.textPrimary)
            if rows.isEmpty {
                Text("予定はありません")
                    .font(CalendarMetrics.popoverSecondaryFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if rows.count <= CalendarMetrics.popoverMaxVisibleRows {
                rowList
            } else {
                ScrollView {
                    rowList
                }
                .frame(height: CalendarMetrics.popoverListHeight)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .fill(Theme.Colors.surface)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    private var rowList: some View {
        VStack(alignment: .leading, spacing: CalendarMetrics.popoverRowSpacing) {
            ForEach(rows) { row in
                DayPopoverRowView(row: row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DayPopoverRowView: View {
    let row: DayPopoverRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(EventPalette.color(for: row.color))
                .frame(width: 8, height: 8)
            Text(row.timeText)
                .font(CalendarMetrics.popoverTimeFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: CalendarMetrics.popoverTimeWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.primary)
                    .font(CalendarMetrics.popoverPrimaryFont)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if let secondary = row.secondary {
                    Text(secondary)
                        .font(CalendarMetrics.popoverSecondaryFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
