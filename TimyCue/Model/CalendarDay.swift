import Foundation

extension Calendar {
    /// 年月日の計算に使う暦。端末の設定が和暦などでも、西暦・端末のタイムゾーンで数える
    static var timyCue: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }
}

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

    init(_ date: Date, calendar: Calendar = .timyCue) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// その日の 0:00 から `minuteOfDay` 分後の日時
    func date(atMinute minuteOfDay: Int = 0, calendar: Calendar = .timyCue) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        let midnight = calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
        return calendar.date(byAdding: .minute, value: minuteOfDay, to: midnight) ?? midnight
    }

    func adding(days: Int, calendar: Calendar = .timyCue) -> CalendarDay {
        CalendarDay(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? date(calendar: calendar),
                    calendar: calendar)
    }

    /// この日から other まで何日あるか（other が前なら負）
    func days(to other: CalendarDay, calendar: Calendar = .timyCue) -> Int {
        calendar.dateComponents([.day], from: date(calendar: calendar), to: other.date(calendar: calendar)).day ?? 0
    }

    /// 日付タブなどに出す短い表記（例：10/12）
    var shortLabel: String { "\(month)/\(day)" }

    /// 月曜を 0、日曜を 6 とした曜日の番号（月カレンダーは月曜始まり。仕様 §19）
    func weekdayIndexFromMonday(calendar: Calendar = .timyCue) -> Int {
        let weekday = calendar.component(.weekday, from: date(calendar: calendar))  // 日曜 = 1 … 土曜 = 7
        return (weekday + 5) % 7
    }

    /// 曜日の 1 文字（月〜日）
    func weekdaySymbol(calendar: Calendar = .timyCue) -> String {
        Weekday.symbols[weekdayIndexFromMonday(calendar: calendar)]
    }
}

enum Weekday {
    /// 月曜始まりの曜日の並び（仕様 §19）
    static let symbols = ["月", "火", "水", "木", "金", "土", "日"]
}

extension CalendarDay: Identifiable {
    var id: Self { self }
}

/// 0:00 からの分。14:17 なら 857。
typealias MinuteOfDay = Int

extension MinuteOfDay {
    static let minutesPerDay = 24 * 60
}

enum Clock {
    /// その時刻の 0:00 からの分（14:17 なら 857）
    static func minuteOfDay(_ date: Date, calendar: Calendar = .timyCue) -> MinuteOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

enum TimeText {
    /// 857 → "14:17"
    static func hourMinute(_ minute: MinuteOfDay) -> String {
        let clamped = max(0, minute)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
