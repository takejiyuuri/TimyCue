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
}

/// カレンダー連携の設定（設定 ＞ カレンダー連携。Q32・Q33）。端末の中に保存する
struct CalendarPreferences: Codable, Equatable {
    /// 新しい予定の既定の保存先。nil なら iPhone の「新規イベントのデフォルトカレンダー」（Q32）
    var defaultCalendarID: String?
    /// 読み込まないカレンダー。初めは何も外さない（参照できるカレンダーはすべて読み込む。Q33）
    var hiddenCalendarIDs: Set<String> = []

    func isShown(_ calendarID: String) -> Bool {
        !hiddenCalendarIDs.contains(calendarID)
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
