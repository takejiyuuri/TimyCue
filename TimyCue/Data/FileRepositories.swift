import Foundation

/// 端末の中に JSON で保存するファイル 1 つ。読めなければ空から始める（仕様 §80：壊れてもアプリ全体を止めない）
final class JSONFile<Value: Codable> {
    let url: URL
    private let empty: Value

    init(url: URL, empty: Value) {
        self.url = url
        self.empty = empty
    }

    /// アプリのデータの置き場所（Application Support/TimyCue）。iCloud には送らない（生のデータの同期は §78 で決める）
    static func appSupportURL(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TimyCue", isDirectory: true).appendingPathComponent(name)
    }

    func load() -> Value {
        guard let data = try? Data(contentsOf: url) else { return empty }
        return (try? JSONDecoder().decode(Value.self, from: data)) ?? empty
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }
}

/// Apple カレンダーとつないでいない間、TimyCue で作った予定を端末の中に保存する（仕様 §80：カレンダーを許可しなくても使える）
final class FileEventRepository: EventRepository {
    private let file: JSONFile<[CalendarEvent]>
    private var events: [CalendarEvent]

    init(file: JSONFile<[CalendarEvent]> = JSONFile(url: JSONFile<[CalendarEvent]>.appSupportURL(named: "events.json"), empty: [])) {
        self.file = file
        events = file.load()
    }

    func allEvents() -> [CalendarEvent] { events }

    func insert(_ newEvents: [CalendarEvent]) throws {
        events.append(contentsOf: newEvents)
        try file.save(events)
    }

    func update(_ event: CalendarEvent) throws {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else {
            throw EventRepositoryError.notFound(event.id)
        }
        events[index] = event
        try file.save(events)
    }

    func delete(id: UUID) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else {
            throw EventRepositoryError.notFound(id)
        }
        events.remove(at: index)
        try file.save(events)
    }

    /// 全部消す（Apple カレンダーへ移したあと）
    func removeAll() throws {
        events = []
        try file.save(events)
    }
}

/// TimyCue だけが使う情報を、端末の中に保存する（仕様 §68・§84）
final class FileEventMetadataRepository: EventMetadataRepository {
    private let file: JSONFile<[UUID: TimyCueEventMetadata]>
    private var storage: [UUID: TimyCueEventMetadata]

    init(file: JSONFile<[UUID: TimyCueEventMetadata]> = JSONFile(url: JSONFile<[UUID: TimyCueEventMetadata]>.appSupportURL(named: "metadata.json"), empty: [:])) {
        self.file = file
        storage = file.load()
    }

    func allMetadata() -> [UUID: TimyCueEventMetadata] { storage }

    func save(_ metadata: TimyCueEventMetadata, for eventID: UUID) throws {
        storage[eventID] = metadata
        try file.save(storage)
    }

    func delete(for eventID: UUID) throws {
        storage[eventID] = nil
        try file.save(storage)
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
    func update(_ event: CalendarEvent) throws { try current.update(event) }
    func delete(id: UUID) throws { try current.delete(id: id) }
}
