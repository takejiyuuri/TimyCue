import Foundation

/// Apple カレンダーの予定 1 件ぶんの中身。EKEvent そのものをさわらずに、変換の決まりだけをテストできるようにする
struct ExternalEventRecord: Equatable {
    var title: String
    var location: String?
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String?
    /// 繰り返し（EventKit の繰り返しを正本にする。Q37）
    var repeatRule: RepeatRule = .none
}

/// TimyCue の予定と、Apple カレンダーの予定の変換（仕様 §68・§69）
enum EventKitMapping {
    /// Apple カレンダーには終了時刻が要るので、終了未設定の予定は「開始＋10 分」で保存する。
    /// この 10 分は実際の終了として扱わず、衝突判定にも使わない（§69）
    static let placeholderDurationMinutes = 10

    /// Apple カレンダーへ書く中身
    static func record(from event: CalendarEvent, calendar: Calendar = .timyCue) -> ExternalEventRecord {
        let start = event.day.date(atMinute: event.isAllDay ? 0 : event.startMinute, calendar: calendar)
        let end: Date
        if event.isAllDay {
            end = event.day.adding(days: 1, calendar: calendar).date(calendar: calendar)
        } else {
            let minutes = event.durationMinutes ?? placeholderDurationMinutes
            end = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
        }
        return ExternalEventRecord(title: event.title,
                                   location: event.locationName,
                                   startDate: start,
                                   endDate: end,
                                   isAllDay: event.isAllDay,
                                   notes: event.notes.isEmpty ? nil : event.notes,
                                   repeatRule: event.repeatRule)
    }

    /// Apple カレンダーの予定から作る TimyCue の予定。
    /// endIsUnset：TimyCue が「終了未設定」として仮の 10 分で保存した予定なら true（終了を持たせない。§69）
    static func calendarEvent(from record: ExternalEventRecord,
                              id: UUID,
                              endIsUnset: Bool,
                              source: EventSource,
                              calendar: Calendar = .timyCue) -> CalendarEvent {
        let day = CalendarDay(record.startDate, calendar: calendar)
        let startMinute = record.isAllDay ? 0 : Clock.minuteOfDay(record.startDate, calendar: calendar)
        var duration: Int?
        if !record.isAllDay && !endIsUnset {
            let minutes = Int((record.endDate.timeIntervalSince(record.startDate) / 60).rounded())
            duration = minutes > 0 ? minutes : nil
        }
        return CalendarEvent(id: id,
                             day: day,
                             startMinute: startMinute,
                             durationMinutes: duration,
                             title: record.title,
                             locationName: record.location.flatMap { $0.isEmpty ? nil : $0 },
                             isAllDay: record.isAllDay,
                             repeatRule: record.repeatRule,
                             notes: record.notes ?? "",
                             source: source)
    }

    /// まだ読んでいない部分。読み込みを頼んだ範囲はいつも途切れない 1 本にしたいので、離れた範囲を頼まれたら間も読む
    static func missingRanges(wanted: ClosedRange<CalendarDay>,
                              requested: ClosedRange<CalendarDay>?) -> [ClosedRange<CalendarDay>] {
        guard let requested else { return [wanted] }
        var result: [ClosedRange<CalendarDay>] = []
        if wanted.lowerBound < requested.lowerBound {
            result.append(wanted.lowerBound...requested.lowerBound.adding(days: -1))
        }
        if wanted.upperBound > requested.upperBound {
            result.append(requested.upperBound.adding(days: 1)...wanted.upperBound)
        }
        return result
    }

    /// 繰り返しの予定は、回ごとに同じ識別子を持つので、その回の日時も足して 1 件ずつ見分ける
    static func linkKey(itemIdentifier: String, occurrenceDate: Date?) -> String {
        guard let occurrenceDate else { return itemIdentifier }
        return "\(itemIdentifier)|\(Int(occurrenceDate.timeIntervalSince1970))"
    }

    static func parseLinkKey(_ key: String) -> (itemIdentifier: String, occurrenceDate: Date?) {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let seconds = TimeInterval(parts[1]) else { return (key, nil) }
        return (parts[0], Date(timeIntervalSince1970: seconds))
    }
}

/// TimyCue の予定の id と Apple カレンダーの予定の結びつき、終了未設定の印（端末の中に保存する）
struct EventKitLinks: Codable, Equatable {
    /// TimyCue の予定の id → Apple カレンダーの予定の鍵（linkKey）
    var keys: [UUID: String] = [:]
    /// 終了未設定で、仮の 10 分で保存した予定（§69）
    var endUnset: Set<UUID> = []
    /// 繰り返し予定のシリーズ（Apple カレンダーの予定の識別子）→ シリーズ共通の設定を保存する id（追加仕様書 §2.7.1）。
    /// 古いファイルにはないので省略できる
    var seriesIDs: [String: UUID]?

    func id(forKey key: String) -> UUID? {
        keys.first { $0.value == key }?.key
    }

    /// 結び付けている Apple カレンダーの予定の識別子（繰り返しの回は、シリーズの識別子にまとめる）
    var itemIdentifiers: Set<String> {
        Set(keys.values.map { EventKitMapping.parseLinkKey($0).itemIdentifier })
    }

    /// Apple カレンダー側で消えた予定の結びつきを外し、消す TimyCue の情報の id（回ごと・シリーズ共通）を返す（追加仕様書 §1.5）
    mutating func removeVanished(_ vanished: Set<String>) -> Set<UUID> {
        guard !vanished.isEmpty else { return [] }
        var removed = Set<UUID>()
        for (id, key) in keys where vanished.contains(EventKitMapping.parseLinkKey(key).itemIdentifier) {
            keys[id] = nil
            endUnset.remove(id)
            removed.insert(id)
        }
        for item in vanished {
            if let seriesID = seriesIDs?[item] {
                seriesIDs?[item] = nil
                removed.insert(seriesID)
            }
        }
        if seriesIDs?.isEmpty == true { seriesIDs = nil }
        return removed
    }

    /// 消えたと見てよいか。権限や読み込みの不具合で全部が見つからないだけのときに、設定をまとめて消さないようにする
    static func trustsVanished(_ vanished: Set<String>, total: Int) -> Bool {
        !vanished.isEmpty && (vanished.count < total || total <= 3)
    }
}
