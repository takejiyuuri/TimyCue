import SwiftUI

/// 吹き出しを開いている日のセルの位置を、吹き出しの層へ渡す
struct OpenDayAnchorKey: PreferenceKey {
    static let defaultValue: [CalendarDay: Anchor<CGRect>] = [:]

    static func reduce(value: inout [CalendarDay: Anchor<CGRect>], nextValue: () -> [CalendarDay: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 月カレンダーの 1 日分のセル（仕様 §20・§21）
struct DayCellView: View {
    let day: CalendarDay
    let summary: DayCellSummary
    let isToday: Bool
    let isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            dayNumber
            DayCellEventsView(summary: summary)
                .padding(.horizontal, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: CalendarMetrics.cellHeight, maxHeight: CalendarMetrics.cellHeight, alignment: .top)
        .clipped()
        .overlay {
            if isOpen {
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .strokeBorder(Theme.Colors.accent, lineWidth: CalendarMetrics.selectionLineWidth)
            }
        }
        .contentShape(Rectangle())
        .anchorPreference(key: OpenDayAnchorKey.self, value: .bounds) { anchor in
            isOpen ? [day: anchor] : [:]
        }
    }

    /// 日付の数字。今日は後ろに淡いオレンジの丸（仕様 §20）
    private var dayNumber: some View {
        Text("\(day.day)")
            .font(CalendarMetrics.dayNumberFont)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: CalendarMetrics.todayCircleSize, height: CalendarMetrics.todayCircleSize)
            .background {
                if isToday {
                    Circle().fill(Theme.Colors.todayCircle)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}

/// セルの中の予定（仕様 §21）
struct DayCellEventsView: View {
    let summary: DayCellSummary

    var body: some View {
        switch summary {
        case .empty:
            EmptyView()
        case .titles(let marks):
            VStack(alignment: .leading, spacing: CalendarMetrics.eventLineSpacing) {
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    HStack(spacing: 2) {
                        Circle()
                            .fill(EventPalette.color(for: mark.color))
                            .frame(width: CalendarMetrics.eventTitleDotSize, height: CalendarMetrics.eventTitleDotSize)
                        Text(mark.title)
                            .font(CalendarMetrics.eventTitleFont)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .dots:
            VStack(alignment: .leading, spacing: CalendarMetrics.summaryDotSpacing) {
                ForEach(Array(summary.dotRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: CalendarMetrics.summaryDotSpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, slot in
                            DotSlotView(slot: slot)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DotSlotView: View {
    let slot: DotSlot

    var body: some View {
        switch slot {
        case .dot(let color):
            Circle()
                .fill(EventPalette.color(for: color))
                .frame(width: CalendarMetrics.summaryDotSize, height: CalendarMetrics.summaryDotSize)
        case .more(let count):
            Text("+\(count)")
                .font(CalendarMetrics.moreFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize()
                .frame(height: CalendarMetrics.summaryDotSize)
        }
    }
}
