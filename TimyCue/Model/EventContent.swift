import Foundation

/// 3 分割画面の右上で入力する中身（日付・開始時刻・所要時間を除く）。
/// 保存するときに、CalendarEvent（Apple カレンダーと共有する部分）と TimyCueEventMetadata に分ける（仕様 §84）。
struct EventContent: Equatable {
    var title = ""
    var locationName: String?
    var repeatRule: RepeatRule = .none
    /// Apple カレンダーのメモ。入力欄には出さないが、編集しても消さない（仕様 §55）
    var notes = ""
    var metadata = TimyCueEventMetadata()

    /// 場所がある予定か（空白だけなら場所なし）
    var hasPlace: Bool {
        !(locationName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// 保存先の Apple カレンダー。nil は既定の保存先（Q32）。カレンダーを選んだら、「TimyCue のみ」の選びは外す
    var calendarID: String? = nil {
        didSet {
            if calendarID != nil { isTimyCueOnly = false }
        }
    }
    /// 新規・コピーで、この予定だけ「TimyCue のみ」を選んだ（spec §89.3。S2）。保存はしない（画面の中だけ）
    var isTimyCueOnly = false

    init() {}

    init(event: CalendarEvent, metadata: TimyCueEventMetadata) {
        title = event.title
        locationName = event.locationName
        repeatRule = event.repeatRule
        notes = event.notes
        calendarID = event.calendarID
        self.metadata = metadata
    }

    /// この予定だけの保存先の選び（作成画面の「カレンダー」の行）。nil は設定の既定
    var saveChoice: SaveChoice? {
        get {
            if isTimyCueOnly { return .timyCueOnly }
            return calendarID.map(SaveChoice.calendar)
        }
        set {
            switch newValue {
            case .timyCueOnly?:
                calendarID = nil
                isTimyCueOnly = true
            case .calendar(let id)?:
                calendarID = id
                isTimyCueOnly = false
            case nil:
                calendarID = nil
                isTimyCueOnly = false
            }
        }
    }

    /// コピー先に渡す中身（仕様 §63）。繰り返しは原則として引き継がない
    func copiedForNewEvent() -> EventContent {
        var copy = self
        copy.repeatRule = .none
        return copy
    }

    /// この中身で、その日の予定を組み立てる。「TimyCue のみ」を選んでいれば、Apple カレンダーの指定は付けない
    func makeEvent(id: UUID = UUID(),
                   day: CalendarDay,
                   startMinute: MinuteOfDay,
                   durationMinutes: Int?,
                   isAllDay: Bool = false,
                   source: EventSource = .timyCue) -> CalendarEvent {
        CalendarEvent(id: id,
                      day: day,
                      startMinute: startMinute,
                      durationMinutes: durationMinutes,
                      title: title,
                      locationName: locationName,
                      isAllDay: isAllDay,
                      repeatRule: repeatRule,
                      notes: notes,
                      source: source,
                      calendarID: isTimyCueOnly ? nil : calendarID)
    }
}
