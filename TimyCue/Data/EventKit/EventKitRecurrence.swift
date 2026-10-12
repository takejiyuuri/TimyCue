import EventKit
import Foundation

/// TimyCue の繰り返し（RepeatRule）と、Apple カレンダーの繰り返し（EKRecurrenceRule）の変換（Q37）。
/// 本来の繰り返しは EventKit を正本にするので、TimyCue は決まりを渡して受け取るだけ
enum EventKitRecurrence {
    /// 月曜を 0 とする曜日 → EventKit の曜日（日曜 = 1 … 土曜 = 7）
    static func ekWeekday(fromMondayIndex index: Int) -> EKWeekday? {
        EKWeekday(rawValue: (index + 1) % 7 + 1)
    }

    /// EventKit の曜日 → 月曜を 0 とする曜日
    static func mondayIndex(from weekday: EKWeekday) -> Int {
        (weekday.rawValue + 5) % 7
    }

    /// TimyCue の繰り返しから EventKit の繰り返しを作る。「なし」なら nil
    static func rule(from repeatRule: RepeatRule, calendar: Calendar = .timyCue) -> EKRecurrenceRule? {
        guard let frequency = repeatRule.frequency else { return nil }
        let ekFrequency: EKRecurrenceFrequency
        switch frequency {
        case .daily: ekFrequency = .daily
        case .weekly: ekFrequency = .weekly
        case .monthly: ekFrequency = .monthly
        case .yearly: ekFrequency = .yearly
        }
        let days: [EKRecurrenceDayOfWeek]? = frequency == .weekly && !repeatRule.weekdays.isEmpty
            ? repeatRule.weekdays.sorted().compactMap { ekWeekday(fromMondayIndex: $0) }.map { EKRecurrenceDayOfWeek($0) }
            : nil
        // 終わりの日はその日の終わりまで含める
        let end = repeatRule.endDay.map { day in
            EKRecurrenceEnd(end: day.adding(days: 1, calendar: calendar).date(calendar: calendar).addingTimeInterval(-1))
        }
        return EKRecurrenceRule(recurrenceWith: ekFrequency,
                                interval: repeatRule.interval,
                                daysOfTheWeek: days,
                                daysOfTheMonth: nil,
                                monthsOfTheYear: nil,
                                weeksOfTheYear: nil,
                                daysOfTheYear: nil,
                                setPositions: nil,
                                end: end)
    }

    /// EventKit の繰り返しから TimyCue の繰り返しを作る。回数で終わる繰り返しは、終わりの日を持たない形で読む
    static func repeatRule(from rule: EKRecurrenceRule?, calendar: Calendar = .timyCue) -> RepeatRule {
        guard let rule else { return .none }
        let frequency: RepeatFrequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return .none
        }
        let weekdays = Set((rule.daysOfTheWeek ?? []).map { mondayIndex(from: $0.dayOfTheWeek) })
        let endDay = rule.recurrenceEnd?.endDate.map { CalendarDay($0, calendar: calendar) }
        return RepeatRule(frequency: frequency, interval: rule.interval, weekdays: weekdays, endDay: endDay)
    }
}
