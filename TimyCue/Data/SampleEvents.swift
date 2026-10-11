import Foundation

/// 見本の予定（モックデータ）。今日から数日分に、色・場所あり／なし・終了あり／なし・終日を混ぜて置く。
/// 個人の予定は使わない（App Store の画面写真にも写るため）。
enum SampleEvents {
    static func make(around today: CalendarDay = CalendarDay(Date())) -> [CalendarEvent] {
        func event(_ dayOffset: Int, _ hour: Int, _ minute: Int, _ title: String,
                   place: String? = nil, color: EventColor, duration: Int? = nil,
                   arrival: Int? = nil, transport: TransportMode? = nil, allDay: Bool = false) -> CalendarEvent {
            var content = EventContent()
            content.title = title
            content.locationName = place
            content.color = color
            content.durationMinutes = duration
            content.arrivalTargetMinutes = arrival
            content.transport = transport
            return CalendarEvent(day: today.adding(days: dayOffset),
                                 startMinute: hour * 60 + minute,
                                 content: content,
                                 isAllDay: allDay)
        }

        return [
            event(0, 9, 30, "A社打合せ", place: "広島市中区（見本）", color: .orange, duration: 60, arrival: 10, transport: .car),
            event(0, 13, 0, "歯医者", place: "見本デンタルクリニック", color: .mint, duration: 30, arrival: 5, transport: .walk),
            event(0, 18, 0, "電話：見本さん", color: .lavender),
            event(1, 10, 0, "現場確認", place: "見本ビル 3F", color: .saxeBlue, duration: 90, arrival: 10, transport: .car),
            event(1, 0, 0, "見本の終日予定", color: .yellow, allDay: true),
            event(2, 8, 45, "朝会", color: .green, duration: 15),
            event(2, 15, 30, "A社打合せ", place: "広島市中区（見本）", color: .orange, duration: 60, arrival: 10, transport: .car),
            event(7, 9, 30, "A社打合せ", place: "広島市中区（見本）", color: .orange, duration: 60, arrival: 10, transport: .car),
        ]
    }
}
