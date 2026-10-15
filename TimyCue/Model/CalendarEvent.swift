import Foundation

/// 予定色（仕様 §4・§53）。実際の色の値は DesignSystem の EventPalette が持つ（HEX は仮。仕様 §86）。
enum EventColor: String, CaseIterable, Codable {
    case orange      // 淡いオレンジ
    case mint        // ミント
    case lavender    // ラベンダー
    case saxeBlue    // サックスブルー
    case yellow      // 淡いイエロー
    case green       // 淡いグリーン

    var displayName: String {
        switch self {
        case .orange: "オレンジ"
        case .mint: "ミント"
        case .lavender: "ラベンダー"
        case .saxeBlue: "サックスブルー"
        case .yellow: "イエロー"
        case .green: "グリーン"
        }
    }
}

/// 繰り返しの単位
enum RepeatFrequency: String, Codable, CaseIterable {
    case daily
    case weekly
    case monthly
    /// Apple カレンダーから来る「毎年」（誕生日など）
    case yearly
}

/// 繰り返し（仕様 §54・Q37）。
/// 本来の繰り返しは Apple カレンダー（EventKit）の繰り返しを正本にする。TimyCue 独自の繰り返しの仕組みは作らない（2026-10-12 変更）。
/// TimyCue の画面では繰り返しを作らない（2026-10-13 ユーザー決定）。ここに持つのは、Apple カレンダーから読んだ繰り返しの決まりを表す値だけ
struct RepeatRule: Equatable, Codable {
    /// nil は「なし」
    var frequency: RepeatFrequency?
    /// 何日／週／か月／年ごとか（1 以上）
    var interval: Int
    /// 毎週のときの曜日（月曜を 0）。空なら、その予定の曜日
    var weekdays: Set<Int>
    /// この日まで（その日を含む）。nil は終わりなし
    var endDay: CalendarDay?

    init(frequency: RepeatFrequency? = nil, interval: Int = 1, weekdays: Set<Int> = [], endDay: CalendarDay? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.endDay = endDay
    }

    static let none = RepeatRule()
    static let daily = RepeatRule(frequency: .daily)
    static let weekly = RepeatRule(frequency: .weekly)
    static let biweekly = RepeatRule(frequency: .weekly, interval: 2)
    static let monthly = RepeatRule(frequency: .monthly)

    var isRepeating: Bool { frequency != nil }

    // MARK: - 保存

    private enum CodingKeys: String, CodingKey {
        case frequency, interval, weekdays, endDay
    }

    /// 繰り返しが「なし」だけだったころのファイル（"none" という文字）も読めるようにする
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), (try? single.decode(String.self)) != nil {
            self = .none
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(frequency: try container.decodeIfPresent(RepeatFrequency.self, forKey: .frequency),
                  interval: try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1,
                  weekdays: try container.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? [],
                  endDay: try container.decodeIfPresent(CalendarDay.self, forKey: .endDay))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(frequency, forKey: .frequency)
        try container.encode(interval, forKey: .interval)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encodeIfPresent(endDay, forKey: .endDay)
    }
}

/// 繰り返し予定を直す・消すときの範囲（Q44）
enum RecurrenceScope: CaseIterable {
    case thisEvent
    case futureEvents
    case allEvents

    var displayName: String {
        switch self {
        case .thisEvent: "この予定のみ"
        case .futureEvents: "これ以降"
        case .allEvents: "すべて"
        }
    }
}

/// どこから来た予定か。Apple カレンダーとの同期（仕様 §68）は第4段階で接続する。
enum EventSource: Equatable, Codable {
    case timyCue
    case appleCalendar
}

/// 予定のうち、Apple カレンダー（EventKit）と共有する部分（仕様 §84）。
/// 到着目標・移動手段・通知など TimyCue だけが使う情報は、TimyCueEventMetadata に分けて持つ。
struct CalendarEvent: Identifiable, Equatable, Codable {
    let id: UUID
    var day: CalendarDay
    /// 開始時刻（0:00 からの分）。開始時刻は必須（仕様 §46・§69）
    var startMinute: MinuteOfDay
    /// 所要時間（分）。nil は終了時刻未設定（仕様 §41・§69）。複数日で登録しても予定ごとに持つ（Q1）
    var durationMinutes: Int?
    var title: String
    var locationName: String?
    var isAllDay: Bool
    var repeatRule: RepeatRule
    /// Apple カレンダーのメモ。主な入力欄には出さないが、消さずに持っておく（仕様 §55）
    var notes: String
    var source: EventSource
    /// 保存先の Apple カレンダー（EKCalendar の calendarIdentifier）。nil は既定の保存先（Q32）
    var calendarID: String?

    init(id: UUID = UUID(),
         day: CalendarDay,
         startMinute: MinuteOfDay,
         durationMinutes: Int? = nil,
         title: String,
         locationName: String? = nil,
         isAllDay: Bool = false,
         repeatRule: RepeatRule = .none,
         notes: String = "",
         source: EventSource = .timyCue,
         calendarID: String? = nil) {
        self.id = id
        self.day = day
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.title = title
        self.locationName = locationName
        self.isAllDay = isAllDay
        self.repeatRule = repeatRule
        self.notes = notes
        self.source = source
        self.calendarID = calendarID
    }

    /// 終了時刻。終了未設定なら nil（Apple カレンダー用の仮の終了を本当の終了と見なさない。仕様 §69）
    var endMinute: MinuteOfDay? {
        durationMinutes.map { startMinute + $0 }
    }

    /// 表示に使う名前（Q3）
    var displayTitle: String {
        Self.displayTitle(title: title, locationName: locationName)
    }

    /// 表示に使う名前の決まり（Q3）：予定名 → 場所名 → 「予定」。
    /// 予定名がないのは主に Apple カレンダーなど外から来た予定（TimyCue で作る予定は予定名が必須。仕様 §46）
    static func displayTitle(title: String, locationName: String?) -> String {
        if !title.isEmpty { return title }
        if let place = locationName, !place.isEmpty { return place }
        return "予定"
    }
}
