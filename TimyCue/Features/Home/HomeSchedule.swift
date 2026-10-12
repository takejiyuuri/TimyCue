import Foundation

/// ホームに出す予定の決まり（v1.1「ホーム」・§13・2026-10-12「ホームの切り替え」）。画面に依らない計算だけを置く
enum HomeSchedule {
    /// ホームの主表示の予定：これから始まる、いちばん近い時間指定の予定を 1 件だけ（v1.1）。
    /// 前の予定の案内が終わっていれば次の予定を出し、前の予定を主表示に残さない（2026-10-12）。終日の予定は出発の対象にしない（§13）
    static func nextEvent(in events: [CalendarEvent], now: Date, calendar: Calendar = .timyCue) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && startDate(of: $0, calendar: calendar) > now }
            .min { startDate(of: $0, calendar: calendar) < startDate(of: $1, calendar: calendar) }
    }

    /// 今日はこれから時間指定の予定がなく、終日の予定だけがあるか（§13：「今日は時間指定の予定はありません」）
    static func hasOnlyAllDayToday(in events: [CalendarEvent], now: Date, calendar: Calendar = .timyCue) -> Bool {
        let today = CalendarDay(now, calendar: calendar)
        let todays = events.filter { $0.day == today }
        return todays.contains(where: \.isAllDay)
            && !todays.contains { !$0.isAllDay && startDate(of: $0, calendar: calendar) > now }
    }

    static func startDate(of event: CalendarEvent, calendar: Calendar = .timyCue) -> Date {
        event.day.date(atMinute: event.isAllDay ? 0 : event.startMinute, calendar: calendar)
    }

    /// 開始までの残り。「あと45分」「あと2時間5分」。1 日以上先は日付と時刻（出発時刻の計算は第 5 段階）
    static func countdownText(from now: Date, to start: Date) -> String {
        let minutes = max(0, Int(start.timeIntervalSince(now) / 60))
        if minutes < 60 { return "開始まであと\(minutes)分" }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "開始まであと\(hours)時間" : "開始まであと\(hours)時間\(rest)分"
        }
        return ""
    }
}
