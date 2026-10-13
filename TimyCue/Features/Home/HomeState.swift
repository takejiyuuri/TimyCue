import Foundation

/// ホームの主状態。「今、次に何をすべきか」を、いつも 1 つだけ出す（複数の状態をカードで並べない。追加仕様書 §45）。
/// 画面に依らない判定だけを置く。通知・Live Activity も、同じ判定（resolve）を使えるようにする
enum HomeState: Equatable {
    /// 1. 予定なし（これから時間指定の予定がない）。今日は終日の予定だけのときは onlyAllDayToday（spec §13）
    case noEvents(onlyAllDayToday: Bool)
    /// 2. 次の行動時刻（場所ありは出発、場所なしは開始）まで 60 分より前：静かな次の予定の表示（追加仕様書 §5.2）
    case upcoming(CalendarEvent)
    /// 3. 出発 60 分以内：時計で出発までの残り（spec §6・追加仕様書 §44）
    case departureCountdown(CalendarEvent, departure: Date)
    /// 4. 場所なしの予定の開始 60 分以内：時計で開始までの残り（追加仕様書 §36.2・§44.11）。
    /// 開発中は、出発時刻の計算をまだ作っていない場所ありの予定もここ（追加仕様書 §44.11）
    case startCountdown(CalendarEvent)
    /// 5. 出発時刻（過ぎて 3 分未満）：「出発してください」（spec §6・追加仕様書 §8.7）
    case departureTime(CalendarEvent, departure: Date)
    /// 6. 出発時刻超過（3 分以上）：「出発時刻を○分過ぎています」（spec Q46・追加仕様書 §8.7）
    case departureOverdue(CalendarEvent, departure: Date, minutesLate: Int)
    /// 7. 移動中（移動開始の判定ができてから。追加仕様書 §15。まだ判定しない）
    case moving(CalendarEvent)
    /// 8. 到着済み・開始待ち（意味のある到着の判定ができてから。追加仕様書 §18。まだ判定しない）
    case arrived(CalendarEvent)
    /// 9. 予定開始時刻：「予定時刻になりました」を約 3 分（追加仕様書 §5.1）
    case eventStarted(CalendarEvent)
    /// 10. 競合などの例外（両方へ行けない予定 §6 などができてから。まだ判定しない）
    case conflict(CalendarEvent)
    /// 場所はあるが、出発時刻を計算できない（製品で計算に失敗したとき）。黙って開始のカウントダウンへ切り替えない（追加仕様書 §44.11）。
    /// どう見せるかは未決（追加仕様書 §45.3）
    case departureUnavailable(CalendarEvent)

    /// 出発時刻を過ぎてから「出発時刻を○分過ぎています」に切り替えるまでの分（spec Q46：3 分以上）
    static let overdueAfterMinutes = 3

    /// 主状態を決める。estimate は予定ごとの推奨出発時刻の見込み（第 5 段階ができるまでは DepartureEstimate.development）
    static func resolve(events: [CalendarEvent],
                        now: Date,
                        calendar: Calendar = .timyCue,
                        estimate: (CalendarEvent) -> DepartureEstimate) -> HomeState {
        let departure: (CalendarEvent) -> Date? = { event in
            if case .available(let date) = estimate(event) { return date }
            return nil
        }
        // 予定開始から約 3 分の「予定時刻になりました」と、次の予定の出発時刻の優先は、前からの決まりのまま（追加仕様書 §5.1・§5.4）
        guard let main = HomeSchedule.main(in: events, now: now, calendar: calendar, departure: departure) else {
            return .noEvents(onlyAllDayToday: HomeSchedule.hasOnlyAllDayToday(in: events, now: now, calendar: calendar))
        }
        let event: CalendarEvent
        switch main {
        case .started(let started):
            return .eventStarted(started)
        case .upcoming(let upcoming):
            event = upcoming
        }
        switch estimate(event) {
        case .notNeeded, .notImplemented:
            // 場所なしの予定は開始が基準。開発中は、場所ありの予定も開始で仮に動かす
            let start = HomeSchedule.startDate(of: event, calendar: calendar)
            return HomeClockMath.face(now: now, target: start, calendar: calendar) == nil ? .upcoming(event) : .startCountdown(event)
        case .unavailable:
            return .departureUnavailable(event)
        case .available(let leaveAt):
            let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            if minuteStart < leaveAt {
                // 時計は出発の 60 分前から（それより前は静かな表示。追加仕様書 §44.12）
                return HomeClockMath.face(now: now, target: leaveAt, calendar: calendar) == nil
                    ? .upcoming(event)
                    : .departureCountdown(event, departure: leaveAt)
            }
            // 出発時刻を過ぎたら、時計は終えて「出発してください」。3 分以上は「出発時刻を○分過ぎています」（予定開始までは続ける）
            let late = Int(minuteStart.timeIntervalSince(leaveAt) / 60)
            return late < overdueAfterMinutes
                ? .departureTime(event, departure: leaveAt)
                : .departureOverdue(event, departure: leaveAt, minutesLate: late)
        }
    }

    /// 主状態の予定（予定なしのときは nil）
    var event: CalendarEvent? {
        switch self {
        case .noEvents:
            nil
        case .upcoming(let event), .startCountdown(let event), .moving(let event), .arrived(let event),
             .eventStarted(let event), .conflict(let event), .departureUnavailable(let event),
             .departureCountdown(let event, _), .departureTime(let event, _), .departureOverdue(let event, _, _):
            event
        }
    }

    /// 時計で数える先（時計を出す状態のときだけ）。場所ありは出発、場所なしは開始（追加仕様書 §44.11）
    func clockTarget(calendar: Calendar = .timyCue) -> HomeSchedule.ClockTarget? {
        switch self {
        case .startCountdown(let event):
            HomeSchedule.ClockTarget(date: HomeSchedule.startDate(of: event, calendar: calendar), isDeparture: false)
        case .departureCountdown(_, let departure):
            HomeSchedule.ClockTarget(date: departure, isDeparture: true)
        default:
            nil
        }
    }

    /// 予定の上に出す大きな知らせ（出発時刻・超過・予定開始）。ほかの状態では nil
    var headline: String? {
        switch self {
        case .departureTime: "出発してください"
        case .departureOverdue(_, _, let minutesLate): "出発時刻を\(minutesLate)分過ぎています"
        case .eventStarted: "予定時刻になりました"
        default: nil
        }
    }
}
