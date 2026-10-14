import Foundation
import Observation

/// 予定登録・編集・コピーの 3 分割画面の状態（仕様 §31〜§66）。
/// 画面（View）は表示と操作の受け渡しだけにして、決まりごとはすべてここに置く。
///
/// 日付（2026-10-14 ユーザー決定）：下のカレンダーをタップすると、左上に出す日を選ぶ（選んでいない日なら左上の日をその日へ動かす）。
/// 複数の日は、右の入力のいちばん下の「同じ内容で追加」を開いている間だけ、なぞったりタップしたりして足す・外す。
/// 足した日の時刻は、初めは「一括」（全部の日で同じ時刻）。「個別」を選ぶと日ごとに決める。左上には 1 日だけ出す。
@MainActor
@Observable
final class ScheduleEditorStore {
    private(set) var mode: EditorMode = .new
    /// 予定を登録する日（新規・コピーは複数、編集は 1 日）。日付順
    private(set) var selectedDays: [CalendarDay] = []
    /// 最初に選んだ日（下のカレンダーをタップして選んだ日）。「同じ内容で追加」で足した日はこれ以外
    private(set) var baseDay: CalendarDay?
    /// 左上の時間画面に出している日（1 日）。選んである日を下のカレンダーでタップすると切り替わる（2026-10-14 ユーザー決定）
    private(set) var displayedDay: CalendarDay?
    /// 日ごとの開始時刻（仕様 §36：日ごとに違ってよい）
    private(set) var startMinutes: [CalendarDay: MinuteOfDay] = [:]
    /// 全部の日に共通の所要時間（Q1：最初に入れた値が全部の日に入る）。nil は終了未設定
    private(set) var commonDurationMinutes: Int?
    /// その日だけ変えた所要時間（Q1。「個別」のとき、その日を左上に出して変える）。値が nil の日は、その日だけ終了未設定
    private(set) var durationOverrides: [CalendarDay: Int?] = [:]
    /// 「同じ内容で追加」の時刻を日ごとに決めるか（2026-10-14 ユーザー決定）。
    /// false（一括。初め）：全部の日で同じ開始時刻・所要時間。true（個別）：日ごとに決める
    private(set) var setsTimesIndividually = false
    /// 右上の入力欄の中身
    var content = EventContent()
    /// 右上で開いている行（仕様 §45：同時に 1 行だけ）
    private(set) var expandedRow: InputRow?
    private(set) var events: [CalendarEvent] = []
    private(set) var metadataByEventID: [UUID: TimyCueEventMetadata] = [:]
    /// 予定を書き込める Apple カレンダー（つないでいないときは空）と、新しい予定の既定の保存先（Q32）
    private(set) var writableCalendars: [CalendarChoice] = []
    private(set) var defaultCalendarID: String?
    /// 到着目標の全体既定値（Q70。設定画面で変えられるようにするのは後の段階）
    var defaultArrivalTargetMinutes = TimyCueEventMetadata.defaultArrivalTargetMinutes
    /// 書き込めない Apple カレンダー（共有・購読など）の id → 名前（追加仕様書 §1.7）
    private(set) var readOnlyCalendarTitles: [String: String] = [:]

    /// 保存しようとして足りないものがあったか。あったら、直るまで知らせを出し続ける（仕様 §46）
    private var showsSaveIssue = false

    @ObservationIgnored private let repository: EventRepository
    @ObservationIgnored private let metadataRepository: EventMetadataRepository
    @ObservationIgnored private var baseline = Snapshot()

    init(repository: EventRepository,
         metadataRepository: EventMetadataRepository) {
        self.repository = repository
        self.metadataRepository = metadataRepository
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

    /// 右上に出す行。ルートは移動手段が車のときだけ（仕様 §52）。
    /// カレンダーは書き込める Apple カレンダーが 2 つ以上あるときだけ（Q32）。
    /// 「同じ内容で追加」は新規・コピーのときだけ、いちばん下に出す（2026-10-14 ユーザー決定）
    var visibleRows: [InputRow] {
        InputRow.allCases.filter { row in
            switch row {
            case .route: content.metadata.transport == .car
            case .calendar: writableCalendars.count > 1
            case .additionalDays: mode.allowsMultipleDays
            default: true
            }
        }
    }

    /// Apple カレンダーとつないだ・設定を変えたとき（書き込めないカレンダーも含めて渡す）
    func setCalendars(_ calendars: [CalendarChoice], defaultCalendarID: String?) {
        writableCalendars = calendars.filter(\.isWritable)
        readOnlyCalendarTitles = Dictionary(calendars.filter { !$0.isWritable }.map { ($0.id, $0.title) },
                                            uniquingKeysWith: { first, _ in first })
        self.defaultCalendarID = defaultCalendarID
    }

    // MARK: - 編集できない Apple カレンダーの予定（追加仕様書 §1.7）

    /// 編集している予定が、書き込めない Apple カレンダーのものなら、その短い理由。
    /// 予定名・日時・場所など Apple 由来の項目はロックし、TimyCue の設定（到着目標など）だけ変えられる
    var appleFieldsLockReason: String? {
        guard case .edit(let id) = mode,
              let event = events.first(where: { $0.id == id }),
              event.source == .appleCalendar,
              let calendarID = event.calendarID,
              let title = readOnlyCalendarTitles[calendarID] else { return nil }
        return "「\(title)」は編集できないカレンダーです。予定名・日時・場所は Apple のカレンダーで変更してください"
    }

    var areAppleFieldsLocked: Bool {
        appleFieldsLockReason != nil
    }

    /// その行がロックされているか（TimyCue の設定の行はロックしない）
    func isLocked(_ row: InputRow) -> Bool {
        areAppleFieldsLocked && row.isAppleField
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
        // 到着目標は作った瞬間の全体既定値を入れる（Q70。全体既定値の設定は後の段階。今は初期値の 0 分前）
        content.metadata.arrivalTargetMinutes = defaultArrivalTargetMinutes
        selectedDays = []
        startMinutes = [:]
        commonDurationMinutes = nil
        durationOverrides = [:]
        displayedDay = day
        baseDay = day
        setsTimesIndividually = false
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
        baseDay = event.day
        setsTimesIndividually = false
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
        baseDay = nil
        setsTimesIndividually = false
        startMinutes = [:]
        commonDurationMinutes = duration
        durationOverrides = [:]
        resetTransientState()
        // 表示中の日はコピー元の日のまま。コピー先はカレンダーで選んでもらう
    }

    // MARK: - 日付

    /// 下のカレンダーをタップしたとき（「同じ内容で追加」を開いていないとき。仕様 §34・§61、2026-10-14 ユーザー決定）。
    /// 選んである日なら、その日を左上に出す（日ごとに時刻を決めるため。追加仕様書 vNext §1.2）。
    /// 選んでいない日なら、左上に出している日をその日へ動かす（開始時刻・所要時間はそのまま。編集の移動と同じ）。
    /// まだ何も選んでいなければ、その日を選ぶ
    func selectDay(_ day: CalendarDay) {
        guard !areAppleFieldsLocked, day != copySourceDay else { return }
        if !selectedDays.contains(day) {
            if let shown = displayedDay, selectedDays.contains(shown) {
                moveDay(shown, to: day)
            } else {
                selectedDays = (selectedDays + [day]).sorted()
                if baseDay == nil { baseDay = day }
            }
        }
        displayedDay = day
    }

    /// 「同じ内容で追加」の行を開いている間は、下のカレンダーで日を足したり外したりする（新規・コピーのみ。2026-10-14 ユーザー決定）
    var isAddingDays: Bool {
        expandedRow == .additionalDays && mode.allowsMultipleDays
    }

    /// 「同じ内容で追加」で足した日（最初に選んだ日は含めない）。日付順
    var additionalDays: [CalendarDay] {
        selectedDays.filter { $0 != baseDay }
    }

    /// コピー先を選んでいる（コピー中）。下のカレンダーの日付を押すたびに、コピー先を足す・外す（2026-10-14 ユーザー決定）
    var isChoosingCopyDestinations: Bool {
        if case .copy = mode { return true }
        return false
    }

    /// コピー元の予定の日。コピー先にはできない（2026-10-14 ユーザー決定）
    var copySourceDay: CalendarDay? {
        guard case .copy(let id) = mode else { return nil }
        return events.first { $0.id == id }?.day
    }

    /// コピー中に下のカレンダーの日付を押したとき：選んでいなければコピー先に足し、選んであれば外す。
    /// 「同じ内容で追加」を開かなくてよい（あの行は一括／個別の時刻の切り替えに使う）。コピー元の日は選べない（2026-10-14 ユーザー決定）
    func toggleCopyDestination(_ day: CalendarDay) {
        guard isChoosingCopyDestinations, !areAppleFieldsLocked, day != copySourceDay else { return }
        if selectedDays.contains(day) {
            removeDay(day)
        } else {
            addDay(day)
        }
    }

    /// 同じ内容で日を足す（新規・コピーのみ）。「一括」なら開始時刻も同じものを入れる。「個別」なら時刻は日ごとに決めてもらう。
    /// 所要時間は全部の日に共通の値が入る（Q1）。まだ何も選んでいなければ、その日を選ぶ
    func addDay(_ day: CalendarDay) {
        guard mode.allowsMultipleDays, !selectedDays.contains(day), day != copySourceDay else { return }
        guard !selectedDays.isEmpty else {
            selectDay(day)
            return
        }
        selectedDays = (selectedDays + [day]).sorted()
        if !setsTimesIndividually, let start = sharedStartMinute {
            startMinutes[day] = start
        }
    }

    /// 「一括」のときの、全部の日に共通の開始時刻（最初に選んだ日の時刻）
    private var sharedStartMinute: MinuteOfDay? {
        baseDay.flatMap { startMinutes[$0] } ?? selectedDays.lazy.compactMap { self.startMinutes[$0] }.first
    }

    /// 「一括」と「個別」を切り替える（2026-10-14 ユーザー決定）。
    /// 一括に戻すときは、今左上に出している日（編集中の日）の開始時刻・所要時間を、全部の日に入れ直す（2026-10-14 決定）
    func setTimesIndividually(_ individually: Bool) {
        guard mode.allowsMultipleDays, individually != setsTimesIndividually else { return }
        setsTimesIndividually = individually
        guard !individually else { return }
        let start = batchStart
        let duration = batchDuration
        for day in selectedDays {
            startMinutes[day] = start
        }
        commonDurationMinutes = duration
        durationOverrides = [:]
    }

    /// 一括にそろえる値の元になる日：今左上に出している日。出している日が選んである日でなければ、最初に選んだ日
    private var activeDay: CalendarDay? {
        if let shown = displayedDay, selectedDays.contains(shown) { return shown }
        return baseDay
    }

    /// 一括にそろえる開始時刻・所要時間。出している日に時刻がなければ、ほかの日の時刻（仮）
    private var batchStart: MinuteOfDay? {
        activeDay.flatMap { startMinutes[$0] } ?? sharedStartMinute
    }

    private var batchDuration: Int? {
        activeDay.flatMap { durationMinutes(on: $0) } ?? commonDurationMinutes
    }

    /// 一括にすると、開始時刻・所要時間が変わる日があるか。あれば切り替える前に一度確かめる。全部同じなら確かめずに切り替える
    var batchChangesSomeDays: Bool {
        let start = batchStart
        let duration = batchDuration
        return selectedDays.contains { startMinutes[$0] != start || durationMinutes(on: $0) != duration }
    }

    /// 一括にそろえる前に確かめる文（2026-10-14 決定）。例：すべて 10:00〜11:00 にそろえますか？
    var batchConfirmationMessage: String {
        guard let start = batchStart else { return "すべての日の時刻をそろえますか？" }
        let end = batchDuration.map { "〜\(TimeText.hourMinute(start + $0))" } ?? ""
        return "すべて \(TimeText.hourMinute(start))\(end) にそろえますか？"
    }

    /// 足した日を外す（新規・コピーのみ）。新規では最初に選んだ日は外さない（コピーはどの日も外せる。2026-10-14 ユーザー決定）。
    /// 左上に出していた日を外したら、最初に選んだ日（それを外したら残った最初の日）を出す
    func removeDay(_ day: CalendarDay) {
        guard mode.allowsMultipleDays, selectedDays.contains(day),
              day != baseDay || isChoosingCopyDestinations else { return }
        selectedDays.removeAll { $0 == day }
        startMinutes[day] = nil
        durationOverrides[day] = nil
        if baseDay == day { baseDay = selectedDays.first }
        if displayedDay == day {
            displayedDay = baseDay ?? day
        }
    }

    /// 左上に出している日を別の日へ動かす。その日の開始時刻と、その日だけの所要時間も一緒に動かす
    private func moveDay(_ old: CalendarDay, to new: CalendarDay) {
        selectedDays = (selectedDays.filter { $0 != old } + [new]).sorted()
        startMinutes[new] = startMinutes.removeValue(forKey: old)
        if let duration = durationOverrides.removeValue(forKey: old) {
            durationOverrides[new] = .some(duration)
        }
        if baseDay == old { baseDay = new }
    }

    // MARK: - 時刻

    /// 開始時刻を入れる（時をタップして分ホイール、仮予定のドラッグ。仕様 §38・§40）。
    /// 表示中の日が選ばれていなければ、その日を選んでから入れる
    func setStartMinute(_ minute: MinuteOfDay, on day: CalendarDay? = nil) {
        guard !areAppleFieldsLocked, let target = day ?? displayedDay else { return }
        if !selectedDays.contains(target) { selectDay(target) }
        // コピー元の日のように選べない日なら、時刻も入れない
        guard selectedDays.contains(target) else { return }
        // 「一括」なら全部の日で同じ時刻（2026-10-14 ユーザー決定）
        let days = mode.allowsMultipleDays && !setsTimesIndividually ? selectedDays : [target]
        for each in days {
            startMinutes[each] = clampToDay(minute)
        }
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
    /// 複数日（Q1）：最初に入れた所要時間は全部の日に入る。そのあと左上に出した日で変えると、その日だけ変わる。
    /// 1 日だけ選んでいる間は、何度変えても全部の日に共通の値として持つ（あとで足した日にも同じ値が入る）
    func setEndMinute(_ end: MinuteOfDay?, on day: CalendarDay? = nil) {
        guard !areAppleFieldsLocked, let target = day ?? displayedDay else { return }
        let duration: Int?
        if let end {
            guard let start = startMinutes[target], end > start else { return }
            duration = end - start
        } else {
            duration = nil
        }

        let isFirstEntry = commonDurationMinutes == nil && durationOverrides.isEmpty
        if !mode.allowsMultipleDays || !setsTimesIndividually || selectedDays.count <= 1 || isFirstEntry {
            commonDurationMinutes = duration
            durationOverrides = [:]
        } else if duration == commonDurationMinutes {
            durationOverrides[target] = nil
        } else {
            durationOverrides[target] = .some(duration)
        }
    }

    // MARK: - 右上の行

    /// 行を開く。別の行が開いていたら閉じる。開いている行をもう一度押したら閉じる（仕様 §45）
    func toggleRow(_ row: InputRow) {
        // ロックした行は開かない（理由は右上の一番上に出している）
        guard !isLocked(row) else { expandedRow = nil; return }
        expandedRow = expandedRow == row ? nil : row
    }

    func collapseRows() {
        expandedRow = nil
    }

    // MARK: - 保存

    /// 繰り返し予定（Apple カレンダーの繰り返しの 1 回）を編集しているか。保存・削除のときに範囲を聞く（Q44）
    var isEditingRecurringEvent: Bool {
        guard case .edit(let id) = mode else { return false }
        return events.first { $0.id == id }?.repeatRule.isRepeating ?? false
    }

    /// 保存して、保存した予定を返す。足りないものがあれば、その項目を開いて知らせ、保存しない（仕様 §46）。
    /// 繰り返し予定の編集では、scope の範囲（この予定のみ／これ以降／すべて）で直す（Q44）
    @discardableResult
    func save(scope: RecurrenceScope = .thisEvent) throws -> [CalendarEvent] {
        let issues = saveIssues
        guard issues.isEmpty else {
            present(issues)
            throw ScheduleEditorError.notReady(issues)
        }

        let saved: [CalendarEvent]
        /// 保存する TimyCue の情報（到着目標など）。繰り返しはシリーズ共通の設定と回ごとの個別上書きを分ける（追加仕様書 §2.7.1・Q53）
        var entries: [UUID: TimyCueEventMetadata] = [:]
        switch mode {
        case .new, .copy:
            saved = draftEvents
            try repository.insert(saved)
            var common = content.metadata
            common.overrides = nil
            for event in saved {
                entries[event.id] = common
                if event.repeatRule.isRepeating, let seriesID = repository.seriesID(of: event.id) {
                    entries[seriesID] = common
                }
            }
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
            let isRecurring = original.repeatRule.isRepeating
            let effectiveScope: RecurrenceScope = isRecurring ? scope : .thisEvent
            let before = metadataByEventID[id] ?? TimyCueEventMetadata()
            let changed = before.changedFields(to: content.metadata)
            let targets = repository.occurrenceIDs(sameSeriesAs: id, scope: effectiveScope)
            let oldCommon = repository.seriesID(of: id).flatMap { metadataByEventID[$0] }
            // 書き込めないカレンダーの予定は、Apple カレンダーへは書かず、TimyCue の設定だけ保存する（§1.7）
            if !areAppleFieldsLocked {
                try repository.update(updated, scope: effectiveScope)
            }
            saved = [updated]

            if !isRecurring {
                entries[id] = content.metadata
            } else if effectiveScope == .thisEvent {
                entries[id] = RecurringMetadata.thisOnly(before: before, after: content.metadata)
                // 共通設定がまだない（前の版で作った）繰り返しは、変える前の設定を共通設定として残す
                if oldCommon == nil, let seriesID = repository.seriesID(of: id) {
                    var common = before
                    common.overrides = nil
                    entries[seriesID] = common
                }
            } else {
                var fallback = before
                fallback.overrides = nil
                for target in Set(targets + [id]) {
                    entries[target] = RecurringMetadata.series(target: metadataByEventID[target] ?? fallback,
                                                               changed: changed,
                                                               newValues: content.metadata,
                                                               isEditedOccurrence: target == id)
                }
                // 「これ以降」で Apple 側の繰り返しが分かれると、シリーズの id も新しくなる（前の回は前の共通設定のまま）
                if let seriesID = repository.seriesID(of: id) {
                    entries[seriesID] = RecurringMetadata.updatedCommon(oldCommon ?? fallback,
                                                                        changed: changed,
                                                                        newValues: content.metadata)
                }
            }
        }
        try metadataRepository.saveAll(entries)

        reloadEvents()
        showsSaveIssue = false
        baseline = snapshot
        return saved
    }

    /// 編集中の予定を消す（仕様 §64。編集のときだけ）。消したら新規の状態に戻す。
    /// 繰り返し予定は、scope の範囲（この予定のみ／これ以降／すべて）で消す（Q44）
    func deleteEditingEvent(scope: RecurrenceScope = .thisEvent) throws {
        guard case .edit(let id) = mode else { return }
        let day = displayedDay
        let effectiveScope: RecurrenceScope = isEditingRecurringEvent ? scope : .thisEvent
        var removed = Set(repository.occurrenceIDs(sameSeriesAs: id, scope: effectiveScope))
        // 「すべて」ならシリーズ共通の設定も消す（追加仕様書 §2.7.1）
        if effectiveScope == .allEvents, let seriesID = repository.seriesID(of: id) { removed.insert(seriesID) }
        try repository.delete(id: id, scope: effectiveScope)
        try metadataRepository.deleteAll(removed)
        reloadEvents()
        startNew(on: day)
    }

    // MARK: - ローカル予定を Apple カレンダーへ移す（追加仕様書 §1.12）

    /// 編集している予定が、つなぐ前から TimyCue の中にあった予定で、Apple カレンダーとつないでいるか。
    /// 自動・一括では移さない。編集画面でユーザーが「Apple Calendarに保存」を選んだときだけ移す
    var canMoveToAppleCalendar: Bool {
        guard case .edit(let id) = mode, !writableCalendars.isEmpty,
              let event = events.first(where: { $0.id == id }) else { return false }
        return event.source == .timyCue
    }

    /// 「Apple Calendarに保存」：今の内容で Apple カレンダーに新しく作り、TimyCue の設定を引き継いで、
    /// 元のローカル予定を消す（二重に出さない）。作った予定を返す
    @discardableResult
    func moveToAppleCalendar() throws -> CalendarEvent {
        let issues = saveIssues
        guard issues.isEmpty else {
            present(issues)
            throw ScheduleEditorError.notReady(issues)
        }
        guard canMoveToAppleCalendar, case .edit(let id) = mode,
              let original = events.first(where: { $0.id == id }),
              let day = selectedDays.first,
              let start = startMinutes[day] else {
            throw ScheduleEditorError.eventNotFound(editingEvent?.id ?? UUID())
        }
        let moved = content.makeEvent(id: UUID(),
                                      day: day,
                                      startMinute: start,
                                      durationMinutes: durationMinutes(on: day),
                                      isAllDay: original.isAllDay,
                                      source: .appleCalendar)
        try repository.insert([moved])
        var settings = content.metadata
        settings.overrides = nil
        var entries = [moved.id: settings]
        if moved.repeatRule.isRepeating, let seriesID = repository.seriesID(of: moved.id) { entries[seriesID] = settings }
        try metadataRepository.saveAll(entries)
        try repository.delete(id: id)
        try metadataRepository.delete(for: id)

        reloadEvents()
        mode = .edit(eventID: moved.id)
        showsSaveIssue = false
        baseline = snapshot
        return moved
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
        baseDay = baseline.baseDay
        startMinutes = baseline.startMinutes
        commonDurationMinutes = baseline.commonDurationMinutes
        durationOverrides = baseline.durationOverrides
        content = baseline.content
        setsTimesIndividually = false
        if let shown = displayedDay, !selectedDays.isEmpty, !selectedDays.contains(shown) {
            displayedDay = baseDay ?? selectedDays.first
        }
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
        var baseDay: CalendarDay?
        var startMinutes: [CalendarDay: MinuteOfDay] = [:]
        var commonDurationMinutes: Int?
        var durationOverrides: [CalendarDay: Int?] = [:]
        var content = EventContent()
    }

    private var snapshot: Snapshot {
        Snapshot(mode: mode,
                 selectedDays: selectedDays,
                 baseDay: baseDay,
                 startMinutes: startMinutes,
                 commonDurationMinutes: commonDurationMinutes,
                 durationOverrides: durationOverrides,
                 content: content)
    }
}
