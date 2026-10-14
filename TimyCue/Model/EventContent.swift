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
    /// 保存先の Apple カレンダー。nil は既定の保存先（Q32）
    var calendarID: String?

    init() {}

    init(event: CalendarEvent, metadata: TimyCueEventMetadata) {
        title = event.title
        locationName = event.locationName
        repeatRule = event.repeatRule
        notes = event.notes
        calendarID = event.calendarID
        self.metadata = metadata
    }

    /// コピー先に渡す中身（仕様 §63）。繰り返しは原則として引き継がない
    func copiedForNewEvent() -> EventContent {
        var copy = self
        copy.repeatRule = .none
        return copy
    }

    /// この中身で、その日の予定を組み立てる
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
                      calendarID: calendarID)
    }
}
