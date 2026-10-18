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

    /// 消した予定の結び付けを外す（メモリの上。ファイルに書けなくても、消した予定を二度消さない・取り違えない。
    /// 書けないまま終わったら、次に開いたときに古い結び付けが残るが、Apple 側で消えた予定の 2 回の確かめで外れる）
    mutating func forgetDeleted(_ ids: Set<UUID>) {
        for id in ids { keys[id] = nil }
        endUnset.subtract(ids)
    }

    /// 予定の id と Apple カレンダーの予定の鍵を結ぶ。同じ鍵をほかの id が持っていたら、そちらの結び付きを外して、その id を返す
    /// （1 つの Apple の予定を、2 つの TimyCue の予定に結ばない。spec §89.9・2026-10-18 S1b）
    @discardableResult
    mutating func setKey(_ key: String?, for id: UUID) -> UUID? {
        var displaced: UUID?
        if let key, let other = keys.first(where: { $0.value == key && $0.key != id })?.key {
            keys[other] = nil
            displaced = other
        }
        keys[id] = key
        return displaced
    }

    /// 結び付けている Apple カレンダーの予定の識別子（繰り返しの回は、シリーズの識別子にまとめる）
    var itemIdentifiers: Set<String> {
        Set(keys.values.map { EventKitMapping.parseLinkKey($0).itemIdentifier })
    }

    /// 見つからなかった予定・回と、最初に見つからなかった時刻（追加仕様書 §1.5）。
    /// 値は予定の識別子（予定そのもの・繰り返し全体）か、繰り返しの回の鍵。古いファイルにはないので省略できる
    var missingSince: [String: Date]?

    /// Apple カレンダー側で消えたことを確かめる。1 回見つからなかっただけでは消さない（一時的な読み込みの不具合と区別する）。
    /// 前に見つからなかった時から minimumInterval 以上たった、別の確認でもまだ見つからないものだけを返す。
    /// 見つかったものは記録から外す。全部が一度に見つからない読み込みは、同期・権限・読み込みの不具合とみなし、
    /// 記録も削除の確定もしない（正常に読み直せてから、1 件ずつ確かめる）
    mutating func confirmMissing(_ missing: Set<String>, checked: Set<String>, now: Date, minimumInterval: TimeInterval) -> Set<String> {
        guard Self.trustsVanished(missing, total: checked.count) || missing.isEmpty else { return [] }
        let linked = itemIdentifiers.union(keys.values)
        var pending = (missingSince ?? [:]).filter { linked.contains($0.key) }
        var confirmed = Set<String>()
        for target in checked where !missing.contains(target) {
            pending[target] = nil
        }
        for target in missing {
            if let since = pending[target] {
                if now.timeIntervalSince(since) >= minimumInterval {
                    confirmed.insert(target)
                    pending[target] = nil
                }
            } else {
                pending[target] = now
            }
        }
        missingSince = pending.isEmpty ? nil : pending
        return confirmed
    }

    /// Apple カレンダー側で削除が確かめられた予定・回の結びつきを外し、消す TimyCue の情報の id を返す（追加仕様書 §1.5）。
    /// 予定の識別子なら、その予定（繰り返しなら全部の回とシリーズ共通の設定）。回の鍵なら、その回だけ
    mutating func removeVanished(_ vanished: Set<String>) -> Set<UUID> {
        guard !vanished.isEmpty else { return [] }
        var removed = Set<UUID>()
        for (id, key) in keys where vanished.contains(key) || vanished.contains(EventKitMapping.parseLinkKey(key).itemIdentifier) {
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

    /// 正常な読み込みとみなしてよいか。結び付けている予定がまとめて見つからないときは、
    /// 同期・権限・読み込みの不具合を先に疑う（追加仕様書 §1.5）
    static func trustsVanished(_ vanished: Set<String>, total: Int) -> Bool {
        !vanished.isEmpty && (vanished.count < total || total < massMissingThreshold)
    }

    /// 全部が見つからないとき、読み込みの不具合とみなす件数。実装上の暫定値で、仕様の値ではない
    static let massMissingThreshold = 4
}
