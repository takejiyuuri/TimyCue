import Foundation
import Observation

/// 日付吹き出しの 1 行（仕様 §22）
struct DayPopoverRow: Identifiable, Equatable {
    let id: UUID
    /// 開始時刻。終日は「終日」
    let timeText: String
    /// 主表示：予定名。予定名がなければ場所名（Q3 のフォールバック）
    let primary: String
    /// 補助表示：場所。予定名がないときは場所を主表示にするので出さない
    let secondary: String?
    let color: EventColor
}

/// カレンダータブの状態（仕様 §18〜§24）。予定を俯瞰・確認するだけで、編集はしない（仕様 §18）。
@MainActor
@Observable
final class CalendarStore {
    /// 吹き出しは最大 2 つ（仕様 §23）
    static let maxOpenPopovers = 2
    /// 縦に並べる月の範囲（今月の前後。仮の値）
    static let monthsBefore = 12
    static let monthsAfter = 24

    private(set) var today: CalendarDay
    private(set) var months: [CalendarMonth]
    /// 吹き出しを開いている日。古い順（仕様 §23）
    private(set) var openDays: [CalendarDay] = []
    private var eventsByDay: [CalendarDay: [CalendarEvent]] = [:]
    private var metadataByEventID: [UUID: TimyCueEventMetadata] = [:]

    @ObservationIgnored private let repository: EventRepository
    @ObservationIgnored private let metadataRepository: EventMetadataRepository

    init(repository: EventRepository,
         metadataRepository: EventMetadataRepository,
         today: CalendarDay = CalendarDay(Date())) {
        self.repository = repository
        self.metadataRepository = metadataRepository
        self.today = today
        months = CalendarMonth.range(around: CalendarMonth(today), before: Self.monthsBefore, after: Self.monthsAfter)
        reload()
    }

    var currentMonth: CalendarMonth { CalendarMonth(today) }

    /// 予定を読み直す（予定を保存したあとなど）
    func reload() {
        metadataByEventID = metadataRepository.allMetadata()
        eventsByDay = Dictionary(grouping: repository.allEvents(), by: \.day)
            .mapValues { $0.sorted(by: Self.displayOrder) }
    }

    /// 日付が変わったときに「今日」を更新する
    func updateToday(_ day: CalendarDay = CalendarDay(Date())) {
        guard day != today else { return }
        today = day
        months = CalendarMonth.range(around: CalendarMonth(day), before: Self.monthsBefore, after: Self.monthsAfter)
    }

    // MARK: - 読み取り

    /// その日の予定。終日 → 開始時刻順（仕様 §22。終日を先にするのは仮）
    func events(on day: CalendarDay) -> [CalendarEvent] {
        eventsByDay[day] ?? []
    }

    /// 予定の色。TimyCue の情報がない予定（Apple カレンダーから来たばかりなど）は仮にオレンジ。
    /// Apple カレンダー由来の色を初期候補にするのは第4段階（仕様 §53）
    func color(for event: CalendarEvent) -> EventColor {
        metadataByEventID[event.id]?.color ?? .orange
    }

    /// セルに出す予定（仕様 §21）
    func summary(on day: CalendarDay) -> DayCellSummary {
        DayCellSummary(marks: events(on: day).map { EventMark(title: $0.displayTitle, color: color(for: $0)) })
    }

    /// 吹き出しの中身（仕様 §22）
    func popoverRows(on day: CalendarDay) -> [DayPopoverRow] {
        events(on: day).map { event in
            let hasTitle = !event.title.isEmpty
            let place = event.locationName.flatMap { $0.isEmpty ? nil : $0 }
            return DayPopoverRow(id: event.id,
                                 timeText: event.isAllDay ? "終日" : TimeText.hourMinute(event.startMinute),
                                 primary: event.displayTitle,
                                 secondary: hasTitle ? place : nil,
                                 color: color(for: event))
        }
    }

    func isOpen(_ day: CalendarDay) -> Bool {
        openDays.contains(day)
    }

    // MARK: - 吹き出し

    /// 日付を押す（仕様 §22・§23）。1 つ目・2 つ目は開く。3 つ目は古い方を閉じて入れ替える。
    /// 開いている日をもう一度押したら閉じる（仕様にないので仮）
    func tapDay(_ day: CalendarDay) {
        if let index = openDays.firstIndex(of: day) {
            openDays.remove(at: index)
            return
        }
        openDays.append(day)
        if openDays.count > Self.maxOpenPopovers {
            openDays.removeFirst(openDays.count - Self.maxOpenPopovers)
        }
    }

    func closeAllPopovers() {
        openDays = []
    }

    // MARK: - 内部

    nonisolated private static func displayOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        (lhs.isAllDay ? 0 : 1, lhs.startMinute, lhs.displayTitle) < (rhs.isAllDay ? 0 : 1, rhs.startMinute, rhs.displayTitle)
    }
}
