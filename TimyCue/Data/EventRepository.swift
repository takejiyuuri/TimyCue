import Foundation

/// 予定（Apple カレンダーと共有する部分）の読み書き。今はモック、第4段階で EventKit 版に差し替える（仕様 §68）。
protocol EventRepository: AnyObject {
    /// 読み込んである予定
    func allEvents() -> [CalendarEvent]
    func insert(_ events: [CalendarEvent]) throws
    func update(_ event: CalendarEvent) throws
    func delete(id: UUID) throws
    /// その期間の予定を読み込んでおく。Apple カレンダーは表示に必要な範囲だけ、必要になったときに読む（Q35）
    func ensureLoaded(from start: CalendarDay, to end: CalendarDay)
    /// 繰り返し予定を、範囲を決めて直す・消す（Q44）。繰り返しを持たない保存先では、ふつうに直す・消す
    func update(_ event: CalendarEvent, scope: RecurrenceScope) throws
    func delete(id: UUID, scope: RecurrenceScope) throws
    /// その予定と同じ繰り返しの、読み込んである回の id（範囲が「これ以降」ならその回から後、「すべて」なら全部。その予定自身も含む）
    func occurrenceIDs(sameSeriesAs id: UUID, scope: RecurrenceScope) -> [UUID]
    /// 繰り返し予定のシリーズ全体の共通設定を保存する id（追加仕様書 §2.7.1）。繰り返しでない・繰り返しを持たない保存先では nil
    func seriesID(of eventID: UUID) -> UUID?
}

extension EventRepository {
    /// 全部を手元に持っている保存先では何もしない
    func ensureLoaded(from start: CalendarDay, to end: CalendarDay) {}
    func update(_ event: CalendarEvent, scope: RecurrenceScope) throws { try update(event) }
    func delete(id: UUID, scope: RecurrenceScope) throws { try delete(id: id) }
    func occurrenceIDs(sameSeriesAs id: UUID, scope: RecurrenceScope) -> [UUID] { [id] }
    func seriesID(of eventID: UUID) -> UUID? { nil }
}

/// TimyCue だけが使う情報の読み書き（仕様 §84）。Apple カレンダーの予定とは別に保存する（仕様 §68）。
/// 予定の id で結びつける。EventKit に移るときに、Apple カレンダー側の識別子との対応を決める。
protocol EventMetadataRepository: AnyObject {
    func allMetadata() -> [UUID: TimyCueEventMetadata]
    func save(_ metadata: TimyCueEventMetadata, for eventID: UUID) throws
    /// まとめて保存する（Apple カレンダーの予定を何百件も初めて読んだときに、1 件ずつ書かないように）
    func saveAll(_ entries: [UUID: TimyCueEventMetadata]) throws
    func delete(for eventID: UUID) throws
}

extension EventMetadataRepository {
    func saveAll(_ entries: [UUID: TimyCueEventMetadata]) throws {
        for (id, metadata) in entries { try save(metadata, for: id) }
    }
}

enum EventRepositoryError: Error, Equatable {
    case notFound(UUID)
}

/// メモリの中だけに予定を持つ版。見本の予定（審査でも何か触れるように）を最初から入れておける。
final class InMemoryEventRepository: EventRepository {
    private var events: [CalendarEvent]

    init(events: [CalendarEvent] = []) {
        self.events = events
    }

    func allEvents() -> [CalendarEvent] {
        events
    }

    func insert(_ newEvents: [CalendarEvent]) throws {
        events.append(contentsOf: newEvents)
    }

    func update(_ event: CalendarEvent) throws {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else {
            throw EventRepositoryError.notFound(event.id)
        }
        events[index] = event
    }

    func delete(id: UUID) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else {
            throw EventRepositoryError.notFound(id)
        }
        events.remove(at: index)
    }
}

/// メモリの中だけに TimyCue の情報を持つ版
final class InMemoryEventMetadataRepository: EventMetadataRepository {
    private var storage: [UUID: TimyCueEventMetadata]

    init(metadata: [UUID: TimyCueEventMetadata] = [:]) {
        storage = metadata
    }

    func allMetadata() -> [UUID: TimyCueEventMetadata] {
        storage
    }

    func save(_ metadata: TimyCueEventMetadata, for eventID: UUID) throws {
        storage[eventID] = metadata
    }

    func delete(for eventID: UUID) throws {
        storage[eventID] = nil
    }
}
