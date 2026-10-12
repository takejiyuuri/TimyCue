import Foundation

/// ホームに出す予定の決まり（v1.1「ホーム」・§13・2026-10-12「ホームの切り替え」）。画面に依らない計算だけを置く
enum HomeSchedule {
    /// 予定の開始時刻に「予定時刻になりました」を出しておく、いちばん長い時間（追加仕様書 §5.1：通常 3 分。最大 3 分）
    static let startedNoticeDuration: TimeInterval = 3 * 60
    /// これより先の予定は、大きな「あと○分」にせず静かに出す（追加仕様書 §5.2：出発まで 60 分以上）
    static let quietMinutes = 60

    /// ホームの主表示
    enum Main: Equatable {
        /// 開始時刻になった予定（約 3 分だけ）
        case started(CalendarEvent)
        /// これからの予定
        case upcoming(CalendarEvent)

        var event: CalendarEvent {
            switch self {
            case .started(let event), .upcoming(let event): event
            }
        }
    }

    /// ホームの主表示を決める。開始時刻から最大 3 分は「予定時刻になりました」、そのあとは主表示から外して次の予定へ（§5.1）。
    /// その途中でも、次の予定の出発時刻になったら次の案内を優先する（§5.1・§5.4）。
    /// departure は予定の出発時刻（移動時間の計算は第 5 段階。それまでは nil で、途中で切り替えない）
    static func main(in events: [CalendarEvent],
                     now: Date,
                     calendar: Calendar = .timyCue,
                     departure: (CalendarEvent) -> Date? = { _ in nil }) -> Main? {
        let next = nextEvent(in: events, now: now, calendar: calendar)
        let started = events
            .filter { event in
                guard !event.isAllDay else { return false }
                let start = startDate(of: event, calendar: calendar)
                return start <= now && now.timeIntervalSince(start) < startedNoticeDuration
            }
            .max { startDate(of: $0, calendar: calendar) < startDate(of: $1, calendar: calendar) }
        if let started {
            if let next, let leaveAt = departure(next), leaveAt <= now { return .upcoming(next) }
            return .started(started)
        }
        return next.map(Main.upcoming)
    }

    /// まだ先なので静かに出すか（§5.2）。
    /// 暫定：出発時刻の計算（第 5 段階）までの実装途中の代用として、開始時刻で見る。仕様ではない。第 5 段階で推奨出発時刻に置き換える
    static func isQuiet(now: Date, start: Date) -> Bool {
        start.timeIntervalSince(now) >= TimeInterval(quietMinutes * 60)
    }
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
