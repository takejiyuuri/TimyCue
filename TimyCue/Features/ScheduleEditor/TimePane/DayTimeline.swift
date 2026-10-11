import SwiftUI

/// 0〜24 時の目盛りと、予定ブロックを実際の時刻の位置に置いた時間軸（仕様 §20・§22）
struct DayTimeline: View {
    let day: CalendarDay
    let events: [CalendarEvent]
    let drafts: [CalendarEvent]

    static func hourID(_ hour: Int) -> String { "hour-\(hour)" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            hourGrid
            ForEach(events) { event in
                EventBlock(event: event, style: .saved)
                    .frame(height: blockHeight(for: event))
                    .padding(.leading, EditorLayout.hourLabelWidth + 2)
                    .padding(.trailing, 4)
                    .offset(y: yPosition(for: event.startMinute))
            }
            ForEach(drafts) { draft in
                EventBlock(event: draft, style: .draft)
                    .frame(height: blockHeight(for: draft))
                    .padding(.leading, EditorLayout.hourLabelWidth + 2)
                    .padding(.trailing, 4)
                    .offset(y: yPosition(for: draft.startMinute))
            }
        }
        .padding(.vertical, 6)
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 2) {
                    Text("\(hour)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: EditorLayout.hourLabelWidth, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(height: 1)
                }
                .frame(height: EditorLayout.hourHeight, alignment: .top)
                .id(Self.hourID(hour))
            }
        }
    }

    private func yPosition(for minute: MinuteOfDay) -> CGFloat {
        CGFloat(minute) / 60 * EditorLayout.hourHeight
    }

    private func blockHeight(for event: CalendarEvent) -> CGFloat {
        guard let duration = event.content.durationMinutes else { return EditorLayout.untimedBlockHeight }
        return max(EditorLayout.untimedBlockHeight, CGFloat(duration) / 60 * EditorLayout.hourHeight)
    }
}

/// 予定ブロック。保存前の仮予定は、淡く点線で区別する（仕様 §22。最終形は未決 §53）
struct EventBlock: View {
    enum Style {
        case saved
        case draft
    }

    let event: CalendarEvent
    let style: Style

    var body: some View {
        let color = EventPalette.color(for: event.content.color)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(color.opacity(style == .draft ? 0.35 : 0.85)))
        .overlay {
            if style == .draft {
                shape.stroke(color, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
        }
    }

    private var title: String {
        let label = event.content.primaryLabel ?? "新規予定"
        return style == .draft ? "\(TimeText.hourMinute(event.startMinute)) \(label)" : label
    }
}
