import Foundation
import Observation

/// カレンダータブの中で移る先。予定詳細は別の画面にせず吹き出しで出す（Q27）
enum CalendarRoute: Hashable {
    /// 1 日タイムライン（仕様 §25）
    case timeline(CalendarDay)
}

/// 予定詳細の吹き出しの「編集」から開く 3 分割画面（Q30）
struct EditRequest: Identifiable, Equatable {
    let id: UUID
    /// 下カレンダーを最初に出す月
    let month: CalendarMonth
}

/// 1 日タイムラインでスクロールして見せる位置
struct TimelineFocus: Equatable {
    let day: CalendarDay
    let minute: MinuteOfDay
}

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
    /// 月カレンダーの吹き出しで、一覧から予定詳細に切り替えている日と予定（Q28(a)）
    private(set) var popoverDetails: [CalendarDay: UUID] = [:]
    /// 1 日タイムラインで予定詳細の吹き出しを出している予定（Q28(b)）
    private(set) var timelineDetailEventID: UUID?
    /// 予定詳細の吹き出しの「編集」で開く 3 分割画面（Q30）。閉じたら nil に戻るので外から書ける
    var editRequest: EditRequest?
    /// カレンダータブの中の画面の行き来（1 日タイムライン）。戻る操作で書き換わるので外から書ける
    var path: [CalendarRoute] = []
    /// 1 日タイムラインの「＋」から保存したあと、作った予定が見える位置までスクロールする目印（Q22）
    private(set) var timelineFocus: TimelineFocus?
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

    /// その日の時刻のある予定（開始時刻順）。1 日タイムラインの 0:00〜24:00 に置く（仕様 §26）
    func timedEvents(on day: CalendarDay) -> [CalendarEvent] {
        events(on: day).filter { !$0.isAllDay }
    }

    /// その日の終日の予定。タイムラインの上の終日専用帯に出す（仕様 §30）
    func allDayEvents(on day: CalendarDay) -> [CalendarEvent] {
        events(on: day).filter(\.isAllDay)
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
            popoverDetails[day] = nil
            return
        }
        openDays.append(day)
        if openDays.count > Self.maxOpenPopovers {
            let closed = openDays.prefix(openDays.count - Self.maxOpenPopovers)
            closed.forEach { popoverDetails[$0] = nil }
            openDays.removeFirst(closed.count)
        }
    }

    /// 吹き出しの外を押したとき、開いている吹き出しを閉じる。予定詳細に切り替えていても一覧へ戻さず、まとめて閉じる（Q9・Q29）
    func closeAllPopovers() {
        guard !openDays.isEmpty else { return }
        openDays = []
        popoverDetails = [:]
    }

    /// 一覧の予定を押す：別の吹き出しを重ねず、同じ吹き出しの中身を予定詳細に切り替える（Q28(a)）
    func showDetail(in day: CalendarDay, eventID: UUID) {
        guard isOpen(day) else { return }
        popoverDetails[day] = eventID
    }

    /// 予定詳細の吹き出しの中をもう一度押すと、元の予定一覧へ戻る（Q29）
    func backToList(in day: CalendarDay) {
        popoverDetails[day] = nil
    }

    /// その日の吹き出しで出している予定詳細。一覧のときは nil
    func detailEventID(inPopoverOf day: CalendarDay) -> UUID? {
        popoverDetails[day]
    }

    // MARK: - 1 日タイムライン

    /// 吹き出しの上の日付を押して、その日の 1 日タイムラインへ移る（仕様 §25）
    func openTimeline(_ day: CalendarDay) {
        timelineDetailEventID = nil
        path = [.timeline(day)]
    }

    /// 予定ブロックを押す：そのブロックの近くに予定詳細の吹き出しを出す（Q17・Q28(b)）。
    /// 出している予定をもう一度押したら閉じる（仮）。3 分割の編集画面へは直接行かない
    func tapTimelineEvent(_ eventID: UUID) {
        timelineDetailEventID = timelineDetailEventID == eventID ? nil : eventID
    }

    /// 吹き出しの外を押したとき、予定詳細の吹き出しを閉じる（Q29）
    func closeTimelineDetail() {
        timelineDetailEventID = nil
    }

    // MARK: - 編集（Q30）

    /// 予定詳細の吹き出しの「編集」：3 分割画面を開く。閉じたら元の画面に戻り、吹き出しもそのまま出す
    func requestEdit(_ eventID: UUID) {
        guard let event = event(id: eventID) else { return }
        editRequest = EditRequest(id: eventID, month: CalendarMonth(event.day))
    }

    // MARK: - 新規予定（Q21・Q22）

    /// 月カレンダーの「＋」で最初に選ぶ日。選択中の日（いちばん新しく開いた吹き出しの日）があればその日、なければ今日（Q21）
    var dayForNewEvent: CalendarDay {
        openDays.last ?? today
    }

    /// 月カレンダーの「＋」から保存したあと：保存した日を選択状態にして、その日の吹き出しを開く。
    /// 複数日なら最初の日を代表にする（Q22）
    func showSavedDay(_ day: CalendarDay) {
        reload()
        if !isOpen(day) { tapDay(day) }
    }

    /// 1 日タイムラインの「＋」から保存したあと：作った予定が見える位置までスクロールする（Q22）
    func focusTimeline(on day: CalendarDay, minute: MinuteOfDay) {
        reload()
        timelineFocus = TimelineFocus(day: day, minute: minute)
    }

    /// タイムラインがスクロールし終えたら目印を消す
    func clearTimelineFocus() {
        timelineFocus = nil
    }

    /// 予定を消したあと、その予定詳細の吹き出しを閉じる（月カレンダーの吹き出しは一覧に戻す）
    func closeEventDetail(_ eventID: UUID) {
        for (day, id) in popoverDetails where id == eventID {
            popoverDetails[day] = nil
        }
        if timelineDetailEventID == eventID { timelineDetailEventID = nil }
    }

    // MARK: - 予定詳細

    func event(id: UUID) -> CalendarEvent? {
        eventsByDay.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    /// TimyCue の情報。まだない予定（Apple カレンダーから来たばかりなど）は nil
    func metadata(for eventID: UUID) -> TimyCueEventMetadata? {
        metadataByEventID[eventID]
    }

    // MARK: - 内部

    /// 吹き出しの時刻（Q12）。終了時刻があれば「10:00–11:30」、なければ「10:00」。終日は「終日」。
    /// Apple カレンダーに保存するために付ける仮の終了時刻は、終了時刻として持たないので出ない（§69）
    nonisolated static func timeText(for event: CalendarEvent) -> String {
        if event.isAllDay { return "終日" }
        let start = TimeText.hourMinute(event.startMinute)
        guard let end = event.endMinute else { return start }
        return "\(start)–\(TimeText.hourMinute(end))"
    }

    nonisolated private static func displayOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        (lhs.isAllDay ? 0 : 1, lhs.startMinute, lhs.displayTitle) < (rhs.isAllDay ? 0 : 1, rhs.startMinute, rhs.displayTitle)
    }
}
