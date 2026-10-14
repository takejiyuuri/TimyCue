import CoreLocation
import Foundation

/// 出発時刻を計算する前に決めること（どの予定を・どこから・どの手段で・いつ計算し直すか）。画面に依らない決まりだけを置く
enum DeparturePlanner {
    /// 固定の起点がないとき、現在地からの最初の計算を始める予定開始の何時間前か（2026-10-14 決定。実機で確かめる暫定値）
    static let currentLocationLeadHours = 4
    /// 推奨出発時刻の何分前から、実際の現在地を起点にするか（追加仕様書 §8.5）
    static let currentLocationSwitchMinutes = 60
    /// ホームが前面のときに計算し直す間隔（分。2026-10-14 決定の基本値。場所・移動手段・予定時刻・現在地が変わればすぐ）
    static let recalculateIntervalMinutes = 5
    /// 現在地がこれ以上動いたら計算し直す（メートル。GPS の数十メートルの揺れでは計算し直さない。spec Q42-2。値は仮）
    static let significantMoveMeters = 300.0
    /// 前もって計算する予定：これから 24 時間のうちに始まる場所ありの予定を、近い順にこの件数まで（仮）
    static let lookaheadHours = 24
    static let maxEventsToCalculate = 3
    /// 一度計算できたあとに計算できなくなっても、この分まではその値を使い続ける（追加仕様書 §25.6）
    static let keepLastValidMinutes = 15

    /// 起点
    enum Origin: Equatable {
        /// 前の予定の場所・自宅
        case place(SavedPlace)
        /// 実際の現在地
        case currentLocation
        /// まだ計算を始めない（固定の起点がなく、予定開始の 4 時間前より前）
        case notYet
    }

    /// 前もって計算する予定
    static func eventsToCalculate(in events: [CalendarEvent], now: Date, calendar: Calendar = .timyCue) -> [CalendarEvent] {
        let limit = now.addingTimeInterval(TimeInterval(lookaheadHours * 3600))
        return events
            .filter { event in
                guard !event.isAllDay, HomeSchedule.hasPlace(event) else { return false }
                let start = HomeSchedule.startDate(of: event, calendar: calendar)
                return start > now && start <= limit
            }
            .sorted { HomeSchedule.startDate(of: $0, calendar: calendar) < HomeSchedule.startDate(of: $1, calendar: calendar) }
            .prefix(maxEventsToCalculate)
            .map { $0 }
    }

    /// 前もって使う固定の起点（追加仕様書 §28.5・§32、2026-10-14 決定）。
    /// ① 同じ日の直近の場所ありの予定（場所なしの予定はさかのぼる）→ ② 「自宅から出ることが多い」なら登録した自宅。
    /// どちらもなければ nil（当日の現在地を使う）。前の予定の場所の地点をまだ確かめていなければ、②へ進む（仮）
    static func plannedOrigin(for event: CalendarEvent,
                              among events: [CalendarEvent],
                              settings: DepartureSettings,
                              placeBook: PlaceBook,
                              calendar: Calendar = .timyCue) -> SavedPlace? {
        let start = HomeSchedule.startDate(of: event, calendar: calendar)
        let previous = events
            .filter { other in
                other.id != event.id && other.day == event.day && !other.isAllDay && HomeSchedule.hasPlace(other)
                    && HomeSchedule.startDate(of: other, calendar: calendar) < start
            }
            .max { HomeSchedule.startDate(of: $0, calendar: calendar) < HomeSchedule.startDate(of: $1, calendar: calendar) }
        if let previous, let point = placeBook.place(for: previous.locationName) {
            return point
        }
        if settings.firstEventOrigin == .home, let home = settings.home {
            return home
        }
        return nil
    }

    /// いまの計算に使う起点。推奨出発時刻の 60 分前を過ぎたら実際の現在地（追加仕様書 §8.5）。
    /// それより前は固定の起点。固定の起点がなければ、予定開始の 4 時間前から現在地（2026-10-14 決定の暫定ルール）
    static func origin(for event: CalendarEvent,
                       among events: [CalendarEvent],
                       settings: DepartureSettings,
                       placeBook: PlaceBook,
                       lastDeparture: Date?,
                       now: Date,
                       calendar: Calendar = .timyCue) -> Origin {
        if let lastDeparture, now >= lastDeparture.addingTimeInterval(-TimeInterval(currentLocationSwitchMinutes * 60)) {
            return .currentLocation
        }
        if let planned = plannedOrigin(for: event, among: events, settings: settings, placeBook: placeBook, calendar: calendar) {
            return .place(planned)
        }
        let start = HomeSchedule.startDate(of: event, calendar: calendar)
        return now >= start.addingTimeInterval(-TimeInterval(currentLocationLeadHours * 3600)) ? .currentLocation : .notYet
    }

    /// 推奨出発時刻（追加仕様書 §8.1〜§8.3）。
    /// 車・徒歩・自転車：地図の移動時間（車は駐車の 5 分を足す）と安全マージンから、到着目標の時刻から逆算する。
    /// 公共交通：安全マージンを乗車時間に足さず、到着目標を安全マージンの分だけ前倒しして、その時刻までに着く便の出発時刻にする
    static func recommendedDeparture(from origin: CLLocationCoordinate2D,
                                     to destination: CLLocationCoordinate2D,
                                     transport: TransportMode,
                                     start: Date,
                                     arrivalTargetMinutes: Int,
                                     margin: DepartureMath.MarginLevel,
                                     now: Date,
                                     travel: TravelTimeProviding,
                                     calendar: Calendar = .timyCue) async throws -> Date {
        let target = DepartureMath.arrivalTarget(start: start, arrivalTargetMinutes: arrivalTargetMinutes)
        if transport == .publicTransit {
            let ride = try await travel.travelTime(from: origin, to: destination, transport: transport, departure: nil, arrival: target)
            let marginMinutes = DepartureMath.safetyMarginMinutes(travelMinutes: DepartureMath.minutes(ofTravel: ride.seconds), level: margin)
            let earlier = target.addingTimeInterval(-TimeInterval(marginMinutes * 60))
            let trip = try await travel.travelTime(from: origin, to: destination, transport: transport, departure: nil, arrival: earlier)
            guard let leave = trip.departure else { throw TravelTimeError.transitUnavailable }
            // 分の頭にそろえる（少し早めの側）
            return calendar.dateInterval(of: .minute, for: leave)?.start ?? leave
        }
        // 前もっての計算では、到着目標の 1 時間前に出るとして地図に聞く（渋滞の見込みのため。仮）。それより前ならいま
        let leaveGuess = max(now, target.addingTimeInterval(-3600))
        let trip = try await travel.travelTime(from: origin, to: destination, transport: transport, departure: leaveGuess, arrival: nil)
        let travelMinutes = DepartureMath.predictedTravelMinutes(mapSeconds: trip.seconds, transport: transport)
        let marginMinutes = DepartureMath.safetyMarginMinutes(travelMinutes: travelMinutes, level: margin)
        return DepartureMath.recommendedDeparture(start: start, arrivalTargetMinutes: arrivalTargetMinutes,
                                                  travelMinutes: travelMinutes, marginMinutes: marginMinutes)
    }

    /// 計算に使う移動手段。はっきり指定していればそれ（勝手に変えない。追加仕様書 §30.2）。
    /// 「自動」は、実績がたまるまで「普段よく使う移動手段」（2026-10-14 決定）。まだ選んでいなければ nil
    static func transport(for metadata: TimyCueEventMetadata?, settings: DepartureSettings) -> TransportMode? {
        let chosen = metadata?.transport ?? .auto
        return chosen == .auto ? settings.usualTransport : chosen
    }
}
