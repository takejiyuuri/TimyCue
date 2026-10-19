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

/// カレンダー連携の設定（設定 ＞ カレンダー連携。Q32・Q33）。端末の中に保存する。
/// 新しい版で足す項目は、なくても読める項目だけにする（古い TestFlight のビルドに戻しても読めるように。spec §89.8）
struct CalendarPreferences: Codable, Equatable {
    /// 新しい予定の既定の保存先にする Apple カレンダー。nil なら iPhone の「新規イベントのデフォルトカレンダー」（Q32）。
    /// 保存先の種類を「TimyCue のみ」にしても、連携を OFF にしても消さない（Apple の選択の記憶。Q103）
    var defaultCalendarID: String?
    /// 読み込まないカレンダー。初めは何も外さない（参照できるカレンダーはすべて読み込む。Q33）
    var hiddenCalendarIDs: Set<String> = []
    /// 「カレンダーを連携」の案内を「あとで」にした回数（Q38）。古いファイルにはないので省略できる
    var guidanceDismissCount: Int?
    /// 古い版（v1.2 の自動の切り替え）が付けた「保存先のカレンダーを切り替えました」をまだ知らせていない印。
    /// 自動の切り替えは廃止したので、もう知らせない。読むだけで消さない（spec §89.4・2026-10-18 Q110）。
    /// S2 の移行では、この印だけでは Apple に保存していた証拠にしない（2026-10-19 ユーザー指示）。古いファイルにはないので省略できる
    var pendingFallbackNotice: Bool?
    /// 重複候補で「両方残す」を選んだ組（もう聞かない。Q50）。古いファイルにはないので省略できる
    var keptBothDuplicates: Set<String>?
    /// ホームで「重複している可能性のある予定が N 件あります」と一度知らせた組（Q50）
    var notifiedDuplicates: Set<String>?
    /// 祝日カレンダーを手で直した分（カレンダーの id → 祝日として扱うか）。手で直した分は自動の判定より優先する（Q55）。
    /// 古いファイルにはないので省略できる
    var holidayOverrides: [String: Bool]?
    /// 新しい予定の既定の保存先の種類（spec §89.2・§89.8）。nil は移行の前（前の版と同じ Apple の決まりで扱う）。
    /// アプリの本物の保存先では、起動のときの移行で必ず入る。古いファイルにはないので省略できる
    var saveTargetKind: SaveTargetKind?
    /// Apple カレンダー連携（全体の ON/OFF。spec §89.6）。nil・true は ON、false は利用者がわざと OFF にした。古いファイルにはないので省略できる
    var appleLinkEnabled: Bool?
    /// この形を書いた版の印。新しい版が保存するたびに書く（古い版が書き直すと消えるので、それで見分ける。spec §89.8）。
    /// 古いファイルにはないので省略できる
    var formatVersion: Int?

    /// 新しい版が書く印の値
    static let currentFormatVersion = 2

    /// Apple カレンダー連携が ON か（初めは ON）
    var isAppleLinkEnabled: Bool {
        appleLinkEnabled ?? true
    }

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
}
