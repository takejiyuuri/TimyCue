import SwiftUI

/// 下：登録する日を選ぶカレンダー（仕様 §17）。月を縦に並べてスクロールする。
/// 日付セルの予定表示（色点・件数。仕様 §13）は次の段階で入れる。
struct CalendarPane: View {
    private let today = CalendarDay(Date())

    /// 今月の前後に並べる月数。ずっと続くスクロールは次の段階で入れる（大量表示への内部の安全策を兼ねる）
    private let monthsBefore = 1
    private let monthsAfter = 11

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Theme.Spacing.m) {
                    ForEach(months, id: \.self) { month in
                        MonthGrid(month: month, today: today)
                            .id(month)
                    }
                }
                .padding(Theme.Spacing.s)
            }
            .onAppear {
                proxy.scrollTo(MonthKey(today), anchor: .top)
            }
        }
        .paneBackground()
    }

    private var months: [MonthKey] {
        let base = MonthKey(today)
        return (-monthsBefore...monthsAfter).map { base.adding(months: $0) }
    }
}

/// 年月
struct MonthKey: Hashable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    func adding(months: Int) -> MonthKey {
        let index = year * 12 + (month - 1) + months
        return MonthKey(year: index / 12, month: index % 12 + 1)
    }

    var firstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1) }

    var title: String { "\(year)年\(month)月" }

    /// 日曜始まりの 7 列に並べたときのセル（月の前の空きは nil）
    func cells(calendar: Calendar = .current) -> [CalendarDay?] {
        let first = firstDay.date(calendar: calendar)
        let leading = calendar.component(.weekday, from: first) - 1
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        return Array(repeating: nil, count: leading)
            + (1...count).map { CalendarDay(year: year, month: month, day: $0) }
    }
}

/// 1 か月分の日付の並び
private struct MonthGrid: View {
    @Environment(ScheduleEditorStore.self) private var store
    let month: MonthKey
    let today: CalendarDay

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(month.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.leading, 2)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(DayText.weekdayHeaders, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                ForEach(Array(month.cells().enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(day: day,
                                isToday: day == today,
                                isSelected: store.selectedDays.contains(day),
                                isDisplayed: store.displayedDay == day)
                            .onTapGesture { store.browse(to: day) }
                    } else {
                        Color.clear.frame(height: DayCell.height)
                    }
                }
            }
        }
    }
}

/// 日付セル。選択済み（複数）と、左上に表示中（1 日）を見分けられるようにする（仕様 §17）
private struct DayCell: View {
    static let height: CGFloat = 34

    let day: CalendarDay
    let isToday: Bool
    let isSelected: Bool
    let isDisplayed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        Text("\(day.day)")
            .font(.footnote.weight(isToday ? .bold : .regular).monospacedDigit())
            .foregroundStyle(isToday ? Theme.Colors.accent : Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background(shape.fill(isSelected ? Theme.Colors.accent.opacity(0.18) : Color.clear))
            .overlay {
                if isDisplayed {
                    shape.stroke(Theme.Colors.accent, lineWidth: 2)
                } else if isSelected {
                    shape.stroke(Theme.Colors.accent.opacity(0.5), lineWidth: 1)
                }
            }
            .contentShape(shape)
    }
}
