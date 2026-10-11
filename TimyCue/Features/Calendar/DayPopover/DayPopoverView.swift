import SwiftUI

/// 吹き出しを開いている日のセルの近くに、吹き出しを並べる層（仕様 §22・§23）
struct DayPopoverLayer: View {
    let anchors: [CalendarDay: Anchor<CGRect>]
    @Environment(CalendarStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            ForEach(store.openDays, id: \.self) { day in
                if let anchor = anchors[day] {
                    let cell = proxy[anchor]
                    let width = min(CalendarMetrics.popoverMaxWidth, proxy.size.width * CalendarMetrics.popoverWidthRatio)
                    let x = min(max(cell.midX - width / 2, CalendarMetrics.popoverMargin),
                                proxy.size.width - width - CalendarMetrics.popoverMargin)
                    // 下に入りきるなら下、入りきらなければ上に出す
                    let below = cell.maxY + CalendarMetrics.popoverGap + CalendarMetrics.popoverMaxHeight <= proxy.size.height
                    DayPopoverView(day: day, rows: store.popoverRows(on: day))
                        .frame(width: width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .topLeading : .bottomLeading)
                        .offset(x: x,
                                y: below
                                    ? cell.maxY + CalendarMetrics.popoverGap
                                    : cell.minY - CalendarMetrics.popoverGap - proxy.size.height)
                }
            }
        }
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
                .frame(width: 40, alignment: .leading)
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
