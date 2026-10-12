import Foundation

/// 年と月（仕様 §19・Q18〜Q20 の月表示・年表示に使う）
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

    /// 月表示列に出す文字。月だけ（Q20：例 10月）
    var monthLabel: String { "\(month)月" }

    /// 画面上部の固定領域に出す年（Q20：例 2026年）
    var yearLabel: String { "\(year)年" }

    func adding(months: Int) -> CalendarMonth {
        let index = id + months
        let year = Int((Double(index) / 12).rounded(.down))
        return CalendarMonth(year: year, month: index - year * 12 + 1)
    }

    var firstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1) }
}

/// 月曜から日曜までの 1 週間。通常の月カレンダーは、月ごとの箱にせず週を途切れず縦に並べる（v1.1・§19）
struct CalendarWeek: Hashable, Comparable, Identifiable {
    /// その週の月曜
    let start: CalendarDay

    init(containing day: CalendarDay) {
        start = day.adding(days: -day.weekdayIndexFromMonday())
    }

    var id: CalendarDay { start }

    static func < (lhs: CalendarWeek, rhs: CalendarWeek) -> Bool {
        lhs.start < rhs.start
    }

    /// 月曜〜日曜の 7 日。月の境目もそのまま続ける（例：28 29 30 31 1 2 3）
    var days: [CalendarDay] {
        (0..<7).map { start.adding(days: $0) }
    }

    /// その週の日曜
    var lastDay: CalendarDay { start.adding(days: 6) }

    func adding(weeks: Int) -> CalendarWeek {
        CalendarWeek(containing: start.adding(days: weeks * 7))
    }

    /// この週から other まで何週あるか（other が前なら負）
    func weeks(to other: CalendarWeek) -> Int {
        start.days(to: other.start) / 7
    }

    /// この週に 1 日がある月。月表示列のこの週の高さに出す（Q18）
    var monthStartingInWeek: CalendarMonth? {
        days.first { $0.day == 1 }.map(CalendarMonth.init)
    }

    /// この週が一番上にあるときに固定表示する月と年（Q19・Q20）。
    /// 次の月の 1 日を含む週が一番上に来たら次の月になるよう、週の最後の日（日曜）の月を使う
    var stickyMonth: CalendarMonth { CalendarMonth(lastDay) }
}
