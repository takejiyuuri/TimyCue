import Foundation

/// iPhone の Apple カレンダー（EventKit）から見えるカレンダー 1 つ。iCloud・Google・Exchange なども含む（Q33）
struct CalendarChoice: Identifiable, Equatable, Hashable {
    /// EKCalendar の calendarIdentifier
    let id: String
    let title: String
    /// どのアカウントのカレンダーか（iCloud・Google など）
    let sourceTitle: String
    /// 予定を書き込めるか
    let isWritable: Bool
    /// カレンダーの色にいちばん近い予定色（一覧で見分けるため）
    let color: EventColor
    /// 祝日のカレンダーか（自動の判定。設定 ＞ カレンダー連携 ＞ 祝日カレンダー で直した分は CalendarPreferences が持つ）
    var isHolidays = false

    /// 祝日のカレンダーの自動の判定（Q55）。EventKit には祝日の印がないので、書き込めないカレンダーで、
    /// 名前に「祝日」「Holiday」が入っているものを祝日カレンダーとする。当たらないものは祝日にしない（通常の編集できない予定として扱う。§1.7）
    static func isHolidayCalendar(title: String, isWritable: Bool) -> Bool {
        guard !isWritable else { return false }
        let name = title.lowercased()
        return name.contains("祝日") || name.contains("holiday")
    }
}

/// カレンダー連携の設定（設定 ＞ カレンダー連携。Q32・Q33）。端末の中に保存する
struct CalendarPreferences: Codable, Equatable {
    /// 新しい予定の既定の保存先。nil なら iPhone の「新規イベントのデフォルトカレンダー」（Q32）
    var defaultCalendarID: String?
    /// 読み込まないカレンダー。初めは何も外さない（参照できるカレンダーはすべて読み込む。Q33）
    var hiddenCalendarIDs: Set<String> = []
    /// 「カレンダーを連携」の案内を「あとで」にした回数（Q38）。古いファイルにはないので省略できる
    var guidanceDismissCount: Int?
    /// 既定の保存先が使えなくなって iPhone の既定へ切り替えたことを、まだ知らせていない（v1.2。一度だけ知らせる）。
    /// 古いファイルにはないので省略できる
    var pendingFallbackNotice: Bool?
    /// 重複候補で「両方残す」を選んだ組（もう聞かない。Q50）。古いファイルにはないので省略できる
    var keptBothDuplicates: Set<String>?
    /// ホームで「重複している可能性のある予定が N 件あります」と一度知らせた組（Q50）
    var notifiedDuplicates: Set<String>?
    /// 祝日カレンダーを手で直した分（カレンダーの id → 祝日として扱うか）。手で直した分は自動の判定より優先する（Q55）。
    /// 古いファイルにはないので省略できる
    var holidayOverrides: [String: Bool]?

    /// そのカレンダーを祝日カレンダーとして扱うか：手で直していればそれ、なければ自動の判定（Q55）
    func isHolidayCalendar(_ calendar: CalendarChoice) -> Bool {
        holidayOverrides?[calendar.id] ?? calendar.isHolidays
    }

    /// 祝日カレンダーとして扱うかを手で決める（自動の判定より優先する）
    mutating func setHoliday(_ isHoliday: Bool, calendarID: String) {
        var overrides = holidayOverrides ?? [:]
        overrides[calendarID] = isHoliday
        holidayOverrides = overrides
    }

    func isShown(_ calendarID: String) -> Bool {
        !hiddenCalendarIDs.contains(calendarID)
    }

    /// TimyCue の既定の保存先が、削除・書き込み不可などで使えなくなっていたら、iPhone の既定へ戻す（v1.2「Apple Calendar」）。
    /// 戻したときだけ true を返し、知らせる印を付ける。戻したあとは既定を持たないので、同じことで二度は知らせない。
    /// 書き込めるカレンダーが 1 つも見えないとき（読み込みの途中など）は、消えたと決めつけない
    mutating func dropUnavailableDefault(writable: [CalendarChoice]) -> Bool {
        guard let id = defaultCalendarID, !writable.isEmpty, !writable.contains(where: { $0.id == id }) else { return false }
        defaultCalendarID = nil
        pendingFallbackNotice = true
        return true
    }

    /// 書き込めるカレンダーの中から、保存先を決める。予定ごとの指定 → 設定の既定 → iPhone の既定 の順（Q32）
    static func saveTarget(eventCalendarID: String?,
                           preferences: CalendarPreferences,
                           systemDefaultID: String?,
                           writable: [CalendarChoice]) -> String? {
        let writableIDs = Set(writable.map(\.id))
        for candidate in [eventCalendarID, preferences.defaultCalendarID, systemDefaultID] {
            if let candidate, writableIDs.contains(candidate) { return candidate }
        }
        return writable.first?.id
    }
}
