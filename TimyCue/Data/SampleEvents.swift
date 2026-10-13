import Foundation

/// 見本の予定（モックデータ）。今日から数日分に、色・場所あり／なし・終了あり／なし・終日を混ぜて置く。
/// 個人の予定は使わない（App Store の画面写真にも写るため）。
enum SampleEvents {
    static func make(around today: CalendarDay = CalendarDay(Date()))
        -> (events: [CalendarEvent], metadata: [UUID: TimyCueEventMetadata]) {
        var events: [CalendarEvent] = []
        var metadata: [UUID: TimyCueEventMetadata] = [:]

        func add(_ dayOffset: Int, _ hour: Int, _ minute: Int, _ title: String,
                 place: String? = nil, color: EventColor, duration: Int? = nil,
                 arrival: Int = 0, transport: TransportMode = .auto, allDay: Bool = false) {
            let event = CalendarEvent(day: today.adding(days: dayOffset),
                                      startMinute: hour * 60 + minute,
                                      durationMinutes: duration,
                                      title: title,
                                      locationName: place,
                                      isAllDay: allDay)
            var info = TimyCueEventMetadata()
            info.color = color
            info.arrivalTargetMinutes = arrival
            info.transport = transport
            events.append(event)
            metadata[event.id] = info
        }

        add(0, 9, 30, "A社打合せ", place: "広島市中区（見本）", color: .orange, duration: 60, arrival: 10, transport: .car)
        add(0, 13, 0, "歯医者", place: "見本デンタルクリニック", color: .mint, duration: 30, arrival: 5, transport: .walk)
        add(0, 18, 0, "電話：見本さん", color: .lavender)
        // 1 日タイムラインで横に分ける見本（仕様 §29）：9:30〜10:30 の A社打合せと重なる 2 件
        add(0, 10, 0, "社内レビュー", color: .green, duration: 60)
        add(0, 10, 15, "見本さんへ連絡", color: .yellow)
        add(0, 0, 0, "見本の終日予定（今日）", color: .saxeBlue, allDay: true)
        add(1, 10, 0, "現場確認", place: "見本ビル 3F", color: .saxeBlue, duration: 90, arrival: 10, transport: .publicTransit)
        add(1, 0, 0, "見本の終日予定", color: .yellow, allDay: true)
        add(2, 8, 45, "朝会", color: .green, duration: 15)
        add(2, 15, 30, "A社打合せ", place: "広島市中区（見本）", color: .orange, duration: 60, arrival: 10, transport: .car)
        add(7, 9, 30, "A社打合せ", place: "広島市中区（見本）", color: .orange, duration: 60, arrival: 10, transport: .car)
        add(5, 11, 0, "見本株式会社本社打ち合わせ（長い予定名の見本）", place: "見本ビル 10F", color: .saxeBlue, duration: 60)

        // 月カレンダーの表示の見本（仕様 §21）：6 件の日（色点だけ）と 13 件の日（11 件＋「+2」）
        let colors = EventColor.allCases
        let busyTitles = ["朝会", "見積", "現場A", "現場B", "打合せ", "書類", "電話", "移動", "点検", "納品", "片付け", "日報", "連絡"]
        for (index, title) in busyTitles.prefix(6).enumerated() {
            add(3, 8 + index, 0, title, color: colors[index % colors.count], duration: 30)
        }
        for (index, title) in busyTitles.enumerated() {
            add(4, 7 + index, 0, title, color: colors[index % colors.count], duration: 30)
        }

        return (events, metadata)
    }
}
