#if TIMYCUE_DEV_TOOLS
import Foundation
import Observation

// H2 の前提作業 2（2026-10-16 Q94・ユーザーの追加の指示）：今の Home の時計を、表示の時刻を手で進めて確かめるための計算。
// 検証用のビルド（TIMYCUE_DEV_TOOLS）だけに入る。見本の予定 1 件と、決まった出発時刻で、今の Home と同じ
// HomeState.resolve・HomeClockMath.face を呼ぶだけ。実際のカレンダー・通知・位置情報・経路の計算・Live Activity には
// 渡さず、何も保存しない。時計の計算や Home の決まりは変えない（ここで真似をせず、本物の計算をそのまま使う）

/// 時計を確かめる見本の予定
enum ClockVerificationScenario: String, CaseIterable {
    /// 場所ありの予定：数える先は推奨出発時刻（「出発まで」）
    case withPlace
    /// 場所なしの予定：数える先は予定の開始（「開始まで」）
    case withoutPlace

    var title: String {
        switch self {
        case .withPlace: "場所あり（出発まで）"
        case .withoutPlace: "場所なし（開始まで）"
        }
    }

    /// 数える先の時刻（場所ありは出発、場所なしは開始）。10:00
    static let targetMinute: MinuteOfDay = 10 * 60
    /// 場所ありの見本の移動時間（出発 10:00 → 開始 10:30）。経路は計算せず、決まった値にする
    static let sampleTravelMinutes = 30

    /// 見本の時刻の説明。場所ありは出発と開始、場所なしは開始だけ（場所なしの予定に出発はない：spec §12。2026-10-17）
    var scheduleText: String {
        switch self {
        case .withPlace: "出発 10:00・開始 10:30"
        case .withoutPlace: "開始 10:00"
        }
    }

    /// 見本の予定（day の日の 1 件。見本と分かる名前）
    func event(on day: CalendarDay) -> CalendarEvent {
        switch self {
        case .withPlace:
            var event = CalendarEvent(day: day, startMinute: Self.targetMinute + Self.sampleTravelMinutes, title: "見本：打ち合わせ")
            event.locationName = "見本の場所"
            return event
        case .withoutPlace:
            return CalendarEvent(day: day, startMinute: Self.targetMinute, title: "見本：オンライン会議")
        }
    }

    /// 見本の出発時刻の見込み（DepartureStore の代わり。経路も位置情報も使わない）
    func estimate(on day: CalendarDay, calendar: Calendar = .timyCue) -> DepartureEstimate {
        switch self {
        case .withPlace: .available(day.date(atMinute: Self.targetMinute, calendar: calendar))
        case .withoutPlace: .notNeeded
        }
    }
}

/// 表示の時刻を「数える先から何分か」で決めたときに、今の Home が出すもの
struct ClockVerificationModel: Equatable {
    let scenario: ClockVerificationScenario
    let day: CalendarDay
    /// 数える先（10:00）からの分。負は前（-23 なら 9:37）
    let offsetMinutes: Int
    var calendar: Calendar = .timyCue

    var target: Date { day.date(atMinute: ClockVerificationScenario.targetMinute, calendar: calendar) }
    var now: Date { target.addingTimeInterval(TimeInterval(offsetMinutes * 60)) }
    var event: CalendarEvent { scenario.event(on: day) }

    /// 今の Home と同じ主状態の決め方（HomeView と同じ呼び方）
    var state: HomeState {
        let estimate = scenario.estimate(on: day, calendar: calendar)
        return HomeState.resolve(events: [event], now: now, calendar: calendar, estimate: { _ in estimate })
    }

    /// 今の Home と同じ時計（数える先まで 60 分以内のときだけ）
    var face: HomeClockMath.Face? {
        state.clockTarget(calendar: calendar).flatMap { HomeClockMath.face(now: now, target: $0.date, calendar: calendar) }
    }

    /// 時計の中と下の言葉（「出発」「開始」）
    var targetWord: String? { state.clockTarget(calendar: calendar)?.word }

    var nowText: String { TimeText.hourMinute(Clock.minuteOfDay(now, calendar: calendar)) }

    /// 「出発の 23 分前」「出発の 3 分後」「ちょうど出発時刻」
    var offsetText: String {
        let word = scenario == .withPlace ? "出発" : "開始"
        if offsetMinutes == 0 { return "ちょうど\(word)時刻" }
        return offsetMinutes < 0 ? "\(word)の\(-offsetMinutes)分前" : "\(word)の\(offsetMinutes)分後"
    }

    /// 主状態の呼び名（確かめる人が、画面と見比べるため）
    var stateTitle: String {
        switch state {
        case .noEvents: "予定なし（開始の知らせが終わった）"
        case .upcoming: "時計なし（60分より前の静かな表示）"
        case .departureCountdown: "出発までの時計"
        case .startCountdown: "開始までの時計"
        case .departureTime: "出発時刻（出発してください）"
        case .departureOverdue: "出発時刻を3分以上過ぎた"
        case .eventStarted: "予定開始（予定時刻になりました）"
        case .moving, .arrived, .conflict, .departureUnavailable: "そのほか"
        }
    }

    /// 「いま」の文字を出すかの呼び名（時計があるときだけ）。到達点の言葉は案内の対象に合わせる（場所なしは「開始」。2026-10-17）
    var nowLabelTitle: String? {
        guard let face else { return nil }
        return face.showsNowLabel ? "出す" : "出さない（\(targetWord ?? "出発")と5分以内）"
    }

    /// 残り時間の弧の色の呼び名（時計があるときだけ）
    var ringColorTitle: String? {
        guard let face else { return nil }
        switch face.band {
        case .plenty: return "緑（60〜31分）"
        case .half: return "黄（30〜16分）"
        case .last: return "コーラル（15〜1分）"
        }
    }
}

/// 時計の検証画面で切り替えるもの。表示の時刻は、この画面の中だけで進める
@Observable
final class ClockVerificationStore {
    /// 動かせる範囲（数える先からの分）
    static let range = -90...40
    /// 時計の外径（画面の幅に対する割合）：H2 の第一の候補 40％と、今の Home の 74％
    static let clockWidths: [Double] = [0.40, 0.74]

    var scenario: ClockVerificationScenario
    var offsetMinutes: Int
    var clockWidth: Double
    /// 1 秒ごとに 1 分ずつ進める
    var isRunning = false
    let day: CalendarDay

    init(scenario: ClockVerificationScenario = .withPlace, offsetMinutes: Int = -61, clockWidth: Double = 0.40,
         day: CalendarDay = CalendarDay(Date())) {
        self.scenario = scenario
        self.offsetMinutes = min(max(offsetMinutes, Self.range.lowerBound), Self.range.upperBound)
        self.clockWidth = clockWidth
        self.day = day
    }

    var model: ClockVerificationModel {
        ClockVerificationModel(scenario: scenario, day: day, offsetMinutes: offsetMinutes)
    }

    /// minutes 分進める（負は戻す）。範囲の端で止め、自動で進めているときは止める
    func step(_ minutes: Int) {
        let next = offsetMinutes + minutes
        offsetMinutes = min(max(next, Self.range.lowerBound), Self.range.upperBound)
        if offsetMinutes != next || offsetMinutes == Self.range.upperBound { isRunning = false }
    }

    func jump(to offset: Int, scenario: ClockVerificationScenario? = nil) {
        if let scenario { self.scenario = scenario }
        isRunning = false
        offsetMinutes = min(max(offset, Self.range.lowerBound), Self.range.upperBound)
    }

    /// Codemagic の画面写真用：起動引数 `-TimyCueClockScenario withoutPlace -TimyCueClockOffset m23 -TimyCueClockWidth 40`。
    /// 数える先からの分は、起動引数で「-」が次の名前と取り違えられないよう、前は m（m23＝23 分前）、後は p（p3＝3 分後）で書く
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> ClockVerificationStore {
        let store = ClockVerificationStore()
        if let raw = defaults.string(forKey: "TimyCueClockScenario"), let scenario = ClockVerificationScenario(rawValue: raw) {
            store.scenario = scenario
        }
        if let raw = defaults.string(forKey: "TimyCueClockOffset"), let minutes = Self.offset(fromArgument: raw) {
            store.jump(to: minutes)
        }
        let percent = defaults.double(forKey: "TimyCueClockWidth")
        if let width = clockWidths.first(where: { abs($0 * 100 - percent) < 0.5 }) {
            store.clockWidth = width
        }
        return store
    }

    /// 「m23」→ -23、「p3」→ 3、「0」→ 0
    static func offset(fromArgument raw: String) -> Int? {
        if raw.hasPrefix("m") { return Int(raw.dropFirst()).map { -$0 } }
        if raw.hasPrefix("p") { return Int(raw.dropFirst()) }
        return Int(raw)
    }
}

/// すぐに飛べる時刻（確かめること 1 つずつ）
struct ClockVerificationPreset: Identifiable {
    let title: String
    let scenario: ClockVerificationScenario
    let offset: Int
    var id: String { "\(scenario.rawValue)\(offset)\(title)" }

    static let all: [ClockVerificationPreset] = [
        ClockVerificationPreset(title: "61分前（時計なし）", scenario: .withPlace, offset: -61),
        ClockVerificationPreset(title: "出発まで60分（丸のずらし）", scenario: .withPlace, offset: -60),
        ClockVerificationPreset(title: "55分前（「いま」を出さない）", scenario: .withPlace, offset: -55),
        ClockVerificationPreset(title: "54分前（「いま」を出す）", scenario: .withPlace, offset: -54),
        ClockVerificationPreset(title: "31分前（緑の最後）", scenario: .withPlace, offset: -31),
        ClockVerificationPreset(title: "30分前（黄になる）", scenario: .withPlace, offset: -30),
        ClockVerificationPreset(title: "出発まで23分", scenario: .withPlace, offset: -23),
        ClockVerificationPreset(title: "15分前（コーラルになる）", scenario: .withPlace, offset: -15),
        ClockVerificationPreset(title: "6分前（「いま」を出す）", scenario: .withPlace, offset: -6),
        ClockVerificationPreset(title: "5分前（「いま」を出さない）", scenario: .withPlace, offset: -5),
        ClockVerificationPreset(title: "出発まで1分", scenario: .withPlace, offset: -1),
        ClockVerificationPreset(title: "出発時刻（出発してください）", scenario: .withPlace, offset: 0),
        ClockVerificationPreset(title: "2分過ぎ（まだ出発してください）", scenario: .withPlace, offset: 2),
        ClockVerificationPreset(title: "3分過ぎ（○分過ぎています）", scenario: .withPlace, offset: 3),
        ClockVerificationPreset(title: "場所なし：61分前（時計なし）", scenario: .withoutPlace, offset: -61),
        ClockVerificationPreset(title: "開始まで23分", scenario: .withoutPlace, offset: -23),
        ClockVerificationPreset(title: "場所なし：開始時刻（予定時刻になりました）", scenario: .withoutPlace, offset: 0),
        ClockVerificationPreset(title: "場所なし：3分後（知らせが終わる）", scenario: .withoutPlace, offset: 3),
    ]

    /// 中央の文字の 4 種類（spec §88.3・Q85 の続き）
    static let centerTexts: [ClockVerificationPreset] = [
        ClockVerificationPreset(title: "出発まで60分", scenario: .withPlace, offset: -60),
        ClockVerificationPreset(title: "出発まで23分", scenario: .withPlace, offset: -23),
        ClockVerificationPreset(title: "出発まで1分", scenario: .withPlace, offset: -1),
        ClockVerificationPreset(title: "開始まで23分", scenario: .withoutPlace, offset: -23),
    ]
}
#endif
