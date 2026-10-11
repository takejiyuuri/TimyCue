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
    /// 最初に並べる週の数と、端に近づいたときに足す週の数（Q13：見える範囲は固定しない）
    static let initialWeeksBefore = 26
    static let initialWeeksAfter = 52
    static let weeksPerExtension = 26
    /// 端に何週まで近づいたら足すか
    static let extensionThreshold = 6
    /// 内部の安全上限（今日から前後それぞれ約 100 年）。ふつうの使い方では届かない
    static let maxWeeksFromToday = 52 * 100

    private(set) var today: CalendarDay
    /// 縦に並べている週（古い順）。スクロールしていく方向へ順に足す（Q13）
    private(set) var weeks: [CalendarWeek]
    /// 一番上に見えている週の月曜。スクロール位置と結びつける（Q19・Q20 の固定表示に使う）
    var topWeekID: CalendarDay?
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
        let initialTop = CalendarWeek(containing: CalendarMonth(today).firstDay)
        weeks = Self.weeks(around: CalendarWeek(containing: today))
        topWeekID = initialTop.id
        reload()
    }

    var currentMonth: CalendarMonth { CalendarMonth(today) }

    /// 一番上に見えている週
    var topWeek: CalendarWeek {
        CalendarWeek(containing: topWeekID ?? CalendarMonth(today).firstDay)
    }

    /// 月表示列の上に固定表示する月（Q19）と、画面上部の年（Q20）
    var stickyMonth: CalendarMonth { topWeek.stickyMonth }

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
        let todayWeek = CalendarWeek(containing: day)
        if let first = weeks.first, let last = weeks.last, !(first...last).contains(todayWeek) {
            weeks = Self.weeks(around: todayWeek)
        }
    }

    // MARK: - 週の追加（Q13）

    /// 週が画面に出たとき。端に近づいていたら、その方向へ週を足す
    func weekDidAppear(_ week: CalendarWeek) {
        guard let index = weeks.firstIndex(of: week) else { return }
        if index < Self.extensionThreshold { extendBefore() }
        if index >= weeks.count - Self.extensionThreshold { extendAfter() }
    }

    func extendBefore() {
        guard let first = weeks.first else { return }
        let limit = CalendarWeek(containing: today).adding(weeks: -Self.maxWeeksFromToday)
        let added = (1...Self.weeksPerExtension).map { first.adding(weeks: -$0) }.filter { $0 >= limit }.reversed()
        weeks.insert(contentsOf: added, at: 0)
    }

    func extendAfter() {
        guard let last = weeks.last else { return }
        let limit = CalendarWeek(containing: today).adding(weeks: Self.maxWeeksFromToday)
        let added = (1...Self.weeksPerExtension).map { last.adding(weeks: $0) }.filter { $0 <= limit }
        weeks.append(contentsOf: added)
    }

    private static func weeks(around center: CalendarWeek) -> [CalendarWeek] {
        (-initialWeeksBefore...initialWeeksAfter).map { center.adding(weeks: $0) }
    }

    // MARK: - 読み取り

    /// その日の予定。終日 → 時間指定の予定を開始時刻順（仕様 §22・Q8）
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
                                 timeText: Self.timeText(for: event),
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
    /// 開いている日をもう一度押したら閉じる（Q9）
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

    /// 吹き出しの外を押したとき、開いている吹き出しを閉じる（Q9）
    func closeAllPopovers() {
        guard !openDays.isEmpty else { return }
        openDays = []
    }

    // MARK: - 内部

    /// 吹き出しの時刻（Q12）。終了時刻があれば「10:00–11:30」、なければ「10:00」。終日は「終日」。
    /// Apple カレンダーに保存するために付ける仮の終了時刻は、終了時刻として持たないので出ない（§69）
    static func timeText(for event: CalendarEvent) -> String {
        if event.isAllDay { return "終日" }
        let start = TimeText.hourMinute(event.startMinute)
        guard let end = event.endMinute else { return start }
        return "\(start)–\(TimeText.hourMinute(end))"
    }

    nonisolated private static func displayOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        (lhs.isAllDay ? 0 : 1, lhs.startMinute, lhs.displayTitle) < (rhs.isAllDay ? 0 : 1, rhs.startMinute, rhs.displayTitle)
    }
}
