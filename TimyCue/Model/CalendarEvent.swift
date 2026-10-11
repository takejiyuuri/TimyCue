import Foundation

/// 予定色（仕様 §2・§37）。実際の色の値は DesignSystem の EventPalette が持つ（HEX は仮）。
enum EventColor: String, CaseIterable, Codable {
    case orange      // 淡いオレンジ
    case mint        // ミント
    case lavender    // ラベンダー
    case saxeBlue    // サックスブルー
    case yellow      // 淡いイエロー
    case green       // グリーン

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

/// 移動手段。選択肢の最終形は未決（仕様 §40 は推定が前提）。今は仮の 3 種。
enum TransportMode: String, CaseIterable, Codable {
    case car
    case walk
    case transit

    var displayName: String {
        switch self {
        case .car: "車"
        case .walk: "徒歩"
        case .transit: "電車・バス"
        }
    }
}

/// 通知の各段階（仕様 §38）。60 分前は Live Activity の開始で、通知はしないのでここには持たない。
struct NotificationSettings: Equatable, Codable {
    var thirtyMinutesBefore = true
    var tenMinutesBefore = true
    var atDeparture = true
    /// ユーザーが足す 1 件（出発の何分前か）。nil なら無し
    var extraMinutesBefore: Int?

    var summary: String {
        var parts: [String] = []
        if thirtyMinutesBefore { parts.append("30分") }
        if tenMinutesBefore { parts.append("10分") }
        if atDeparture { parts.append("出発") }
        if let extra = extraMinutesBefore { parts.append("\(extra)分") }
        return parts.isEmpty ? "なし" : parts.joined(separator: "・")
    }
}

/// 繰り返し。選択肢と「この回のみ／以降すべて」の扱いは未決（報告 Q10）。今は「なし」だけ。
enum RepeatRule: String, Codable {
    case none

    var displayName: String {
        switch self {
        case .none: "なし"
        }
    }
}

/// 予定の中身のうち、日付と開始時刻を除いたもの。
/// コピーで引き継ぐ項目（仕様 §33）はすべてここに入れる。
struct EventContent: Equatable, Codable {
    var title = ""
    var locationName: String?
    var color: EventColor = .orange
    /// 到着目標：予定開始の何分前に着きたいか。nil は未設定
    var arrivalTargetMinutes: Int?
    var transport: TransportMode?
    var notifications = NotificationSettings()
    /// 所要時間（分）。nil は終了時刻未設定（仕様 §24・§45）
    var durationMinutes: Int?
    var memo = ""
    /// 仕様 §33 により、コピーでは引き継がない
    var repeatRule: RepeatRule = .none
    // ルート設定（仕様 §33）は中身が未決のため、項目ができた段階でここに足す

    /// 主表示に使う名前。予定名がなければ場所名（仕様 §13・§14）
    var primaryLabel: String? {
        if !title.isEmpty { return title }
        if let place = locationName, !place.isEmpty { return place }
        return nil
    }

    /// コピー先に渡す中身。繰り返しは原則として引き継がない（仕様 §33）
    func copiedForNewEvent() -> EventContent {
        var copy = self
        copy.repeatRule = .none
        return copy
    }
}

/// どこから来た予定か。Apple カレンダーとの同期（仕様 §44）は後の段階で接続する。
enum EventSource: Equatable, Codable {
    case timyCue
    case appleCalendar
}

/// 保存済みの予定
struct CalendarEvent: Identifiable, Equatable, Codable {
    let id: UUID
    var day: CalendarDay
    /// 開始時刻（0:00 からの分）。開始時刻は必須（仕様 §45）
    var startMinute: MinuteOfDay
    var content: EventContent
    var isAllDay = false
    var source: EventSource = .timyCue

    init(id: UUID = UUID(),
         day: CalendarDay,
         startMinute: MinuteOfDay,
         content: EventContent,
         isAllDay: Bool = false,
         source: EventSource = .timyCue) {
        self.id = id
        self.day = day
        self.startMinute = startMinute
        self.content = content
        self.isAllDay = isAllDay
        self.source = source
    }

    /// 終了時刻。終了未設定なら nil（仮の終了時刻を本当の終了と見なさない。仕様 §45）
    var endMinute: MinuteOfDay? {
        content.durationMinutes.map { startMinute + $0 }
    }
}
