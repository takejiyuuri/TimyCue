import Foundation

/// 時刻を持たない「日付」。複数日選択や日付タブのキーに使う。
/// Date のままだとタイムゾーンや時刻の違いで同じ日が別物になるため、年月日だけで比べる。
struct CalendarDay: Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// その日の 0:00 から `minuteOfDay` 分後の日時
    func date(atMinute minuteOfDay: Int = 0, calendar: Calendar = .current) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        let midnight = calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
        return calendar.date(byAdding: .minute, value: minuteOfDay, to: midnight) ?? midnight
    }

    func adding(days: Int, calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? date(calendar: calendar),
                    calendar: calendar)
    }

    /// 日付タブなどに出す短い表記（例：10/12）
    var shortLabel: String { "\(month)/\(day)" }
}

/// 0:00 からの分。14:17 なら 857。
typealias MinuteOfDay = Int

extension MinuteOfDay {
    static let minutesPerDay = 24 * 60
}

enum TimeText {
    /// 857 → "14:17"
    static func hourMinute(_ minute: MinuteOfDay) -> String {
        let clamped = max(0, minute)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
