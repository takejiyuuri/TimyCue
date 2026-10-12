import CoreGraphics
import EventKit
import Foundation

/// Apple カレンダー（EventKit）を保存先にする版（仕様 §68）。
/// TimyCue で作成・編集・削除した予定を Apple カレンダーに反映し、Apple カレンダー側の変更も読み込む。
/// TimyCue だけの情報（到着目標など）は EventKit の予定に入れず、別に保存する（§68・§84）。
/// 読み込む期間は決めず、表示に必要な範囲をそのつど読む（Q35）。読み込むカレンダーは設定で選べる（Q33）。
///
/// Apple カレンダーからの読み込みは時間がかかるので、画面の処理（メインスレッド）では行わない。
/// 裏で読み、読み終わったら onLoaded で知らせる（画面の処理で読むと、予定の多い人で画面が固まり、iOS に止められた）
final class EventKitEventRepository: EventRepository {
    private let store: EKEventStore
    private let linksFile: JSONFile<EventKitLinks>
    private var links: EventKitLinks
    /// links.keys の逆引き（Apple カレンダーの予定の鍵 → TimyCue の予定の id）
    private var idByKey: [String: UUID]
    private let metadata: EventMetadataRepository
    private let preferences: () -> CalendarPreferences
    private let calendar = Calendar.timyCue

    /// 読み込みを頼んだ範囲（内部のキャッシュ。ユーザーから見える制限ではない。Q35）
    private var requestedRange: ClosedRange<CalendarDay>?
    private var cache: [CalendarEvent] = []
    /// 起動してから、Apple カレンダー側で消えた予定を一度見たか
    private var checkedDeletedOnce = false
    /// 裏で読むための列。順に処理するので、結果も頼んだ順に届く
    private let fetchQueue = DispatchQueue(label: "io.github.takejiyuuri.timycue.eventkit", qos: .userInitiated)

    /// 裏での読み込みが済んで、予定が変わったとき（画面の処理の中で呼ぶ）
    var onLoaded: (@MainActor () -> Void)?

    init(store: EKEventStore,
         metadata: EventMetadataRepository,
         preferences: @escaping () -> CalendarPreferences,
         linksFile: JSONFile<EventKitLinks> = JSONFile(url: JSONFile<EventKitLinks>.appSupportURL(named: "eventkit-links.json"), empty: EventKitLinks())) {
        self.store = store
        self.metadata = metadata
        self.preferences = preferences
        self.linksFile = linksFile
        let loaded = linksFile.load()
        links = loaded
        idByKey = Dictionary(loaded.keys.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - カレンダー

    /// 見えるカレンダー（iCloud・Google・Exchange なども。Q33）
    func calendars() -> [CalendarChoice] {
        store.calendars(for: .event).map { ekCalendar in
            CalendarChoice(id: ekCalendar.calendarIdentifier,
                           title: ekCalendar.title,
                           sourceTitle: ekCalendar.source?.title ?? "",
                           isWritable: ekCalendar.allowsContentModifications,
                           color: Self.nearestColor(of: ekCalendar))
        }
    }

    /// iPhone の「新規イベントのデフォルトカレンダー」（Q32）
    var systemDefaultCalendarID: String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    // MARK: - 読み込み

    func allEvents() -> [CalendarEvent] {
        cache
    }

    /// その期間の予定がまだなら、足りない部分だけを裏で読む。読み終わったら onLoaded
    func ensureLoaded(from start: CalendarDay, to end: CalendarDay) {
        let wanted = min(start, end)...max(start, end)
        let missing = EventKitMapping.missingRanges(wanted: wanted, requested: requestedRange)
        guard !missing.isEmpty else { return }
        requestedRange = requestedRange.map { min($0.lowerBound, wanted.lowerBound)...max($0.upperBound, wanted.upperBound) } ?? wanted
        load(missing, replacingAll: false)
    }

    /// Apple カレンダー側が変わったとき・読み込むカレンダーを変えたときに、頼んだ範囲を裏で読み直す
    func reloadCache() {
        guard let range = requestedRange else { cache = []; return }
        load([range], replacingAll: true, checksDeleted: true)
    }

    /// 裏で読み、読み終わったら画面の処理の中で取り込む。
    /// checksDeleted のときは、結び付けてある予定が Apple カレンダー側で消えていないかも見る（追加仕様書 §1.5）
    private func load(_ ranges: [ClosedRange<CalendarDay>], replacingAll: Bool, checksDeleted: Bool = false) {
        let hidden = preferences().hiddenCalendarIDs
        let store = store
        let calendar = calendar
        // 起動して初めて読むときも見る（アプリを閉じている間に消された予定）
        let linkedKeys = (checksDeleted || !checkedDeletedOnce) ? Array(links.keys.values) : []
        checkedDeletedOnce = true
        fetchQueue.async { [weak self] in
            let fetched = ranges.flatMap { Self.fetch(store: store, hiddenCalendarIDs: hidden, range: $0, calendar: calendar) }
            let check = Self.missingTargets(linkedKeys: linkedKeys, fetchedKeys: Set(fetched.map(\.key)),
                                            ranges: ranges, store: store, calendar: calendar)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !linkedKeys.isEmpty { self.removeConfirmedMissing(check.missing, checked: check.checked) }
                    self.merge(fetched, ranges: ranges, replacingAll: replacingAll)
                    self.onLoaded?()
                }
            }
        }
    }

    /// Apple カレンダー側で削除されたかもしれない予定・回（裏で行う）。
    /// 予定そのもの・繰り返し全体は、識別子で引けなければ見つからないとする。
    /// 繰り返しの 1 回は、シリーズ全体を探してもないと確かめられたときだけ見つからないとする（下の説明）。
    /// カレンダーを隠しただけ・権限がないときは見つからないことにしない（§1.9・§1.10）
    private static func missingTargets(linkedKeys: [String],
                                       fetchedKeys: Set<String>,
                                       ranges: [ClosedRange<CalendarDay>],
                                       store: EKEventStore,
                                       calendar: Calendar) -> (missing: Set<String>, checked: Set<String>) {
        guard !linkedKeys.isEmpty, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return ([], []) }
        let fetchedItems = Set(fetchedKeys.map { EventKitMapping.parseLinkKey($0).itemIdentifier })
        var missing = Set<String>()
        var checked = Set<String>()

        // 予定そのもの・繰り返し全体
        let items = Set(linkedKeys.map { EventKitMapping.parseLinkKey($0).itemIdentifier })
        for item in items {
            checked.insert(item)
            if !fetchedItems.contains(item) && store.calendarItem(withIdentifier: item) == nil {
                missing.insert(item)
            }
        }

        // 繰り返しの 1 回。EventKit は、日をずらした回も「元の回の日時（occurrenceDate）」とシリーズの識別子を持ち続けるので、
        // それで追う。読んだ範囲にあるはずの回が読めなかったときは、シリーズの初めから終わりまで（前後 1 年を足す）を探し、
        // どこにもなければ削除とみなす。終わりのない繰り返し・回数で終わる繰り返し・長すぎる繰り返しは探しきれないので、
        // 削除か移動か区別できないとして確かめない（設定は残す）
        var candidates: [String: [Date]] = [:]
        for key in linkedKeys {
            let parsed = EventKitMapping.parseLinkKey(key)
            guard let occurrence = parsed.occurrenceDate, !missing.contains(parsed.itemIdentifier) else { continue }
            if fetchedKeys.contains(key) {
                checked.insert(key)
                continue
            }
            let day = CalendarDay(occurrence, calendar: calendar)
            guard ranges.contains(where: { $0.contains(day) }) else { continue }
            candidates[parsed.itemIdentifier, default: []].append(occurrence)
        }
        for (item, dates) in candidates {
            guard let master = store.calendarItem(withIdentifier: item) as? EKEvent,
                  let seriesEnd = master.recurrenceRules?.compactMap({ $0.recurrenceEnd?.endDate }).max(),
                  master.recurrenceRules?.allSatisfy({ $0.recurrenceEnd?.endDate != nil }) == true,
                  let seriesStart = master.startDate,
                  let start = calendar.date(byAdding: .year, value: -1, to: min(seriesStart, dates.min() ?? seriesStart)),
                  let end = calendar.date(byAdding: .year, value: 1, to: max(seriesEnd, dates.max() ?? seriesEnd)),
                  let limit = calendar.date(byAdding: .year, value: Self.seriesSearchYears, to: start),
                  end <= limit else { continue }
            var found = Set<Date>()
            var chunkStart = start
            while chunkStart < end {
                let chunkEnd = min(calendar.date(byAdding: .year, value: 3, to: chunkStart) ?? end, end)
                store.events(matching: store.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: nil))
                    .filter { $0.calendarItemIdentifier == item }
                    .compactMap { $0.occurrenceDate }
                    .forEach { found.insert($0) }
                chunkStart = chunkEnd
            }
            for date in dates {
                let key = EventKitMapping.linkKey(itemIdentifier: item, occurrenceDate: date)
                checked.insert(key)
                if !found.contains(date) { missing.insert(key) }
            }
        }
        return (missing, checked)
    }

    /// Apple カレンダー側での削除が確かめられた予定・回を、TimyCue からも消し、その TimyCue の設定も消す（追加仕様書 §1.5）。
    /// 1 回見つからなかっただけでは消さず、時間をおいた別の確認でもまだ見つからないときだけ消す
    private func removeConfirmedMissing(_ missing: Set<String>, checked: Set<String>) {
        let before = links
        let confirmed = links.confirmMissing(missing, checked: checked, now: Date(),
                                             minimumInterval: Self.deletionConfirmInterval)
        let removed = links.removeVanished(confirmed)
        if !removed.isEmpty {
            idByKey = idByKey.filter { !removed.contains($0.value) }
            cache.removeAll { removed.contains($0.id) }
            try? metadata.deleteAll(removed)
        }
        if links != before { try? linksFile.save(links) }
    }

    /// 削除を確かめるまでに空ける時間。実装上の暫定値で、仕様の値ではない（追加仕様書 §1.5 の決まりは
    /// 「1 回見つからないだけでは消さない」「時間を空けた別の正常な読み込みでも見つからないことを確かめる」
    /// 「続けて届く変更の知らせを、何回もの確認と数えない」）
    private static let deletionConfirmInterval: TimeInterval = 5 * 60
    /// 繰り返しの 1 回を探しきれるとみなす、シリーズの長さの上限（年）。実装上の暫定値
    private static let seriesSearchYears = 12

    /// 書き込んだ直後に、その日だけをすぐ読み直す（1 日ぶんなので短い。保存した予定をすぐ画面に出すため）
    private func refreshNow(days: [CalendarDay]) {
        let ranges = Set(days).map { $0...$0 }
        guard !ranges.isEmpty else { return }
        let hidden = preferences().hiddenCalendarIDs
        let fetched = ranges.flatMap { Self.fetch(store: store, hiddenCalendarIDs: hidden, range: $0, calendar: calendar) }
        merge(fetched, ranges: ranges, replacingAll: false)
    }

    /// 裏で読んだ予定を取り込む。TimyCue の予定の id を結び付け、初めて見る予定には色の初期候補を付ける
    private func merge(_ fetched: [FetchedEvent], ranges: [ClosedRange<CalendarDay>], replacingAll: Bool) {
        let known = metadata.allMetadata()
        var newMetadata: [UUID: TimyCueEventMetadata] = [:]
        // 繰り返しのまだ見ていない回は、シリーズ共通の設定（到着目標など）を使う。個別上書きは引き継がない（追加仕様書 §2.7.1）
        let seriesIDs = links.seriesIDs ?? [:]
        var linksChanged = false
        var events: [CalendarEvent] = []
        for item in fetched {
            let id: UUID
            // 前の id と設定を使い直すのは、鍵（予定の識別子＋繰り返しなら元の回の日時）が同じときだけ。
            // 名前や日時が似ているだけの予定には結び付け直さない（追加仕様書 §1.5.1・Q54）
            if let existing = idByKey[item.key] {
                id = existing
            } else {
                id = UUID()
                links.keys[id] = item.key
                idByKey[item.key] = id
                linksChanged = true
            }
            // 初めて見る Apple カレンダーの予定は、元のカレンダーの色を初期候補にする（§53）
            if known[id] == nil && newMetadata[id] == nil {
                let parsed = EventKitMapping.parseLinkKey(item.key)
                if parsed.occurrenceDate != nil,
                   let seriesID = seriesIDs[parsed.itemIdentifier], var common = known[seriesID] {
                    common.overrides = nil
                    newMetadata[id] = common
                } else {
                    var info = TimyCueEventMetadata()
                    info.color = item.calendarColor
                    newMetadata[id] = info
                }
            }
            var event = EventKitMapping.calendarEvent(from: item.record,
                                                      id: id,
                                                      endIsUnset: links.endUnset.contains(id),
                                                      source: .appleCalendar,
                                                      calendar: calendar)
            event.calendarID = item.calendarID
            events.append(event)
        }
        if linksChanged { try? linksFile.save(links) }
        // 何百件あっても、ファイルへは 1 回だけ書く
        if !newMetadata.isEmpty { try? metadata.saveAll(newMetadata) }

        var merged = replacingAll ? [] : cache.filter { event in !ranges.contains { $0.contains(event.day) } }
        merged.append(contentsOf: events)
        // 何日にもまたがる予定などが二重に入らないようにする
        var seen = Set<UUID>()
        cache = merged.filter { seen.insert($0.id).inserted }
    }

    /// Apple カレンダーから読んだ予定 1 件（裏で読むので、EKEvent ではなく値だけを持ち出す）
    private struct FetchedEvent {
        let key: String
        let record: ExternalEventRecord
        let calendarID: String?
        let calendarColor: EventColor
    }

    /// 裏で行う読み込みそのもの。EventKit の検索は 4 年までなので区切って読み、同じ予定は 1 件にする
    private static func fetch(store: EKEventStore,
                              hiddenCalendarIDs: Set<String>,
                              range: ClosedRange<CalendarDay>,
                              calendar: Calendar) -> [FetchedEvent] {
        let shown = store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !shown.isEmpty else { return [] }
        var result: [FetchedEvent] = []
        var seenKeys = Set<String>()
        var chunkStart = range.lowerBound
        while chunkStart <= range.upperBound {
            let chunkEnd = min(chunkStart.adding(days: 365 * 3, calendar: calendar), range.upperBound)
            let predicate = store.predicateForEvents(withStart: chunkStart.date(calendar: calendar),
                                                     end: chunkEnd.adding(days: 1, calendar: calendar).date(calendar: calendar),
                                                     calendars: shown)
            for ekEvent in store.events(matching: predicate) {
                let key = linkKey(for: ekEvent)
                guard seenKeys.insert(key).inserted else { continue }
                result.append(FetchedEvent(key: key,
                                           record: record(of: ekEvent, store: store),
                                           calendarID: ekEvent.calendar?.calendarIdentifier,
                                           calendarColor: nearestColor(of: ekEvent.calendar)))
            }
            chunkStart = chunkEnd.adding(days: 1, calendar: calendar)
        }
        return result
    }

    // MARK: - 書き込み

    func insert(_ events: [CalendarEvent]) throws {
        let writable = calendars().filter(\.isWritable)
        for event in events {
            guard let targetID = CalendarPreferences.saveTarget(eventCalendarID: event.calendarID,
                                                                preferences: preferences(),
                                                                systemDefaultID: systemDefaultCalendarID,
                                                                writable: writable),
                  let target = store.calendar(withIdentifier: targetID) else {
                throw EventKitRepositoryError.noCalendar
            }
            let ekEvent = EKEvent(eventStore: store)
            ekEvent.calendar = target
            Self.apply(EventKitMapping.record(from: event, calendar: calendar), to: ekEvent, includeRecurrence: true)
            try store.save(ekEvent, span: event.repeatRule.isRepeating ? .futureEvents : .thisEvent, commit: false)
            setKey(Self.linkKey(for: ekEvent), for: event.id)
            setEndUnset(event)
        }
        try store.commit()
        try linksFile.save(links)
        refreshNow(days: events.map(\.day))
        // 繰り返しはほかの日にも出るので、読み込んである範囲を読み直す（裏で）
        if events.contains(where: \.repeatRule.isRepeating) { reloadCache() }
    }

    func update(_ event: CalendarEvent) throws {
        try update(event, scope: .thisEvent)
    }

    /// 予定を直す。繰り返し予定は、この予定のみ／これ以降／すべて の範囲で直す（Q44）。
    /// 「この予定のみ」では繰り返しの決まりは変えない。「すべて」は、系列の初めの回に、この回で動かした分だけ同じように当てる
    func update(_ event: CalendarEvent, scope: RecurrenceScope) throws {
        guard let occurrence = find(event.id) else { throw EventRepositoryError.notFound(event.id) }
        let record = EventKitMapping.record(from: event, calendar: calendar)
        let oldDay = cache.first { $0.id == event.id }?.day
        let wasRecurring = occurrence.hasRecurrenceRules

        if !wasRecurring || scope == .thisEvent {
            // 繰り返しでない予定に繰り返しを付けるのもここ（範囲は聞かない）
            Self.apply(record, to: occurrence, includeRecurrence: !wasRecurring)
            moveCalendarIfNeeded(occurrence, to: event.calendarID)
            try store.save(occurrence, span: wasRecurring ? .thisEvent : .futureEvents, commit: true)
            setKey(Self.linkKey(for: occurrence), for: event.id)
        } else {
            let target: EKEvent
            let occurrenceDate: Date
            if scope == .allEvents,
               let master = store.calendarItem(withIdentifier: occurrence.calendarItemIdentifier) as? EKEvent {
                let shift = record.startDate.timeIntervalSince(occurrence.startDate)
                var shifted = record
                shifted.startDate = master.startDate.addingTimeInterval(shift)
                shifted.endDate = shifted.startDate.addingTimeInterval(record.endDate.timeIntervalSince(record.startDate))
                Self.apply(shifted, to: master, includeRecurrence: true)
                target = master
                occurrenceDate = occurrence.occurrenceDate.addingTimeInterval(shift)
            } else {
                Self.apply(record, to: occurrence, includeRecurrence: true)
                target = occurrence
                occurrenceDate = record.startDate
            }
            moveCalendarIfNeeded(target, to: event.calendarID)
            try store.save(target, span: .futureEvents, commit: true)
            setKey(EventKitMapping.linkKey(itemIdentifier: target.calendarItemIdentifier,
                                           occurrenceDate: target.hasRecurrenceRules ? occurrenceDate : nil),
                   for: event.id)
        }
        setEndUnset(event)
        try linksFile.save(links)
        refreshNow(days: [event.day] + (oldDay.map { [$0] } ?? []))
        // 繰り返しが変わると、ほかの日の回も変わるので、読み込んである範囲を読み直す（裏で）
        if (wasRecurring && scope != .thisEvent) || (!wasRecurring && record.repeatRule.isRepeating) {
            reloadCache()
        }
    }

    func delete(id: UUID) throws {
        try delete(id: id, scope: .thisEvent)
    }

    /// 予定を消す。繰り返し予定は、この予定のみ／これ以降／すべて の範囲で消す（§64・Q44）
    func delete(id: UUID, scope: RecurrenceScope) throws {
        guard let occurrence = find(id) else { throw EventRepositoryError.notFound(id) }
        let wasRecurring = occurrence.hasRecurrenceRules
        let removed = occurrenceIDs(sameSeriesAs: id, scope: wasRecurring ? scope : .thisEvent)
        switch (wasRecurring, scope) {
        case (true, .futureEvents):
            try store.remove(occurrence, span: .futureEvents, commit: true)
        case (true, .allEvents):
            let master = (store.calendarItem(withIdentifier: occurrence.calendarItemIdentifier) as? EKEvent) ?? occurrence
            try store.remove(master, span: .futureEvents, commit: true)
        default:
            try store.remove(occurrence, span: .thisEvent, commit: true)
        }
        for removedID in removed {
            setKey(nil, for: removedID)
            links.endUnset.remove(removedID)
        }
        try linksFile.save(links)
        cache.removeAll { removed.contains($0.id) }
    }

    /// 繰り返し予定のシリーズ共通の設定を保存する id。初めて聞かれたシリーズには作って覚える（追加仕様書 §2.7.1）
    func seriesID(of eventID: UUID) -> UUID? {
        guard let key = links.keys[eventID] else { return nil }
        let parsed = EventKitMapping.parseLinkKey(key)
        guard parsed.occurrenceDate != nil else { return nil }
        if let existing = links.seriesIDs?[parsed.itemIdentifier] { return existing }
        let created = UUID()
        var ids = links.seriesIDs ?? [:]
        ids[parsed.itemIdentifier] = created
        links.seriesIDs = ids
        try? linksFile.save(links)
        return created
    }

    /// 同じ繰り返しの、読み込んである回の id（「これ以降」ならその回から後、「すべて」なら全部。その予定自身も含む）
    func occurrenceIDs(sameSeriesAs id: UUID, scope: RecurrenceScope) -> [UUID] {
        guard scope != .thisEvent, let key = links.keys[id] else { return [id] }
        let item = EventKitMapping.parseLinkKey(key).itemIdentifier
        let day = cache.first { $0.id == id }?.day
        let ids = cache.filter { other in
            guard let otherKey = links.keys[other.id],
                  EventKitMapping.parseLinkKey(otherKey).itemIdentifier == item else { return false }
            if scope == .futureEvents, let day { return other.day >= day }
            return true
        }.map(\.id)
        return ids.contains(id) ? ids : [id] + ids
    }

    // MARK: - 内部

    /// 予定の id と Apple カレンダーの予定の鍵を結ぶ（逆引きもそろえる）
    private func setKey(_ key: String?, for id: UUID) {
        if let old = links.keys[id], idByKey[old] == id { idByKey[old] = nil }
        links.keys[id] = key
        if let key { idByKey[key] = id }
    }

    private func setEndUnset(_ event: CalendarEvent) {
        if event.durationMinutes == nil && !event.isAllDay {
            links.endUnset.insert(event.id)
        } else {
            links.endUnset.remove(event.id)
        }
    }

    private func find(_ id: UUID) -> EKEvent? {
        guard let key = links.keys[id] else { return nil }
        let parsed = EventKitMapping.parseLinkKey(key)
        guard let occurrence = parsed.occurrenceDate else {
            return store.calendarItem(withIdentifier: parsed.itemIdentifier) as? EKEvent
        }
        // 繰り返しの予定は、その回の日の予定から探す
        let dayStart = calendar.startOfDay(for: occurrence)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        return store.events(matching: predicate).first {
            $0.calendarItemIdentifier == parsed.itemIdentifier && $0.occurrenceDate == occurrence
        }
    }

    private static func linkKey(for ekEvent: EKEvent) -> String {
        EventKitMapping.linkKey(itemIdentifier: ekEvent.calendarItemIdentifier,
                                occurrenceDate: ekEvent.hasRecurrenceRules ? ekEvent.occurrenceDate : nil)
    }

    /// その予定だけ保存先を変えた（Q32）
    private func moveCalendarIfNeeded(_ ekEvent: EKEvent, to calendarID: String?) {
        if let calendarID, calendarID != ekEvent.calendar?.calendarIdentifier,
           let target = store.calendar(withIdentifier: calendarID), target.allowsContentModifications {
            ekEvent.calendar = target
        }
    }

    private static func record(of ekEvent: EKEvent, store: EKEventStore) -> ExternalEventRecord {
        var rule = ekEvent.recurrenceRules?.first
        // 1 回だけ直した回は、繰り返しの決まりを持たないことがあるので、系列のほうから読む
        if rule == nil, ekEvent.hasRecurrenceRules {
            rule = (store.calendarItem(withIdentifier: ekEvent.calendarItemIdentifier) as? EKEvent)?.recurrenceRules?.first
        }
        return ExternalEventRecord(title: ekEvent.title ?? "",
                                   location: ekEvent.location,
                                   startDate: ekEvent.startDate,
                                   endDate: ekEvent.endDate,
                                   isAllDay: ekEvent.isAllDay,
                                   notes: ekEvent.notes,
                                   repeatRule: EventKitRecurrence.repeatRule(from: rule))
    }

    /// includeRecurrence：繰り返しの決まりも書き換えるか（「この予定のみ」のときは書き換えない）
    private static func apply(_ record: ExternalEventRecord, to ekEvent: EKEvent, includeRecurrence: Bool) {
        ekEvent.title = record.title
        ekEvent.location = record.location
        ekEvent.startDate = record.startDate
        ekEvent.endDate = record.endDate
        ekEvent.isAllDay = record.isAllDay
        // メモは主な入力欄に出さないが、Apple カレンダーにあるものは消さない（§55）
        if let notes = record.notes { ekEvent.notes = notes }
        if includeRecurrence {
            ekEvent.recurrenceRules = EventKitRecurrence.rule(from: record.repeatRule).map { [$0] }
        }
    }

    private static func nearestColor(of ekCalendar: EKCalendar?) -> EventColor {
        guard let color = ekCalendar?.cgColor,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = color.converted(to: space, intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3 else { return .orange }
        return EventColor.nearest(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

enum EventKitRepositoryError: Error {
    /// 新しい予定を入れる Apple カレンダーがない
    case noCalendar
}
