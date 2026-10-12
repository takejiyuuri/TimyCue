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

/// 繰り返し（仕様 §54）。毎日・毎週・隔週・毎月・カスタムは、繰り返しを作る段階で足す。今は「なし」だけ。
enum RepeatRule: String, Codable {
    case none

    var displayName: String {
        switch self {
        case .none: "なし"
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
