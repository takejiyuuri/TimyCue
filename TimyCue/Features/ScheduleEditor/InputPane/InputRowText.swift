import Foundation

extension ScheduleEditorStore {
    /// 右上の 1 行に出す今の値（仕様 §44 の例：「到着目標 10分前」「通知 30分・出発」「終了 未設定」）
    func valueText(for row: InputRow) -> String {
        let info = content.metadata
        switch row {
        case .title:
            return content.title.isEmpty ? "未入力" : content.title
        case .location:
            return content.locationName.flatMap { $0.isEmpty ? nil : $0 } ?? "なし"
        case .arrivalTarget:
            return info.arrivalTargetMinutes.map { "\($0)分前" } ?? "未設定"
        case .transport:
            return info.transport.displayName
        case .route:
            return info.route.displayName
        case .notifications:
            return info.notifications.summary
        case .repeatRule:
            return content.repeatRule.displayName
        case .color:
            return info.color.displayName
        case .end:
            guard let day = displayedDay, let end = endMinute(on: day) else { return "未設定" }
            return TimeText.hourMinute(end)
        case .calendar:
            let id = content.calendarID ?? defaultCalendarID
            return writableCalendars.first { $0.id == id }?.title ?? "既定"
        }
    }

    /// 到着目標の候補（仕様 §49）。ほかはカスタムで選ぶ
    static let arrivalTargetChoices = [5, 10, 15, 20, 30]
    /// カスタムで選べる到着目標・通知の分（仮）
    static let customArrivalRange = 1...180
    static let customNotificationRange = 5...240
    static let customMinuteStep = 5

    /// 終了の行で素早く選べる所要時間（Q24：未設定・30・60・90・120 分・カスタム）。時間画面の下端のハンドルと同じ値を見る
    static let durationChoices = [30, 60, 90, 120]
    /// カスタムで選べる所要時間の範囲と刻み（分。仮）
    static let customDurationRange = 5...(24 * 60)
    static let customDurationStep = 5

    /// 下カレンダーの日付に出す予定の印（Q23）。予定色のドットを最大 3 個と、残りの件数
    func eventDots(on day: CalendarDay) -> (colors: [EventColor], more: Int) {
        let dayEvents = events
            .filter { $0.day == day }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startMinute) < ($1.isAllDay ? 0 : 1, $1.startMinute) }
        let colors = dayEvents.prefix(Self.maxEventDots).map { metadata(for: $0.id)?.color ?? .orange }
        return (Array(colors), max(dayEvents.count - Self.maxEventDots, 0))
    }

    static let maxEventDots = 3

    /// 表示中の日の所要時間を、分で入れる。開始時刻がない日は何もしない
    func setDuration(_ minutes: Int?) {
        guard let day = displayedDay, let start = startMinutes[day] else { return }
        setEndMinute(minutes.map { start + $0 }, on: day)
    }
}
