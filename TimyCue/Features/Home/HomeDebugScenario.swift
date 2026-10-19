#if DEBUG
import Foundation

/// H2 の Home の画面写真用の見本（DEBUG のときだけ。公開版（Release）と TestFlight の形（Release ＋ TIMYCUE_DEV_TOOLS）には入らない）。
/// 起動引数 `-TimyCueHomeScenario 名前` で、場面ごとの見本の予定（メモリの中だけ。本物の予定・設定のファイル・Apple カレンダーには
/// 書かない）と、固定の時刻・見本の出発時刻（場所ありの予定は開始の 15 分前。経路も位置情報も使わない）で Home を出す。
/// Home の計算（HomeScreenModel）は本物のまま使い、見本で真似をしない
enum HomeDebugScenario: String, CaseIterable {
    /// 1 今日の予定なし
    case empty
    /// 2 場所なしの予定 1 件（開始まで 23 分）
    case onePlaceless
    /// 3 場所ありの予定 1 件（出発まで 23 分）
    case onePlace
    /// 4 予定 2 件（出発まで 45 分）
    case two
    /// 5 予定 5 件と終日の予定（出発まで 85 分：時計なし・亀）
    case several
    /// 6 予定 11 件（「ほか○件」）
    case many
    /// 7 出発まで 60 分（時計が出る最初の分。人型）
    case departure60
    /// 8 出発まで 30 分（うさぎ・弧は黄）
    case departure30
    /// 9 出発まで 1 分
    case departure1
    /// 10 出発時刻を 3 分過ぎた（過ぎた出発の点）
    case overdue
    /// 11 終わった予定がある（と進行中の予定）
    case finished
    /// 場所なしの予定の開始時刻（「予定時刻になりました」）
    case started
    /// 今日は終日の予定だけ（「今日は時間指定の予定はありません」と明日の予定）
    case allDayOnly
    /// 今日の予定が終わった夜（「明日」の区切りと明日の最初の予定）
    case tomorrow
    /// 14 長い予定名・場所名
    case longText

    /// 起動引数の値
    static let current: HomeDebugScenario? = UserDefaults.standard.string(forKey: "TimyCueHomeScenario")
        .flatMap(HomeDebugScenario.init(rawValue:))

    /// 見本の移動時間（場所ありの予定の推奨出発時刻は、開始のこの分前）
    static let travelMinutes = 15

    /// 固定の時刻（その日の 0:00 からの分）
    var nowMinute: MinuteOfDay {
        switch self {
        case .empty, .allDayOnly: 9 * 60
        case .onePlaceless, .onePlace, .longText: 9 * 60 + 37
        case .two, .many: 8 * 60 + 30
        case .several: 7 * 60 + 50
        case .departure60: 9 * 60
        case .departure30: 9 * 60 + 30
        case .departure1: 9 * 60 + 59
        case .overdue: 10 * 60 + 3
        case .finished: 14 * 60 + 20
        case .started: 10 * 60 + 1
        case .tomorrow: 20 * 60
        }
    }

    func now(on day: CalendarDay, calendar: Calendar = .timyCue) -> Date {
        day.date(atMinute: nowMinute, calendar: calendar)
    }

    /// 見本の出発時刻の見込み（DepartureStore の代わり）：場所ありは開始の 15 分前、場所なしは出発なし
    func estimate(for event: CalendarEvent, calendar: Calendar = .timyCue) -> DepartureEstimate {
        guard !event.isAllDay, HomeSchedule.hasPlace(event) else { return .notNeeded }
        let start = HomeSchedule.startDate(of: event, calendar: calendar)
        return .available(start.addingTimeInterval(TimeInterval(-Self.travelMinutes * 60)))
    }

    /// 場面の見本の予定（today の日の前後）
    func sample(around today: CalendarDay) -> (events: [CalendarEvent], metadata: [UUID: TimyCueEventMetadata]) {
        var events: [CalendarEvent] = []
        var metadata: [UUID: TimyCueEventMetadata] = [:]

        func add(_ hour: Int, _ minute: Int, _ title: String, dayOffset: Int = 0, place: String? = nil,
                 color: EventColor, duration: Int? = nil, transport: TransportMode = .auto) {
            let event = CalendarEvent(day: today.adding(days: dayOffset), startMinute: hour * 60 + minute,
                                      durationMinutes: duration, title: title, locationName: place)
            var info = TimyCueEventMetadata()
            info.color = color
            info.transport = transport
            events.append(event)
            metadata[event.id] = info
        }

        func addAllDay(_ title: String, color: EventColor = .saxeBlue) {
            let event = CalendarEvent(day: today, startMinute: 0, title: title, isAllDay: true)
            var info = TimyCueEventMetadata()
            info.color = color
            events.append(event)
            metadata[event.id] = info
        }

        func addVisit(_ hour: Int, _ minute: Int, dayOffset: Int = 0) {
            add(hour, minute, "A社打合せ（見本）", dayOffset: dayOffset, place: "広島市中区（見本）", color: .orange, duration: 60,
                transport: .car)
        }

        func addDentist() {
            add(13, 0, "歯医者（見本）", place: "見本デンタルクリニック", color: .mint, duration: 30, transport: .walk)
        }

        switch self {
        case .empty:
            break
        case .onePlaceless:
            add(10, 0, "オンライン会議（見本）", color: .lavender, duration: 30)
        case .onePlace:
            addVisit(10, 15)
        case .two:
            addVisit(9, 30)
            add(13, 0, "電話：見本さん", color: .lavender)
        case .several, .many:
            addAllDay("見本の終日予定")
            addVisit(9, 30)
            add(10, 0, "社内レビュー（見本）", color: .green, duration: 60)
            add(10, 15, "見本さんへ連絡", color: .yellow)
            addDentist()
            add(18, 0, "電話：見本さん", color: .lavender)
            if self == .many {
                add(11, 0, "資料の確認（見本）", color: .green, duration: 30)
                add(11, 30, "見本の打合せ", color: .yellow, duration: 30)
                add(14, 0, "見本の作業", color: .mint, duration: 60)
                add(15, 30, "見本の電話", color: .lavender)
                add(16, 30, "見本の会議", color: .saxeBlue, duration: 30)
                add(17, 0, "見本さんへ連絡（夕方）", color: .orange)
            }
        case .departure60, .departure30, .departure1, .overdue:
            addVisit(10, 15)
            addDentist()
            add(18, 0, "電話：見本さん", color: .lavender)
        case .finished:
            add(9, 0, "朝会（見本）", color: .green, duration: 15)
            add(10, 0, "社内レビュー（見本）", color: .yellow, duration: 60)
            add(12, 0, "昼食（見本）", color: .mint, duration: 60)
            add(13, 30, "見本の作業", color: .saxeBlue, duration: 60)
            addVisit(15, 0)
            add(17, 0, "電話：見本さん", color: .lavender)
        case .started:
            add(10, 0, "オンライン会議（見本）", color: .lavender, duration: 30)
            addDentist()
        case .allDayOnly:
            addAllDay("見本の終日予定")
            addAllDay("見本の休み", color: .green)
            addVisit(9, 30, dayOffset: 1)
        case .tomorrow:
            add(9, 0, "朝会（見本）", color: .green, duration: 15)
            add(11, 0, "打合せ（見本）", color: .yellow, duration: 60)
            addVisit(9, 30, dayOffset: 1)
        case .longText:
            addAllDay("とても長い終日の予定の名前の見本（社内イベントの準備期間・最終日）")
            add(10, 15, "見本株式会社本社ビル大会議室での四半期レビューと来期計画の打ち合わせ（見本）",
                place: "広島県広島市中区見本町一丁目2番3号 見本ビルディング10階 大会議室（見本）",
                color: .orange, duration: 60, transport: .car)
            add(11, 30, "長い予定名の見本：取引先との打ち合わせと現場の確認と資料の受け渡し", color: .green, duration: 30)
            add(13, 0, "歯医者（見本）", place: "見本デンタルクリニック 駅前本院（見本）", color: .mint, duration: 30, transport: .walk)
        }
        return (events, metadata)
    }
}
#endif
