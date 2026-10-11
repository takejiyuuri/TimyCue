import Foundation

/// 日付の表示（例：10/12（月））
enum DayText {
    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    static func weekday(_ day: CalendarDay, calendar: Calendar = .current) -> String {
        let index = calendar.component(.weekday, from: day.date(calendar: calendar)) - 1
        return weekdays[(index % 7 + 7) % 7]
    }

    static func withWeekday(_ day: CalendarDay) -> String {
        "\(day.shortLabel)（\(weekday(day))）"
    }

    static let weekdayHeaders = weekdays
}
