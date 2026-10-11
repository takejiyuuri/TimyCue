import Foundation

/// 予定の読み書き。今はモック、後で EventKit（Apple カレンダー）版に差し替える（仕様 §44・§49）。
protocol EventRepository: AnyObject {
    func allEvents() -> [CalendarEvent]
    func insert(_ events: [CalendarEvent]) throws
    func update(_ event: CalendarEvent) throws
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
}
