import Foundation

/// 年と月。月カレンダーで縦につなげて並べる 1 か月分（仕様 §19）。
struct CalendarMonth: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    var id: Int { year * 12 + (month - 1) }

    static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        lhs.id < rhs.id
    }

    /// 月の見出し（例：2026年10月）。書き方は仮
    var title: String { "\(year)年\(month)月" }

    func adding(months: Int) -> CalendarMonth {
        let index = id + months
        let year = Int((Double(index) / 12).rounded(.down))
        return CalendarMonth(year: year, month: index - year * 12 + 1)
    }

    var firstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1) }

    func numberOfDays(calendar: Calendar = .timyCue) -> Int {
        calendar.range(of: .day, in: .month, for: firstDay.date(calendar: calendar))?.count ?? 30
    }

    /// 月曜始まりの週ごとの日。前後の月にあたる枠は nil
    func weeks(calendar: Calendar = .timyCue) -> [[CalendarDay?]] {
        let leading = firstDay.weekdayIndexFromMonday(calendar: calendar)
        var slots: [CalendarDay?] = Array(repeating: nil, count: leading)
        slots += (1...numberOfDays(calendar: calendar)).map { CalendarDay(year: year, month: month, day: $0) }
        let trailing = (7 - slots.count % 7) % 7
        slots += Array(repeating: nil, count: trailing)
        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<($0 + 7)]) }
    }

    /// 基準の月の前後を並べる（仕様 §19 の縦の連続スクロール）
    static func range(around center: CalendarMonth, before: Int, after: Int) -> [CalendarMonth] {
        (-before...after).map { center.adding(months: $0) }
    }
}
