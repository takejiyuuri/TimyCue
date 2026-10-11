import Foundation
import Observation

/// 予定登録・編集・コピーの 3 分割画面の状態（仕様 §31〜§66）。
/// 画面（View）は表示と操作の受け渡しだけにして、決まりごとはすべてここに置く。
///
/// 日付はタップで 1 日ずつ選ぶ（仕様 §34）。もう一度タップしたら外すのか、なぞって選ぶときの細かな扱いは
/// 画面を作る段階で確かめるので、ここでは「選ぶ」「外す」「表示する日を変える」を別々の操作として用意する。
@MainActor
@Observable
final class ScheduleEditorStore {
    private(set) var mode: EditorMode = .new
    /// 予定を登録する日（新規・コピーは複数、編集は 1 日）。日付順
    private(set) var selectedDays: [CalendarDay] = []
    /// 左上の時間画面に出している日（1 日。仕様 §35 の日付タブで切り替える）
    private(set) var displayedDay: CalendarDay?
    /// 日ごとの開始時刻（仕様 §36：日ごとに違ってよい）
    private(set) var startMinutes: [CalendarDay: MinuteOfDay] = [:]
    /// 全部の日に共通の所要時間（Q1：最初に入れた値が全部の日に入る）。nil は終了未設定
    private(set) var commonDurationMinutes: Int?
    /// その日だけ変えた所要時間（Q1）。値が nil の日は、その日だけ終了未設定
    private(set) var durationOverrides: [CalendarDay: Int?] = [:]
    /// 右上の入力欄の中身
    var content = EventContent()
    /// 右上で開いている行（仕様 §45：同時に 1 行だけ）
    private(set) var expandedRow: InputRow?
    private(set) var predictionState: PredictionState = .idle
    private(set) var events: [CalendarEvent] = []
    private(set) var metadataByEventID: [UUID: TimyCueEventMetadata] = [:]

    /// 保存しようとして足りないものがあったか。あったら、直るまで知らせを出し続ける（仕様 §46）
    private var showsSaveIssue = false

    @ObservationIgnored private let repository: EventRepository
    @ObservationIgnored private let metadataRepository: EventMetadataRepository
    @ObservationIgnored private let predictor: PredictionService
    @ObservationIgnored private var baseline = Snapshot()

    init(repository: EventRepository,
         metadataRepository: EventMetadataRepository,
         predictor: PredictionService = SameTitlePredictionService()) {
        self.repository = repository
        self.metadataRepository = metadataRepository
        self.predictor = predictor
        reloadEvents()
        baseline = snapshot
    }

    // MARK: - 読み取り

    /// 編集中・コピー元の予定
    var editingEvent: CalendarEvent? {
        switch mode {
        case .new: nil
        case .edit(let id), .copy(let id): events.first { $0.id == id }
        }
    }

    /// 保存済みの予定の TimyCue の情報。Apple カレンダーから来たばかりの予定などは nil
    func metadata(for eventID: UUID) -> TimyCueEventMetadata? {
        metadataByEventID[eventID]
    }

    /// その日の保存済みの予定（終日を除き、開始時刻順）。編集中の予定は仮予定として別に出すので含めない
    func timedEvents(on day: CalendarDay) -> [CalendarEvent] {
        var hiddenID: UUID?
        if case .edit(let id) = mode { hiddenID = id }
        return events
            .filter { $0.day == day && !$0.isAllDay && $0.id != hiddenID }
            .sorted { $0.startMinute < $1.startMinute }
    }

    func allDayEvents(on day: CalendarDay) -> [CalendarEvent] {
        events.filter { $0.day == day && $0.isAllDay }
    }

    /// 保存前の仮予定（時刻が決まっている日の分だけ。仕様 §39）
    var draftEvents: [CalendarEvent] {
        selectedDays.compactMap { day in
            guard let start = startMinutes[day] else { return nil }
            return content.makeEvent(day: day, startMinute: start, durationMinutes: durationMinutes(on: day))
        }
    }

    /// 時間画面の初期位置の目安（仕様 §43 の「予定がある日は最初の予定の少し前」）。
    /// 予定がない日の扱い（今日は現在時刻付近、未来日は適切な時間帯）は画面側で決める
    func suggestedScrollMinute(for day: CalendarDay, leadMinutes: Int = 30) -> MinuteOfDay? {
        let starts = timedEvents(on: day).map(\.startMinute) + [startMinutes[day]].compactMap { $0 }
        return starts.min().map { max(0, $0 - leadMinutes) }
    }

    /// 右上に出す行。ルートは移動手段が車のときだけ（仕様 §52）
    var visibleRows: [InputRow] {
        InputRow.allCases.filter { $0 != .route || content.metadata.transport == .car }
    }

    /// 保存に足りないもの。日付 → 開始時刻 → 予定名 の順（仕様 §46・§87）
    var saveIssues: [SaveIssue] {
        var issues: [SaveIssue] = []
        if selectedDays.isEmpty {
            issues.append(.noDaySelected)
        } else {
            let missing = selectedDays.filter { startMinutes[$0] == nil }
            if !missing.isEmpty { issues.append(.missingStartTime(missing)) }
        }
        if requiresTitle && Self.isBlank(content.title) {
            issues.append(.missingTitle)
        }
        return issues
    }

    /// 予定名が必須か（Q3・Q4）。TimyCue で新しく作る予定（新規・コピー）は必須。
    /// 編集では、元から予定名がない予定（Apple カレンダーから来たものなど）だけ必須にしない
    var requiresTitle: Bool {
        switch mode {
        case .new, .copy: true
        case .edit: !Self.isBlank(editingEvent?.title ?? "")
        }
    }

    /// 保存しようとして足りなかったとき、直るまで出しておく知らせ（仕様 §46）
    var presentedIssue: SaveIssue? {
        showsSaveIssue ? saveIssues.first : nil
    }

    /// 保存ボタンの文言（仕様 §60・§61・§62）
    var saveButtonTitle: String {
        let count = max(selectedDays.count, 1)
        switch mode {
        case .new: return count == 1 ? "保存" : "\(count)件保存"
        case .edit: return "変更を保存"
        case .copy: return count == 1 ? "コピーを保存" : "\(count)件コピー"
        }
    }

    /// 未保存の変更があるか（仕様 §66）
    var hasUnsavedChanges: Bool {
        snapshot != baseline
    }

    // MARK: - モードの切り替え

    /// 新規を始める。最初にどの日を選んでおくかは仕様にないので、呼ぶ側が渡す
    func startNew(on day: CalendarDay? = nil) {
        mode = .new
        content = EventContent()
        selectedDays = []
        startMinutes = [:]
        commonDurationMinutes = nil
        durationOverrides = [:]
        displayedDay = day
        resetTransientState()
        if let day { selectedDays = [day] }
        baseline = snapshot
    }

    /// 既存予定の編集を始める（仕様 §42・§61）
    func startEditing(eventID: UUID) throws {
        guard let event = events.first(where: { $0.id == eventID }) else {
            throw ScheduleEditorError.eventNotFound(eventID)
        }
        mode = .edit(eventID: eventID)
        content = EventContent(event: event, metadata: metadataByEventID[eventID] ?? TimyCueEventMetadata())
        selectedDays = [event.day]
        startMinutes = [event.day: event.startMinute]
        commonDurationMinutes = event.durationMinutes
        durationOverrides = [:]
        displayedDay = event.day
        resetTransientState()
        baseline = snapshot
    }

    /// 編集中の予定からコピーを始める（仕様 §62・§63）。元の予定は変えない。
    /// 日付と開始時刻は引き継がない。所要時間は引き継ぐ。編集中に直した中身は、そのままコピーの中身になる
    func startCopy() throws {
        guard case .edit(let id) = mode else { throw ScheduleEditorError.copyRequiresEditMode }
        let duration = selectedDays.first.flatMap { durationMinutes(on: $0) } ?? commonDurationMinutes
        mode = .copy(sourceID: id)
        content = content.copiedForNewEvent()
        selectedDays = []
        startMinutes = [:]
        commonDurationMinutes = duration
        durationOverrides = [:]
        resetTransientState()
        // 表示中の日はコピー元の日のまま。コピー先はカレンダーで選んでもらう
    }

    // MARK: - 日付

    /// 日を選ぶ。新規・コピーでは選んだ日を足し、編集ではその日へ移動する（仕様 §34・§61）。選んだ日を表示する
    func selectDay(_ day: CalendarDay) {
        if mode.allowsMultipleDays {
            if !selectedDays.contains(day) {
                selectedDays.append(day)
                selectedDays.sort()
            }
        } else {
            let carriedStart = selectedDays.first.flatMap { startMinutes[$0] }
            selectedDays = [day]
            startMinutes = carriedStart.map { [day: $0] } ?? [:]
        }
        displayedDay = day
    }

    /// 選んだ日を外す（新規・コピーのみ）。表示中の日を外したら、残りの最初の日を表示する
    func deselectDay(_ day: CalendarDay) {
        guard mode.allowsMultipleDays, let index = selectedDays.firstIndex(of: day) else { return }
        selectedDays.remove(at: index)
        startMinutes[day] = nil
        durationOverrides[day] = nil
        if displayedDay == day {
            displayedDay = selectedDays.first
        }
    }

    /// 左上に出す日を切り替える（日付タブ。仕様 §35）
    func displayDay(_ day: CalendarDay) {
        displayedDay = day
    }

    // MARK: - 時刻

    /// 開始時刻を入れる（時をタップして分ホイール、仮予定のドラッグ。仕様 §38・§40）。
    /// 表示中の日が選ばれていなければ、その日を選んでから入れる
    func setStartMinute(_ minute: MinuteOfDay, on day: CalendarDay? = nil) {
        guard let target = day ?? displayedDay else { return }
        if !selectedDays.contains(target) { selectDay(target) }
        startMinutes[target] = clampToDay(minute)
    }

    /// 時刻を確定して、まだ時刻のない次の日へ表示を移す（仕様 §36）。移った先の日を返す
    @discardableResult
    func confirmStartTime() -> CalendarDay? {
        guard let current = displayedDay, startMinutes[current] != nil else { return nil }
        let unset = selectedDays.filter { startMinutes[$0] == nil }
        guard let next = unset.first(where: { $0 > current }) ?? unset.first else { return nil }
        displayedDay = next
        return next
    }

    /// その日の所要時間。その日だけ変えていなければ、全部の日に共通の値（Q1）
    func durationMinutes(on day: CalendarDay) -> Int? {
        if let override = durationOverrides[day] { return override }
        return commonDurationMinutes
    }

    func endMinute(on day: CalendarDay) -> MinuteOfDay? {
        guard let start = startMinutes[day], let duration = durationMinutes(on: day) else { return nil }
        return start + duration
    }

    /// 終了時刻を入れる（仮予定の下端のハンドル・右上の終了行。仕様 §41）。nil で終了未設定に戻す。
    /// 終了は開始より後のときだけ有効。開始時刻を動かすと、所要時間を保ったまま終了も動く。
    ///
    /// 複数日（Q1）：最初に入れた所要時間は全部の日に入る。そのあと日付タブで選んだ日で変えると、その日だけ変わる。
    /// 1 日だけ選んでいる間は、何度変えても全部の日に共通の値として持つ（あとで足した日にも同じ値が入る）
    func setEndMinute(_ end: MinuteOfDay?, on day: CalendarDay? = nil) {
        guard let target = day ?? displayedDay else { return }
        let duration: Int?
        if let end {
            guard let start = startMinutes[target], end > start else { return }
            duration = end - start
        } else {
            duration = nil
        }

        let isFirstEntry = commonDurationMinutes == nil && durationOverrides.isEmpty
        if !mode.allowsMultipleDays || selectedDays.count <= 1 || isFirstEntry {
            commonDurationMinutes = duration
            durationOverrides = [:]
        } else if duration == commonDurationMinutes {
            durationOverrides[target] = nil
        } else {
            durationOverrides[target] = .some(duration)
        }
    }

    /// 「全日に適用」を出すか（Q5）。複数日を選んでいて、表示中の日と所要時間が違う日があるとき
    var canApplyDurationToAllDays: Bool {
        guard mode.allowsMultipleDays, selectedDays.count > 1, let shown = displayedDay else { return false }
        let duration = durationMinutes(on: shown)
        return selectedDays.contains { durationMinutes(on: $0) != duration }
    }

    /// 「全日に適用」（Q5）：表示中の日の所要時間を、選んでいる全部の日に入れ直す
    func applyDurationToAllDays() {
        guard let shown = displayedDay else { return }
        commonDurationMinutes = durationMinutes(on: shown)
        durationOverrides = [:]
    }

    // MARK: - 予測で一括

    /// 時刻のない日だけに予測の候補を入れる。自分で入れた時刻は上書きしない（Q2）。保存はしない（仕様 §36）
    func applyPrediction() {
        let unset = selectedDays.filter { startMinutes[$0] == nil }
        let suggestions = predictor.suggestStartMinutes(for: unset, content: content, existing: events)
        let applied = unset.filter { suggestions[$0] != nil }
        for day in applied {
            if let minute = suggestions[day] { startMinutes[day] = clampToDay(minute) }
        }
        predictionState = applied.isEmpty ? .noSuggestion : .applied(applied)
    }

    // MARK: - 右上の行

    /// 行を開く。別の行が開いていたら閉じる。開いている行をもう一度押したら閉じる（仕様 §45）
    func toggleRow(_ row: InputRow) {
        expandedRow = expandedRow == row ? nil : row
    }

    func collapseRows() {
        expandedRow = nil
    }

    // MARK: - 保存

    /// 保存して、保存した予定を返す。足りないものがあれば、その項目を開いて知らせ、保存しない（仕様 §46）
    @discardableResult
    func save() throws -> [CalendarEvent] {
        let issues = saveIssues
        guard issues.isEmpty else {
            present(issues)
            throw ScheduleEditorError.notReady(issues)
        }

        let saved: [CalendarEvent]
        switch mode {
        case .new, .copy:
            saved = draftEvents
            try repository.insert(saved)
        case .edit(let id):
            guard let original = events.first(where: { $0.id == id }),
                  let day = selectedDays.first,
                  let start = startMinutes[day] else {
                throw ScheduleEditorError.eventNotFound(id)
            }
            let updated = content.makeEvent(id: original.id,
                                            day: day,
                                            startMinute: start,
                                            durationMinutes: durationMinutes(on: day),
                                            isAllDay: original.isAllDay,
                                            source: original.source)
            try repository.update(updated)
            saved = [updated]
        }
        for event in saved {
            try metadataRepository.save(content.metadata, for: event.id)
        }

        reloadEvents()
        showsSaveIssue = false
        baseline = snapshot
        return saved
    }

    /// 編集中の予定を消す（仕様 §64。編集のときだけ）。消したら新規の状態に戻す
    func deleteEditingEvent() throws {
        guard case .edit(let id) = mode else { return }
        let day = displayedDay
        try repository.delete(id: id)
        try metadataRepository.delete(for: id)
        reloadEvents()
        startNew(on: day)
    }

    /// 予定詳細の吹き出しの「編集」（Q30）：その予定の編集を始め、カレンダー側に 3 分割画面を開いてもらう
    func beginEditing(_ eventID: UUID, from calendar: CalendarStore) {
        refresh()
        do {
            try startEditing(eventID: eventID)
        } catch {
            calendar.reload()
            return
        }
        calendar.requestEdit(eventID)
    }

    /// 保存先を読み直す（カレンダーなど、ほかの画面で予定が変わったあと）
    func refresh() {
        reloadEvents()
    }

    /// 未保存の変更を捨てて、始めた時の状態に戻す
    func discardChanges() {
        mode = baseline.mode
        selectedDays = baseline.selectedDays
        startMinutes = baseline.startMinutes
        commonDurationMinutes = baseline.commonDurationMinutes
        durationOverrides = baseline.durationOverrides
        content = baseline.content
        resetTransientState()
    }

    // MARK: - 内部

    /// 足りない項目を開いて知らせる。保存ボタンを無効にするだけにはしない（仕様 §46）
    private func present(_ issues: [SaveIssue]) {
        showsSaveIssue = true
        guard let first = issues.first else { return }
        switch first {
        case .noDaySelected:
            break  // 下の日付カレンダーは常に見えている（仕様 §32）
        case .missingStartTime(let days):
            if let day = days.first { displayedDay = day }
        case .missingTitle:
            expandedRow = .title
        }
    }

    private func resetTransientState() {
        expandedRow = nil
        predictionState = .idle
        showsSaveIssue = false
    }

    private func reloadEvents() {
        events = repository.allEvents()
        metadataByEventID = metadataRepository.allMetadata()
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clampToDay(_ minute: MinuteOfDay) -> MinuteOfDay {
        min(max(minute, 0), MinuteOfDay.minutesPerDay - 1)
    }

    private struct Snapshot: Equatable {
        var mode: EditorMode = .new
        var selectedDays: [CalendarDay] = []
        var startMinutes: [CalendarDay: MinuteOfDay] = [:]
        var commonDurationMinutes: Int?
        var durationOverrides: [CalendarDay: Int?] = [:]
        var content = EventContent()
    }

    private var snapshot: Snapshot {
        Snapshot(mode: mode,
                 selectedDays: selectedDays,
                 startMinutes: startMinutes,
                 commonDurationMinutes: commonDurationMinutes,
                 durationOverrides: durationOverrides,
                 content: content)
    }
}
