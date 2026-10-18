import Foundation

/// 端末の中に JSON で保存するファイル 1 つ。読めなければ空から始める（仕様 §80：壊れてもアプリ全体を止めない）。
/// 書くときは一時ファイルに書いてから置き換える（途中で終わっても前のファイルが壊れない）。
/// 中身が読めない（壊れた・形が合わない）ファイルは、空として上書きする前に別名で残す。ファイルそのものを開けない
/// （端末のロック中など）ときは、空で上書きしないよう、そのあいだの保存を失敗にする（spec §89.9・2026-10-18 S1b）
final class JSONFile<Value: Codable> {
    let url: URL
    private let empty: Value
    /// 保存のときに失敗を再現する場所（検証用のビルドだけ。spec §89.9）
    var faultPoint: SaveFault?
    /// 中身が読めなかったので別名で残したファイル
    private(set) var unreadableBackup: URL?
    /// ファイルはあるのに開けなかった。このあいだは上書きしない
    private(set) var couldNotOpen = false

    init(url: URL, empty: Value, faultPoint: SaveFault? = nil) {
        self.url = url
        self.empty = empty
        self.faultPoint = faultPoint
    }

    /// アプリのデータの置き場所（Application Support/TimyCue）。iCloud には送らない（生のデータの同期は §78 で決める）
    static func appSupportURL(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TimyCue", isDirectory: true).appendingPathComponent(name)
    }

    func load() -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else { return empty }
        guard let data = try? Data(contentsOf: url) else {
            couldNotOpen = true
            return empty
        }
        couldNotOpen = false
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            backUpUnreadable()
            return empty
        }
    }

    func save(_ value: Value) throws {
        try SaveFaults.check(faultPoint)
        // 開けなかったファイルを空の中身で上書きしない（中身を失わないため）
        guard !couldNotOpen else { throw JSONFileError.couldNotOpen(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// 中身が読めなかったファイルを、日時を付けた別名で残す（あとで調べたり戻したりできるように）
    private func backUpUnreadable() {
        let stamp = Self.backupStamp.string(from: Date())
        let backup = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).unreadable-\(stamp)")
        if (try? FileManager.default.copyItem(at: url, to: backup)) != nil {
            unreadableBackup = backup
        }
    }

    private static var backupStamp: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }
}

/// Apple カレンダーとつないでいない間、TimyCue で作った予定を端末の中に保存する（仕様 §80：カレンダーを許可しなくても使える）。
/// ファイルに書けてから、メモリを変える。書けなければ何も変わらない（失敗を成功にしない・押し直しで重複しない・
/// 消したはずの予定が再起動で戻らない。spec §89.9・2026-10-18 S1b）
final class FileEventRepository: EventRepository {
    private let file: JSONFile<[CalendarEvent]>
    private var events: [CalendarEvent]

    init(file: JSONFile<[CalendarEvent]> = JSONFile(url: JSONFile<[CalendarEvent]>.appSupportURL(named: "events.json"), empty: [],
                                                    faultPoint: .localEventsWrite)) {
        self.file = file
        events = file.load()
    }

    func allEvents() -> [CalendarEvent] { events }

    /// 同じ id の予定がもうあれば足さない（押し直しで同じ予定を重複させない）
    func insert(_ newEvents: [CalendarEvent]) throws {
        let known = Set(events.map(\.id))
        let adding = newEvents.filter { !known.contains($0.id) }
        guard !adding.isEmpty else { return }
        let next = events + adding
        try file.save(next)
        events = next
    }

    func update(_ event: CalendarEvent) throws {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else {
            throw EventRepositoryError.notFound(event.id)
        }
        var next = events
        next[index] = event
        try file.save(next)
        events = next
    }

    func delete(id: UUID) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else {
            throw EventRepositoryError.notFound(id)
        }
        var next = events
        next.remove(at: index)
        try file.save(next)
        events = next
    }
}

/// TimyCue だけが使う情報を、端末の中に保存する（仕様 §68・§84）。ファイルに書けてから、メモリを変える（spec §89.9）
final class FileEventMetadataRepository: EventMetadataRepository {
    private let file: JSONFile<[UUID: TimyCueEventMetadata]>
    private var storage: [UUID: TimyCueEventMetadata]

    /// 失敗の再現（.metadataWrite）は、予定を書いたあとの設定の保存（ScheduleEditorStore）で行う。
    /// ここに置くと、読み込みのときの初期値の保存が先に失敗を使ってしまう
    init(file: JSONFile<[UUID: TimyCueEventMetadata]> = JSONFile(url: JSONFile<[UUID: TimyCueEventMetadata]>.appSupportURL(named: "metadata.json"),
                                                                 empty: [:])) {
        self.file = file
        storage = file.load()
    }

    func allMetadata() -> [UUID: TimyCueEventMetadata] { storage }

    func save(_ metadata: TimyCueEventMetadata, for eventID: UUID) throws {
        var next = storage
        next[eventID] = metadata
        try file.save(next)
        storage = next
    }

    /// ファイルへは 1 回だけ書く
    func saveAll(_ entries: [UUID: TimyCueEventMetadata]) throws {
        guard !entries.isEmpty else { return }
        let next = storage.merging(entries) { _, new in new }
        try file.save(next)
        storage = next
    }

    func delete(for eventID: UUID) throws {
        guard storage[eventID] != nil else { return }
        var next = storage
        next[eventID] = nil
        try file.save(next)
        storage = next
    }

    /// ファイルへは 1 回だけ書く
    func deleteAll(_ eventIDs: Set<UUID>) throws {
        guard eventIDs.contains(where: { storage[$0] != nil }) else { return }
        var next = storage
        for id in eventIDs { next[id] = nil }
        try file.save(next)
        storage = next
    }
}

/// 予定の保存先を、あとから切り替えられるようにする包み（Apple カレンダーとつないだら切り替える）
final class SwitchableEventRepository: EventRepository {
    private(set) var current: EventRepository

    init(_ initial: EventRepository) {
        current = initial
    }

    func use(_ repository: EventRepository) {
        current = repository
    }

    func allEvents() -> [CalendarEvent] { current.allEvents() }
    func insert(_ events: [CalendarEvent]) throws { try current.insert(events) }
    func insertEach(_ events: [CalendarEvent]) -> InsertReport { current.insertEach(events) }
    func update(_ event: CalendarEvent) throws { try current.update(event) }
    func delete(id: UUID) throws { try current.delete(id: id) }
    func ensureLoaded(from start: CalendarDay, to end: CalendarDay) { current.ensureLoaded(from: start, to: end) }
    func update(_ event: CalendarEvent, scope: RecurrenceScope) throws { try current.update(event, scope: scope) }
    func delete(id: UUID, scope: RecurrenceScope) throws { try current.delete(id: id, scope: scope) }
    func occurrenceIDs(sameSeriesAs id: UUID, scope: RecurrenceScope) -> [UUID] {
        current.occurrenceIDs(sameSeriesAs: id, scope: scope)
    }
    func seriesID(of eventID: UUID) -> UUID? { current.seriesID(of: eventID) }
    var hasUnsavedLinks: Bool { current.hasUnsavedLinks }
    var managesAppleLinks: Bool { current.managesAppleLinks }
    func containsEvent(id: UUID) -> Bool { current.containsEvent(id: id) }
}

/// Apple カレンダーとつないだあとの保存先。Apple カレンダーの予定と、つなぐ前から TimyCue の中にあった予定の両方を見せる。
/// つないでも TimyCue の中の予定を勝手に Apple カレンダーへ移したり複製したりしない（Q34）。
/// 新しく作る予定は Apple カレンダーへ。直す・消すは、その予定がある方で行う
final class CombinedEventRepository: EventRepository {
    private let primary: EventRepository
    private let local: EventRepository

    init(primary: EventRepository, local: EventRepository) {
        self.primary = primary
        self.local = local
    }

    func allEvents() -> [CalendarEvent] { primary.allEvents() + local.allEvents() }
    func insert(_ events: [CalendarEvent]) throws { try primary.insert(events) }
    func insertEach(_ events: [CalendarEvent]) -> InsertReport { primary.insertEach(events) }

    func update(_ event: CalendarEvent) throws {
        try update(event, scope: .thisEvent)
    }

    func delete(id: UUID) throws {
        try delete(id: id, scope: .thisEvent)
    }

    func update(_ event: CalendarEvent, scope: RecurrenceScope) throws {
        if local.allEvents().contains(where: { $0.id == event.id }) {
            try local.update(event)
        } else {
            try primary.update(event, scope: scope)
        }
    }

    func delete(id: UUID, scope: RecurrenceScope) throws {
        if local.allEvents().contains(where: { $0.id == id }) {
            try local.delete(id: id)
        } else {
            try primary.delete(id: id, scope: scope)
        }
    }

    func occurrenceIDs(sameSeriesAs id: UUID, scope: RecurrenceScope) -> [UUID] {
        local.allEvents().contains(where: { $0.id == id }) ? [id] : primary.occurrenceIDs(sameSeriesAs: id, scope: scope)
    }

    func seriesID(of eventID: UUID) -> UUID? {
        local.allEvents().contains(where: { $0.id == eventID }) ? nil : primary.seriesID(of: eventID)
    }

    var hasUnsavedLinks: Bool { primary.hasUnsavedLinks }
    var managesAppleLinks: Bool { primary.managesAppleLinks }
    func containsEvent(id: UUID) -> Bool { primary.containsEvent(id: id) || local.containsEvent(id: id) }

    func ensureLoaded(from start: CalendarDay, to end: CalendarDay) {
        primary.ensureLoaded(from: start, to: end)
        local.ensureLoaded(from: start, to: end)
    }
}
