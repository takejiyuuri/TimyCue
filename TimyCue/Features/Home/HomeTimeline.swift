import Foundation

/// 新しい Home（H2。spec §88.2・Q81〜Q84・Q87・Q91）の左のタイムラインに出すもの。画面に依らない計算だけを置く。
/// 見本の予定を前提にせず、実際の予定（Apple の予定と TimyCue のみの予定。場所あり・なし）・今の時刻・出発時刻の見込みから作る。
/// 時刻に比例させない時系列の一覧で、「いま」を基準に、推奨出発時刻と予定開始時刻を別々の点として並べる（Q81）
struct HomeTimeline: Equatable {
    /// 「いま」より下に並べる 1 行
    struct Item: Identifiable, Equatable {
        enum Kind: Equatable {
            /// これからの出発の点（推奨出発時刻が出ているときだけ。§88.2「出発の点は推奨出発時刻があるときだけ出す」）
            case departure
            /// 予定開始の点（場所なしの予定は、出発の点を持たずこれだけ。Q81）
            case start
            /// 進行中の予定（開始を過ぎ、終わりの前）。「いま」のすぐ下に終わりの時刻つきで出す（§88.2・Q83）。
            /// 終わりのない予定は、開始の知らせ（「予定時刻になりました」）のあいだだけ
            case inProgress(end: Date?)
            /// 日付の区切り（今日の予定が終わったあとの「明日」など。§88.2）
            case daySeparator(CalendarDay)
            /// 予定がないときの文（「予定はありません」「今日は時間指定の予定はありません」：§13）
            case message(String)
        }

        let id: String
        let kind: Kind
        /// その行の予定（区切り・文は nil）
        let event: CalendarEvent?
        /// 並べる時刻（出発の点は推奨出発時刻、予定は開始。区切りはその日の 0:00）
        let date: Date
        /// 主状態の予定の行か（いちばん強調する 1 件。§88.1）
        let isMain: Bool

        /// 出発の点か
        var isDeparture: Bool { kind == .departure }

        /// 予定そのものの行（開始の点・進行中）か。「ほか○件」の数え方に使う（出発の点は別に数えない：Q84）
        var isEventRow: Bool {
            switch kind {
            case .start, .inProgress: event != nil
            case .departure, .daySeparator, .message: false
            }
        }
    }

    /// 過ぎた出発の点（Q83・Q87）：今案内している予定の 1 件だけを「いま」の上に 1 行で残す
    struct PastDeparture: Equatable {
        let event: CalendarEvent
        let leaveAt: Date
    }

    /// 「いま」より上の左の列の並び（Q87：人型 →（過ぎた出発の点）→ いま）
    enum AboveNow: Hashable {
        case figure
        case pastDeparture
        case now
    }

    /// 予定がないときの文（今の Home と同じ言葉。§13）
    static let noEventsText = "予定はありません"
    static let onlyAllDayText = "今日は時間指定の予定はありません"

    let today: CalendarDay
    let now: Date
    /// 主状態の予定（いちばん強調する 1 件）
    let mainEventID: UUID?
    /// 日付の下に控えめに出す、今日の終日の予定と表示のみのカレンダーの予定（§88.2。時間軸に混ぜない）
    let allDayEvents: [CalendarEvent]
    /// 今日の終わった予定（「終わった予定 ○件」に畳む。Q84・Q91）
    let finishedEvents: [CalendarEvent]
    let pastDeparture: PastDeparture?
    /// 「いま」より下の行（時刻の順）
    let items: [Item]

    /// 主状態（HomeState）と同じ予定・時刻・出発時刻の見込みから作る。
    /// events は Home と出発時刻の計算に使う予定（表示のみのカレンダーの予定を除いたもの）。
    /// displayOnlyEvents は表示のみのカレンダー（祝日など）の予定で、日付の下に出すだけ（出発案内・編集の対象にしない）
    static func make(events: [CalendarEvent],
                     displayOnlyEvents: [CalendarEvent] = [],
                     state: HomeState,
                     now: Date,
                     calendar: Calendar = .timyCue,
                     estimate: (CalendarEvent) -> DepartureEstimate) -> HomeTimeline {
        let today = CalendarDay(now, calendar: calendar)
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let mainID = state.event?.id
        func start(_ event: CalendarEvent) -> Date { HomeSchedule.startDate(of: event, calendar: calendar) }
        func end(_ event: CalendarEvent) -> Date? {
            event.durationMinutes.map { start(event).addingTimeInterval(TimeInterval($0 * 60)) }
        }
        func inOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
            (start(lhs), lhs.displayTitle, lhs.id.uuidString) < (start(rhs), rhs.displayTitle, rhs.id.uuidString)
        }

        let timed = events.filter { !$0.isAllDay }
        // 開始の知らせ（約 3 分）のあいだの予定。終わりの時刻がなくても、そのあいだは進行中として「いま」のすぐ下に出す
        let startedMainID: UUID? = {
            if case .eventStarted(let event) = state { return event.id }
            return nil
        }()
        let inProgress = timed.filter { event in
            guard start(event) <= now else { return false }
            if let finish = end(event), now < finish { return true }
            return event.id == startedMainID
        }
        .sorted(by: inOrder)
        let inProgressIDs = Set(inProgress.map(\.id))
        // 予定開始を過ぎただけの進行中の予定は「終わった予定」にしない（Q83）
        let finished = timed
            .filter { $0.day == today && start($0) <= now && !inProgressIDs.contains($0.id) }
            .sorted(by: inOrder)

        // これからの予定：今日の予定。今日の予定が終わったら、主状態の予定（明日の最初の予定など）を 1 件（§88.2）
        var upcoming = timed.filter { $0.day == today && start($0) > now }
        if let main = state.event, start(main) > now, !upcoming.contains(where: { $0.id == main.id }) {
            upcoming.append(main)
        } else if !upcoming.isEmpty {
            // 明日の最初の予定の推奨出発時刻が今日の夜にあるときは、その出発の点を今日のタイムラインにも出す（§88.2・Q77-9）
            let tomorrow = today.adding(days: 1, calendar: calendar)
            if let first = timed.filter({ $0.day == tomorrow && start($0) > now }).min(by: inOrder),
               case .available(let leaveAt) = estimate(first),
               CalendarDay(leaveAt, calendar: calendar) == today, minuteStart < leaveAt {
                upcoming.append(first)
            }
        }

        // 過ぎた出発の点：出発時刻を過ぎて「出発してください」「出発時刻を○分過ぎています」の案内が続いている間だけ（Q83・Q87）。
        // 予定開始で「予定時刻になりました」に替わった・案内する予定が替わったら、通常の過去の表示に戻す（出さない）
        let pastDeparture: PastDeparture? = {
            switch state {
            case .departureTime(let event, let leaveAt), .departureOverdue(let event, let leaveAt, _):
                return PastDeparture(event: event, leaveAt: leaveAt)
            default:
                return nil
            }
        }()

        // 出発の点と予定開始の点を、別々の点として時刻の順に並べる（同じ時刻なら出発の点を先に。Q81）
        var points: [(item: Item, order: Int)] = []
        for event in upcoming {
            let isMain = event.id == mainID
            if case .available(let leaveAt) = estimate(event), minuteStart < leaveAt {
                points.append((Item(id: "departure-\(event.id.uuidString)", kind: .departure, event: event, date: leaveAt, isMain: isMain), 0))
            }
            points.append((Item(id: "start-\(event.id.uuidString)", kind: .start, event: event, date: start(event), isMain: isMain), 1))
        }
        points.sort { lhs, rhs in
            (lhs.item.date, lhs.order, lhs.item.event?.displayTitle ?? "", lhs.item.id)
                < (rhs.item.date, rhs.order, rhs.item.event?.displayTitle ?? "", rhs.item.id)
        }

        var items: [Item] = inProgress.map { event in
            Item(id: "now-\(event.id.uuidString)", kind: .inProgress(end: end(event)), event: event, date: start(event),
                 isMain: event.id == mainID)
        }
        var currentDay = today
        for point in points {
            let day = CalendarDay(point.item.date, calendar: calendar)
            if day != currentDay {
                items.append(Item(id: "day-\(day.year)-\(day.month)-\(day.day)", kind: .daySeparator(day), event: nil,
                                  date: day.date(calendar: calendar), isMain: false))
                currentDay = day
            }
            items.append(point.item)
        }

        // 予定がないときの文（今日の行が 1 つもないとき）。終日の予定だけの日は「今日は時間指定の予定はありません」（§13）
        let hasTodayRows = !inProgress.isEmpty || pastDeparture != nil
            || points.contains { CalendarDay($0.item.date, calendar: calendar) == today }
        if !hasTodayRows {
            let todays = events.filter { $0.day == today }
            if todays.contains(where: \.isAllDay) && !todays.contains(where: { !$0.isAllDay }) {
                items.insert(Item(id: "message", kind: .message(onlyAllDayText), event: nil, date: now, isMain: false), at: 0)
            } else if items.isEmpty {
                items.insert(Item(id: "message", kind: .message(noEventsText), event: nil, date: now, isMain: false), at: 0)
            }
        }

        var allDay: [CalendarEvent] = []
        var seen = Set<UUID>()
        for event in events.filter({ $0.day == today && $0.isAllDay }) + displayOnlyEvents.filter({ $0.day == today })
        where seen.insert(event.id).inserted {
            allDay.append(event)
        }
        allDay.sort { ($0.displayTitle, $0.id.uuidString) < ($1.displayTitle, $1.id.uuidString) }

        return HomeTimeline(today: today, now: now, mainEventID: mainID, allDayEvents: allDay, finishedEvents: finished,
                            pastDeparture: pastDeparture, items: items)
    }

    /// 「いま」より上の左の列の並び（Q87）。過ぎた出発の点はいつも最大 1 件
    var aboveNow: [AboveNow] {
        pastDeparture == nil ? [.figure, .now] : [.figure, .pastDeparture, .now]
    }

    /// 並べた予定（開始の点・進行中の行）の数。出発の点・区切り・文は数えない
    var eventCount: Int {
        items.filter(\.isEventRow).count
    }

    /// 日付の表示「10月16日（金）」（左上。大きな見出しにはしない：§88.2）
    static func dateTitle(_ day: CalendarDay, calendar: Calendar = .timyCue) -> String {
        "\(day.month)月\(day.day)日（\(day.weekdaySymbol(calendar: calendar))）"
    }

    /// 日付の下の終日の予定の 1 行（多ければ「ほか○件」。§88.2・Q77-10。出す件数は仮）
    var allDayText: String? {
        guard !allDayEvents.isEmpty else { return nil }
        let titles = allDayEvents.map(\.displayTitle)
        let shown = titles.prefix(Self.allDayTitlesShown).joined(separator: "・")
        let rest = titles.count - Self.allDayTitlesShown
        return rest > 0 ? "終日　\(shown) ほか\(rest)件" : "終日　\(shown)"
    }

    /// 終日の予定の名前を何件まで並べるか（仮）
    static let allDayTitlesShown = 2

    /// 「終わった予定 ○件」（終わった予定がないときは出さない。Q91）
    var finishedText: String? {
        finishedEvents.isEmpty ? nil : "終わった予定 \(finishedEvents.count)件"
    }

    /// 日付の区切りの文字（「明日　10/20（火）」。明日より先は日付だけ）
    static func separatorText(_ day: CalendarDay, today: CalendarDay, calendar: Calendar = .timyCue) -> String {
        let date = "\(day.month)/\(day.day)（\(day.weekdaySymbol(calendar: calendar))）"
        return day == today.adding(days: 1, calendar: calendar) ? "明日　\(date)" : date
    }
}

extension HomeState {
    /// 出発時刻を過ぎて、出発の案内（「出発してください」「出発時刻を○分過ぎています」）が続いているか（Q83）
    var isPastDepartureGuidance: Bool {
        switch self {
        case .departureTime, .departureOverdue: true
        default: false
        }
    }
}
