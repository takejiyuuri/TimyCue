import Foundation
import Observation

/// 予定登録・編集・コピーの 3 分割画面の状態（仕様 §16〜§36・§50）。
/// 画面（View）は表示と操作の受け渡しだけにして、決まりごとはすべてここに置く。
///
/// 日付タップを「選択」「選択解除」「表示切り替え」のどれにするかは未決（報告 Q5・Q6）なので、
/// ここでは操作を分けて用意し、どれをどのタップに割り当てるかは画面側で決める。
@MainActor
@Observable
final class ScheduleEditorStore {
    private(set) var mode: EditorMode = .new
    /// 予定を登録する日（新規・コピーは複数、編集は 1 日）。日付順
    private(set) var selectedDays: [CalendarDay] = []
    /// 左上の時間画面に出している日（1 日）
    private(set) var displayedDay: CalendarDay?
    /// 日ごとの開始時刻（仕様 §19：日ごとに違ってよい）
    private(set) var startMinutes: [CalendarDay: MinuteOfDay] = [:]
    /// 右上の入力欄の中身
    var content = EventContent()
    private(set) var predictionState: PredictionState = .idle
    private(set) var events: [CalendarEvent] = []

    @ObservationIgnored private let repository: EventRepository
    @ObservationIgnored private let predictor: PredictionService
    @ObservationIgnored private var baseline = Snapshot()

    init(repository: EventRepository, predictor: PredictionService = SameTitlePredictionService()) {
        self.repository = repository
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

    /// 保存前の仮予定（時刻が決まっている日の分だけ。仕様 §22）
    var draftEvents: [CalendarEvent] {
        selectedDays.compactMap { day in
            guard let start = startMinutes[day] else { return nil }
            return CalendarEvent(day: day, startMinute: start, content: content)
        }
    }

    /// 時間画面の初期位置の目安（仕様 §26 の「予定がある日は最初の予定の少し前」）。
    /// 予定がない日の扱い（現在時刻付近／履歴から）は画面側で決める
    func suggestedScrollMinute(for day: CalendarDay, leadMinutes: Int = 30) -> MinuteOfDay? {
        let starts = timedEvents(on: day).map(\.startMinute) + [startMinutes[day]].compactMap { $0 }
        return starts.min().map { max(0, $0 - leadMinutes) }
    }

    var dateValidation: DateValidationState {
        if selectedDays.isEmpty { return .noDaySelected }
        let missing = selectedDays.filter { startMinutes[$0] == nil }
        return missing.isEmpty ? .ready : .missingStartTime(missing)
    }

    /// 保存ボタンの文言（仕様 §30・§31・§34）
    var saveButtonTitle: String {
        let count = max(selectedDays.count, 1)
        switch mode {
        case .new: return count == 1 ? "保存" : "\(count)件保存"
        case .edit: return "変更を保存"
        case .copy: return count == 1 ? "コピーを保存" : "\(count)件コピー"
        }
    }

    /// 未保存の変更があるか（仕様 §36）
    var hasUnsavedChanges: Bool {
        snapshot != baseline
    }

    // MARK: - モードの切り替え

    /// 新規を始める。最初にどの日を選んでおくかは未決（報告 Q7）なので、呼ぶ側が渡す
    func startNew(on day: CalendarDay? = nil) {
        mode = .new
        content = EventContent()
        selectedDays = []
        startMinutes = [:]
        displayedDay = day
        predictionState = .idle
        if let day { selectedDays = [day] }
        baseline = snapshot
    }

    /// 既存予定の編集を始める（仕様 §25・§31）
    func startEditing(eventID: UUID) throws {
        guard let event = events.first(where: { $0.id == eventID }) else {
            throw ScheduleEditorError.eventNotFound(eventID)
        }
        mode = .edit(eventID: eventID)
        content = event.content
        selectedDays = [event.day]
        startMinutes = [event.day: event.startMinute]
        displayedDay = event.day
        predictionState = .idle
        baseline = snapshot
    }

    /// 編集中の予定からコピーを始める（仕様 §32・§33）。元の予定は変えない。
    /// 日付と開始時刻は引き継がない。編集中に直した中身は、そのままコピーの中身になる
    func startCopy() throws {
        guard case .edit(let id) = mode else { throw ScheduleEditorError.copyRequiresEditMode }
        mode = .copy(sourceID: id)
        content = content.copiedForNewEvent()
        selectedDays = []
        startMinutes = [:]
        predictionState = .idle
        // 表示中の日はコピー元の日のまま。コピー先はカレンダーで選んでもらう
    }

    // MARK: - 日付

    /// 日を選ぶ。新規・コピーでは選んだ日を足し、編集ではその日へ移動する（仕様 §31）。選んだ日を表示する
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
        if displayedDay == day {
            displayedDay = selectedDays.first
        }
    }

    /// 左上に出す日を切り替える（日付タブ。仕様 §18）
    func displayDay(_ day: CalendarDay) {
        displayedDay = day
    }

    /// 何も入力していない状態か（カレンダータブを開いて眺めているだけの状態）
    var isBrowsing: Bool {
        mode == .new && startMinutes.isEmpty && content == EventContent()
    }

    /// カレンダーで日を見る。何も入力していなければ、その日を新規の登録先にして表示する。
    /// 入力中なら表示を切り替えるだけ（入力中のタップで日を足すかどうかは未決のため、ここでは決めない）
    func browse(to day: CalendarDay) {
        if isBrowsing {
            startNew(on: day)
        } else {
            displayDay(day)
        }
    }

    // MARK: - 時刻

    /// 開始時刻を入れる（時をタップ、分ホイール、仮予定のドラッグ。仕様 §21〜§23）。
    /// 表示中の日が選ばれていなければ、その日を選んでから入れる
    func setStartMinute(_ minute: MinuteOfDay, on day: CalendarDay? = nil) {
        guard let target = day ?? displayedDay else { return }
        if !selectedDays.contains(target) { selectDay(target) }
        startMinutes[target] = clampToDay(minute)
    }

    /// 時刻を確定して、まだ時刻のない次の日へ表示を移す（仕様 §19）。移った先の日を返す
    @discardableResult
    func confirmStartTime() -> CalendarDay? {
        guard let current = displayedDay, startMinutes[current] != nil else { return nil }
        let unset = selectedDays.filter { startMinutes[$0] == nil }
        guard let next = unset.first(where: { $0 > current }) ?? unset.first else { return nil }
        displayedDay = next
        return next
    }

    /// 終了時刻を入れる（下端のハンドル・右上の終了行。仕様 §24）。終了は開始より後のときだけ有効
    func setEndMinute(_ end: MinuteOfDay?, on day: CalendarDay? = nil) {
        guard let end else {
            content.durationMinutes = nil
            return
        }
        guard let target = day ?? displayedDay, let start = startMinutes[target], end > start else { return }
        content.durationMinutes = end - start
    }

    func endMinute(on day: CalendarDay) -> MinuteOfDay? {
        guard let start = startMinutes[day], let duration = content.durationMinutes else { return nil }
        return start + duration
    }

    // MARK: - 予測で一括

    /// 時刻のない日に予測の候補を入れる。保存はしない（仕様 §19）
    func applyPrediction() {
        let unset = selectedDays.filter { startMinutes[$0] == nil }
        let suggestions = predictor.suggestStartMinutes(for: unset, content: content, existing: events)
        let applied = unset.filter { suggestions[$0] != nil }
        for day in applied {
            if let minute = suggestions[day] { startMinutes[day] = clampToDay(minute) }
        }
        predictionState = applied.isEmpty ? .noSuggestion : .applied(applied)
    }

    // MARK: - 保存

    /// 保存して、保存した予定を返す
    @discardableResult
    func save() throws -> [CalendarEvent] {
        guard dateValidation == .ready else { throw ScheduleEditorError.notReady(dateValidation) }
        let saved: [CalendarEvent]
        switch mode {
        case .new, .copy:
            saved = draftEvents
            try repository.insert(saved)
        case .edit(let id):
            guard var event = events.first(where: { $0.id == id }), let day = selectedDays.first,
                  let start = startMinutes[day] else {
                throw ScheduleEditorError.eventNotFound(id)
            }
            event.day = day
            event.startMinute = start
            event.content = content
            try repository.update(event)
            saved = [event]
        }
        reloadEvents()
        baseline = snapshot
        return saved
    }

    /// 未保存の変更を捨てて、始めた時の状態に戻す
    func discardChanges() {
        mode = baseline.mode
        selectedDays = baseline.selectedDays
        startMinutes = baseline.startMinutes
        content = baseline.content
        predictionState = .idle
    }

    // MARK: - 内部

    private func reloadEvents() {
        events = repository.allEvents()
    }

    private func clampToDay(_ minute: MinuteOfDay) -> MinuteOfDay {
        min(max(minute, 0), MinuteOfDay.minutesPerDay - 1)
    }

    private struct Snapshot: Equatable {
        var mode: EditorMode = .new
        var selectedDays: [CalendarDay] = []
        var startMinutes: [CalendarDay: MinuteOfDay] = [:]
        var content = EventContent()
    }

    private var snapshot: Snapshot {
        Snapshot(mode: mode, selectedDays: selectedDays, startMinutes: startMinutes, content: content)
    }
}
