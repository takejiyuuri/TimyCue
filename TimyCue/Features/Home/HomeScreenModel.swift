import Foundation

/// 新しい Home（H2。spec §88）の 1 画面分の中身。画面に依らない計算だけを置く（テストで確かめる）。
/// 主状態・時計・キャラクターのモード・タイムラインを、同じ予定・同じ時刻・同じ出発時刻の見込みから一度に決める
struct HomeScreenModel: Equatable {
    /// 右の時計（Q94 で確かめた時計をそのまま使う。数える先の 60 分前から。場所ありは出発、場所なしは開始）
    struct ClockDisplay: Equatable {
        let face: HomeClockMath.Face
        let target: HomeSchedule.ClockTarget
        /// 時計の中と下の言葉（「出発」「開始」）
        var word: String { target.word }
    }

    let now: Date
    let state: HomeState
    let clock: ClockDisplay?
    /// 人型の見た目のモード（Q89・Q90）
    let mode: CharacterMode
    let timeline: HomeTimeline
    let dateTitle: String

    /// 主状態の大きな知らせ（「出発してください」「出発時刻を○分過ぎています」「予定時刻になりました」）。文言は今のまま
    var headline: String? { state.headline }
    /// 出発時刻を計算できない原因（小さく出す）
    var problem: DepartureProblem? { state.problem }

    static func make(events: [CalendarEvent],
                     displayOnlyEvents: [CalendarEvent] = [],
                     now: Date,
                     calendar: Calendar = .timyCue,
                     estimate: (CalendarEvent) -> DepartureEstimate) -> HomeScreenModel {
        // 主状態は今の Home と同じ決め方（追加仕様書 §45）
        let state = HomeState.resolve(events: events, now: now, calendar: calendar, estimate: estimate)
        let clock = state.clockTarget(calendar: calendar).flatMap { target in
            HomeClockMath.face(now: now, target: target.date, calendar: calendar).map { ClockDisplay(face: $0, target: target) }
        }
        let timeline = HomeTimeline.make(events: events, displayOnlyEvents: displayOnlyEvents, state: state, now: now,
                                         calendar: calendar, estimate: estimate)
        return HomeScreenModel(now: now,
                               state: state,
                               clock: clock,
                               mode: HomeCharacterMode.mode(for: state, now: now, calendar: calendar, estimate: estimate),
                               timeline: timeline,
                               dateTitle: HomeTimeline.dateTitle(timeline.today, calendar: calendar))
    }
}

/// Home の人型の見た目のモード（spec §88.4・Q89・Q90）。見た目（装備）だけを決め、動作（§88.7）や移動の状態とは分ける。
/// H2 では止まった姿を切り替えるだけ（着け外しの演出は H3）
enum HomeCharacterMode {
    /// 残りがこの分以下なら人型（甲羅を外す）。ちょうど 60 分は人型、61 分以上は亀（Q89：出発 61 分以上前は亀）
    static let humanFromMinutes = 60
    /// 残りがこの分以下ならうさぎ（耳の被り物）。31 分は人型、30 分はうさぎ
    static let rabbitFromMinutes = 30

    /// 数える先（場所ありは推奨出発時刻、場所なしは開始）までの残りの分からモードを決める
    static func mode(remainingMinutes: Int) -> CharacterMode {
        if remainingMinutes > humanFromMinutes { return .turtle }
        if remainingMinutes > rabbitFromMinutes { return .human }
        return .rabbit
    }

    /// 主状態からモードを決める。残りの分は時計と同じ数え方（HomeClockMath.remainingMinutes）
    static func mode(for state: HomeState,
                     now: Date,
                     calendar: Calendar = .timyCue,
                     estimate: (CalendarEvent) -> DepartureEstimate) -> CharacterMode {
        func remaining(to target: Date) -> Int {
            HomeClockMath.remainingMinutes(now: now, target: target, calendar: calendar)
        }
        switch state {
        case .noEvents:
            // 予定がないとき：亀モードでのんびり（Q90）
            return .turtle
        case .departureTime, .departureOverdue, .eventStarted:
            // 出発時刻を過ぎて案内が続いている間はうさぎのまま（Q90）。開始の知らせのあいだも、残り 0 分としてうさぎ
            return .rabbit
        case .moving, .arrived:
            // 実際の移動開始を確かめたら、移動の状態を優先してふつうの人型（Q90。移動の判定はまだ作っていない）
            return .human
        case .departureCountdown(_, let departure):
            return mode(remainingMinutes: remaining(to: departure))
        case .startCountdown(let event), .departureUnavailable(let event, _), .conflict(let event):
            // 場所なしの予定・出発時刻をまだ出せない予定は、開始までの残りで（Q90）
            return mode(remainingMinutes: remaining(to: HomeSchedule.startDate(of: event, calendar: calendar)))
        case .upcoming(let event):
            if case .available(let leaveAt) = estimate(event) {
                return mode(remainingMinutes: remaining(to: leaveAt))
            }
            return mode(remainingMinutes: remaining(to: HomeSchedule.startDate(of: event, calendar: calendar)))
        }
    }
}
