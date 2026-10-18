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
    /// コピー先を選んだ順（コピー中だけ使う）。左上に出す日を決めるのに使う（2026-10-14 決定 G1）
    private var copyPicks: [CalendarDay] = []
    /// 「別の日にコピー」を押す前の編集の状態。「コピーをやめる」で戻す（2026-10-14 実機の指摘）
    @ObservationIgnored private var stateBeforeCopy: (snapshot: Snapshot, displayedDay: CalendarDay?,
                                                      setsTimesIndividually: Bool, baseline: Snapshot)?
    /// 右上の入力欄の中身
    var content = EventContent()
    /// 右上で開いている行（仕様 §45：同時に 1 行だけ）
    private(set) var expandedRow: InputRow?
    private(set) var events: [CalendarEvent] = []
    private(set) var metadataByEventID: [UUID: TimyCueEventMetadata] = [:]
    /// Apple カレンダーの保存先の決まり（spec §89.2・§89.4）。つないでいないときは空
    private(set) var saveTargets = SaveTargetRules()
    /// Apple カレンダーとつないでいるか。つないでいれば、新しい予定は Apple カレンダーへ書く（§68。「TimyCue のみ」は S2）
    private(set) var isConnectedToApple = false
    /// 到着目標の全体既定値（Q70。設定画面で変えられるようにするのは後の段階）
    var defaultArrivalTargetMinutes = TimyCueEventMetadata.defaultArrivalTargetMinutes
    /// 書き込めない Apple カレンダー（共有・購読など）の id → 名前（追加仕様書 §1.7）
    private(set) var readOnlyCalendarTitles: [String: String] = [:]

    /// 保存しようとして足りないものがあったか。あったら、直るまで知らせを出し続ける（仕様 §46）
    private var showsSaveIssue = false
    /// 保存・「Apple Calendarに保存」・削除に失敗したときの知らせ（spec §89.9）。画面はこれをアラートで出す
    private(set) var failure: EditorFailure?
    /// この画面で保存できた予定（一部だけ保存できたとき・知らせを出してから閉じるときに、元の画面へ渡す）
    private(set) var savedEventsThisSession: [CalendarEvent] = []
    /// 保存が済んだ。押し直し（続けて 2 回押したなど）で二度書かない。新規・編集を始め直すまで（spec §89.9・2026-10-18 S1b）
    private(set) var isFinished = false
    /// 新規・コピーで、日ごとに使う予定の id（押し直しても同じ id で書く。端末の中の保存では同じ予定を 2 件にしない）
    @ObservationIgnored private var plannedEventIDs: [CalendarDay: UUID] = [:]
    /// 予定は書けたのに保存できなかった TimyCue の設定（到着目標など）。次に保存・読み直すときに、もう一度保存する。
    /// 保存の途中の記録と同じところに置く（アプリが終わっても、次に開いたときに保存し直す）
    private var pendingMetadata: [UUID: TimyCueEventMetadata] {
        get { journal.pendingMetadata }
        set { journal.setPendingMetadata(newValue) }
    }
    /// 保存の途中の記録（新しい予定と「Apple Calendarに保存」。アプリが途中で終わっても次に開いたときに続きができるよう、
    /// 書く前に記録し、済んだら消す。「Apple Calendarに保存」がどこまで済んだかもここに残す。spec §89.9）
    @ObservationIgnored private let journal: SaveJournal

    @ObservationIgnored private let repository: EventRepository
    @ObservationIgnored private let metadataRepository: EventMetadataRepository
    @ObservationIgnored private var baseline = Snapshot()

    init(repository: EventRepository,
         metadataRepository: EventMetadataRepository,
         journal: SaveJournal = .inMemory()) {
        self.repository = repository
        self.metadataRepository = metadataRepository
        self.journal = journal
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
            return content.makeEvent(id: plannedEventIDs[day] ?? UUID(), day: day, startMinute: start,
                                     durationMinutes: durationMinutes(on: day))
        }
    }

    /// 時間画面の初期位置の目安（仕様 §43 の「予定がある日は最初の予定の少し前」）。
    /// 予定がない日の扱い（今日は現在時刻付近、未来日は適切な時間帯）は画面側で決める
    func suggestedScrollMinute(for day: CalendarDay, leadMinutes: Int = 30) -> MinuteOfDay? {
        let starts = timedEvents(on: day).map(\.startMinute) + [startMinutes[day]].compactMap { $0 }
        return starts.min().map { max(0, $0 - leadMinutes) }
    }

    /// 右上に出す行。ルートは移動手段が車のときだけ（仕様 §52）。カレンダーは showsCalendarRow のとき。
    /// 「同じ内容で追加」は新規・コピーのときだけ、いちばん下に出す（2026-10-14 ユーザー決定）
    var visibleRows: [InputRow] {
        InputRow.allCases.filter { row in
            switch row {
            case .route: content.metadata.transport == .car
            case .calendar: showsCalendarRow
            case .additionalDays: mode.allowsMultipleDays
            default: true
            }
        }
    }

    /// Apple カレンダーとつないだ・設定を変えたとき（書き込めないカレンダーも含めた一覧と、表示・表示のみ・既定の保存先の設定）
    func setCalendars(_ rules: SaveTargetRules) {
        saveTargets = rules
        isConnectedToApple = true
        readOnlyCalendarTitles = Dictionary(rules.calendars.filter { !$0.isWritable }.map { ($0.id, $0.title) },
                                            uniquingKeysWith: { first, _ in first })
    }

    // MARK: - 保存先（spec §89.2〜§89.5。2026-10-17・2026-10-18 決定）

    /// 保存先に選べる Apple カレンダー（表示 ON・書き込める・表示のみでない・今も見えるものだけ）
    var saveTargetCandidates: [CalendarChoice] {
        saveTargets.candidates
    }

    /// 保存すると Apple カレンダーへ書く予定の保存先：新規・コピー（つないでいるとき）と、Apple の予定の所属を変える編集。
    /// Apple へ書かないとき（つないでいない・ローカルの予定・所属を変えない編集・書き込めない予定）は nil
    var pendingSaveTarget: SaveTargetResolution? {
        guard isConnectedToApple else { return nil }
        switch mode {
        case .new, .copy:
            return saveTargets.resolve(eventCalendarID: content.calendarID)
        case .edit(let id):
            guard !areAppleFieldsLocked,
                  let original = events.first(where: { $0.id == id }), original.source == .appleCalendar,
                  let target = content.calendarID, target != original.calendarID else { return nil }
            return saveTargets.resolve(eventCalendarID: target)
        }
    }

    /// 今の保存先が使えないなら、その理由（保存の前に止める）
    var saveTargetProblem: SaveTargetProblem? {
        pendingSaveTarget?.problem
    }

    /// 「カレンダー」の行を出すか。つないでいて、選べる保存先が 2 つ以上あるとき（Q32・Q97）。
    /// 今の保存先（コピー元・設定の既定・iPhone の既定、「Apple Calendarに保存」の移す先）が使えないときは、選べるものが 1 つでも出して
    /// 選び直せるようにする（Q110）。行で選んで使えるようになっても、開いたときの保存先が使えなければ出したままにする（選んだ値が見えるように）。
    /// 「TimyCue のみ」を数えるのは S2 から
    var showsCalendarRow: Bool {
        guard isConnectedToApple else { return false }
        let count = saveTargetCandidates.count
        let unusable = saveTargetProblem != nil || moveToAppleTarget?.problem != nil || initialSaveTargetProblem != nil
        return count >= 2 || (count >= 1 && unusable)
    }

    /// 開いたときの保存先（予定ごとの選びを当てる前。新規は設定の既定 → iPhone の既定、コピーはコピー元の所属、
    /// ローカルの予定の編集は「Apple Calendarに保存」の移す先）が使えないなら、その理由
    private var initialSaveTargetProblem: SaveTargetProblem? {
        guard isConnectedToApple else { return nil }
        switch mode {
        case .new, .copy:
            return saveTargets.resolve(eventCalendarID: initialContent.calendarID).problem
        case .edit:
            return canMoveToAppleCalendar ? saveTargets.resolve(eventCalendarID: initialContent.calendarID).problem : nil
        }
    }

    /// 「カレンダー」の行で選ばれている保存先（チップの印）。使えないものは選ばれていないことにする
    var selectedSaveTargetID: String? {
        switch pendingSaveTarget ?? moveToAppleTarget {
        case .usable(let calendar, _)?: calendar.id
        case .unavailable?, .timyCueOnly?, .notChosen?: nil
        case nil: content.calendarID
        }
    }

    /// 「カレンダー」の行の値：「iPhoneの既定（Default）」かカレンダー名。使えないときは「（使えません）」を付ける（spec §89.11・Q110）
    var calendarRowValue: String {
        if let resolution = pendingSaveTarget ?? moveToAppleTarget { return saveTargets.label(for: resolution) }
        // Apple へ書かない編集（所属を変えない・書き込めない予定）は、今の所属の名前
        if let id = content.calendarID, let calendar = saveTargets.calendars.first(where: { $0.id == id }) {
            return calendar.title
        }
        return saveTargets.systemDefaultLabel
    }

    /// 「カレンダー」の行の値の候補（長い順）。行に入りきらなくても「（使えません）」が切れないように、短い言い方も渡す
    /// （例「iPhoneの既定（Default）（使えません）」→「Default（使えません）」→「使えません」。ビルド確認 #57 の画面写真で切れていた）
    var calendarRowValues: [String] {
        let full = calendarRowValue
        guard let resolution = pendingSaveTarget ?? moveToAppleTarget else { return [full] }
        let shortName: String? = switch resolution {
        case .usable(let calendar, _): calendar.title
        case .unavailable(let problem, _): SaveTargetRules.title(of: problem)
        case .timyCueOnly: SaveTargetRules.timyCueOnlyShortLabel
        case .notChosen: nil
        }
        var values = [full]
        if resolution.problem != nil {
            if let shortName { values.append("\(shortName)（使えません）") }
            values.append("使えません")
        } else if let shortName, shortName != full {
            values.append(shortName)
        }
        return values
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
    /// 3 分割画面を開いたとき（新規・編集・コピーを始めたとき）の入力欄の中身
    var initialContent: EventContent {
        baseline.content
    }

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
        // 場所なしで始まるので、通知の初期値は開始の基準。場所を入れたら出発の基準に置き換わる（2026-10-14 決定）
        content.metadata.notifications = .noPlaceDefault
        selectedDays = []
        startMinutes = [:]
        commonDurationMinutes = nil
        durationOverrides = [:]
        displayedDay = day
        baseDay = day
        setsTimesIndividually = false
        resetTransientState()
        resetSaveProgress()
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
        // 場所なしの予定に出発の基準の通知が入っていたら（前の版のもの・Apple カレンダーの予定の初期値）、開始の基準で出す（2026-10-14 決定 C3）
        if !content.hasPlace {
            content.metadata.notifications = content.metadata.notifications.converted(hasPlace: false)
        }
        selectedDays = [event.day]
        startMinutes = [event.day: event.startMinute]
        commonDurationMinutes = event.durationMinutes
        durationOverrides = [:]
        displayedDay = event.day
        baseDay = event.day
        setsTimesIndividually = false
        resetTransientState()
        resetSaveProgress()
        baseline = snapshot
    }

    /// 編集中の予定からコピーを始める（仕様 §62・§63）。元の予定は変えない。
    /// 日付と開始時刻は引き継がない。所要時間は引き継ぐ。編集中に直した中身は、そのままコピーの中身になる
    func startCopy() throws {
        guard case .edit(let id) = mode else { throw ScheduleEditorError.copyRequiresEditMode }
        stateBeforeCopy = (snapshot, displayedDay, setsTimesIndividually, baseline)
        let duration = selectedDays.first.flatMap { durationMinutes(on: $0) } ?? commonDurationMinutes
        mode = .copy(sourceID: id)
        content = content.copiedForNewEvent()
        selectedDays = []
        copyPicks = []
        baseDay = nil
        setsTimesIndividually = false
        startMinutes = [:]
        commonDurationMinutes = duration
        durationOverrides = [:]
        plannedEventIDs = [:]
        savedEventsThisSession = []
        resetTransientState()
        // 表示中の日はコピー元の日のまま。コピー先はカレンダーで選んでもらう
    }

    /// 「コピーをやめる」：コピーを押す前の編集の画面へ、そのときの中身のまま戻す（2026-10-14 実機の指摘「コピーをキャンセルする方法がない」。仮）
    func cancelCopy() {
        guard case .copy = mode, let saved = stateBeforeCopy else { return }
        mode = saved.snapshot.mode
        content = saved.snapshot.content
        selectedDays = saved.snapshot.selectedDays
        baseDay = saved.snapshot.baseDay
        startMinutes = saved.snapshot.startMinutes
        commonDurationMinutes = saved.snapshot.commonDurationMinutes
        durationOverrides = saved.snapshot.durationOverrides
        displayedDay = saved.displayedDay
        setsTimesIndividually = saved.setsTimesIndividually
        copyPicks = []
        resetTransientState()
        baseline = saved.baseline
        stateBeforeCopy = nil
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
    /// 「同じ内容で追加」を開かなくてよい（あの行は一括／個別の時刻の切り替えに使う）。コピー元の日は選べない（2026-10-14 ユーザー決定）。
    /// 足した日を左上に出す（最後に選んだコピー先。2026-10-14 決定 G1）
    func toggleCopyDestination(_ day: CalendarDay) {
        guard isChoosingCopyDestinations, !areAppleFieldsLocked, day != copySourceDay else { return }
        if selectedDays.contains(day) {
            removeDay(day)
        } else {
            addDay(day)
            if selectedDays.contains(day) { displayedDay = day }
        }
    }

    /// 同じ内容で日を足す（新規・コピーのみ）。「一括」なら開始時刻も同じものを入れる。「個別」なら時刻は日ごとに決めてもらう。
    /// 所要時間は全部の日に共通の値が入る（Q1）。まだ何も選んでいなければ、その日を選ぶ
    func addDay(_ day: CalendarDay) {
        guard mode.allowsMultipleDays, !selectedDays.contains(day), day != copySourceDay else { return }
        if selectedDays.isEmpty {
            selectDay(day)
        } else {
            selectedDays = (selectedDays + [day]).sorted()
            if !setsTimesIndividually, let start = sharedStartMinute {
                startMinutes[day] = start
            }
        }
        if isChoosingCopyDestinations && selectedDays.contains(day) {
            copyPicks.append(day)
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
    /// 左上に出していた日を外したら、新規では最初に選んだ日を出す。コピーでは直前に選んだ残りのコピー先へ移り、
    /// コピー先が 0 件ならコピー元の日へ戻る（2026-10-14 決定 G1）
    func removeDay(_ day: CalendarDay) {
        guard mode.allowsMultipleDays, selectedDays.contains(day),
              day != baseDay || isChoosingCopyDestinations else { return }
        selectedDays.removeAll { $0 == day }
        startMinutes[day] = nil
        durationOverrides[day] = nil
        copyPicks.removeAll { $0 == day }
        if baseDay == day { baseDay = selectedDays.first }
        if displayedDay == day {
            displayedDay = isChoosingCopyDestinations ? (copyPicks.last ?? copySourceDay) : (baseDay ?? day)
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
    /// 繰り返し予定の編集では、scope の範囲（この予定のみ／これ以降／すべて）で直す（Q44）。
    /// 複数日の一部だけ保存できた・結果を確かめられなかったときは、知らせを作って partiallySaved を投げる（spec §89.9）
    @discardableResult
    func save(scope: RecurrenceScope = .thisEvent) throws -> [CalendarEvent] {
        // 済んだあとの押し直し（続けて 2 回押したなど）では、もう書かない
        guard !isFinished else { throw ScheduleEditorError.alreadySaved }
        let issues = saveIssues
        guard issues.isEmpty else {
            present(issues)
            throw ScheduleEditorError.notReady(issues)
        }
        // Apple カレンダーへ書くときは、何かを書く前に保存先を確かめる。使えなければ何も書かずに止め、理由を出す（spec §89.4）
        if case .unavailable(let problem, let source)? = pendingSaveTarget {
            failure = .saveTarget(problem, source: source, systemDefaultLabel: saveTargets.systemDefaultLabel,
                                  action: .save, canChooseInRow: showsCalendarRow && !isLocked(.calendar))
            throw problem
        }
        do {
            return try performSave(scope: scope)
        } catch ScheduleEditorError.partiallySaved {
            // 知らせはもう作ってある
            throw ScheduleEditorError.partiallySaved
        } catch {
            failure = describeFailure(error, action: .save)
            throw error
        }
    }

    /// 書き込みそのもの（save から呼ぶ）
    private func performSave(scope: RecurrenceScope) throws -> [CalendarEvent] {
        let saved: [CalendarEvent]
        /// 保存する TimyCue の情報（到着目標など）。繰り返しはシリーズ共通の設定と回ごとの個別上書きを分ける（追加仕様書 §2.7.1・Q53）
        var entries: [UUID: TimyCueEventMetadata] = [:]
        switch mode {
        case .new, .copy:
            // 日ごとの id を決めておく（押し直しでも同じ id）。1 日ずつ書いて、日ごとの結果を受け取る（spec §89.9）
            for day in selectedDays where plannedEventIDs[day] == nil { plannedEventIDs[day] = UUID() }
            let drafts = draftEvents
            var common = content.metadata
            common.overrides = nil
            // 途中でアプリが終わっても、次に開いたときに結び付け直して設定を当てられるよう、書く前に記録する
            journal.begin(drafts.map { journalEntry(for: $0, metadata: common, movedFrom: nil) })
            let report = repository.insertEach(drafts)
            journal.markCreated(Set(report.saved.map(\.id)))
            // 書いていない日・結果不明の日（その場で知らせて確かめてもらう）の記録は消す
            journal.finish(Set((report.notSaved + report.unknown).map(\.id)))
            for event in report.saved {
                entries[event.id] = common
                if event.repeatRule.isRepeating, let seriesID = repository.seriesID(of: event.id) {
                    entries[seriesID] = common
                }
            }
            savedEventsThisSession += report.saved
            guard report.isComplete else {
                // 書けた日の設定は保存しておく（保存できなければ、あとでもう一度）
                let settingsSaved = saveMetadata(entries) == nil
                // 何も書いていないと確かめられた：今までどおりの失敗。入力はそのまま
                if report.saved.isEmpty && report.unknown.isEmpty {
                    throw report.error ?? WriteCheckError.unconfirmed
                }
                reportPartialSave(report, settingsSaved: settingsSaved)
                throw ScheduleEditorError.partiallySaved
            }
            saved = report.saved
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
            var before = metadataByEventID[id] ?? TimyCueEventMetadata()
            // 場所なしの予定は、開いたときに通知を開始の基準へ置き換えて出している（2026-10-14 決定 C3）。
            // その置き換えはユーザーの変更ではないので、元の値も同じように置き換えてから比べる（繰り返しの回ごとの上書きを作らない）
            if (original.locationName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                before.notifications = before.notifications.converted(hasPlace: false)
            }
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
        // 予定は書けている。設定を保存できなくても失敗にはせず（押し直しで予定をもう 1 組作らない）、あとでもう一度保存する
        let metadataError = saveMetadata(entries)
        // ただし、書き込めないカレンダーの予定は TimyCue の設定だけが変更なので、保存できなければ失敗（何も変えていない）
        if let metadataError, mode.isEdit, areAppleFieldsLocked {
            for key in entries.keys { pendingMetadata[key] = nil }
            throw metadataError
        }
        if mode.isEdit { savedEventsThisSession = saved }
        let settingsSaved = metadataError == nil

        reloadEvents()
        showsSaveIssue = false
        failure = settingsSaved ? nil : .settingsNotSaved(isEdit: mode.isEdit)
        baseline = snapshot
        isFinished = true
        return saved
    }

    /// 一部だけ書けた・結果を確かめられなかったとき：書けた日と結果不明の日を選んだ日から外し（押し直しで重ねて書かない・
    /// 確かめずに書き直さない）、書いていない日だけを残して知らせる。残る日がなければ、知らせのあと閉じる（spec §89.9）
    private func reportPartialSave(_ report: InsertReport, settingsSaved: Bool) {
        dropDays(Set((report.saved + report.unknown).map(\.day)))
        reloadEvents()
        showsSaveIssue = false
        if selectedDays.isEmpty { isFinished = true }
        failure = .partialSave(saved: report.saved.map(\.day), notSaved: report.notSaved.map(\.day),
                               unknown: report.unknown.map(\.day), settingsSaved: settingsSaved)
    }

    /// 保存が済んだ日（と結果不明の日）を、選んだ日から外す（新規の最初の日も外す）
    private func dropDays(_ days: Set<CalendarDay>) {
        selectedDays.removeAll { days.contains($0) }
        for day in days {
            startMinutes[day] = nil
            durationOverrides[day] = nil
            plannedEventIDs[day] = nil
        }
        copyPicks.removeAll { days.contains($0) }
        if let base = baseDay, days.contains(base) { baseDay = selectedDays.first }
        if let shown = displayedDay, days.contains(shown) { displayedDay = baseDay ?? selectedDays.first ?? shown }
    }

    /// TimyCue の設定を保存する。前に保存できなかった分も一緒に保存する。保存できなければ、あとでもう一度保存するよう残して、その失敗を返す
    private func saveMetadata(_ entries: [UUID: TimyCueEventMetadata]) -> Error? {
        let all = pendingMetadata.merging(entries) { _, new in new }
        guard !all.isEmpty else { return nil }
        do {
            try SaveFaults.check(.metadataWrite)
            try metadataRepository.saveAll(all)
            pendingMetadata = [:]
            journal.markMetadataSaved(Set(all.keys))
            settleJournal()
            return nil
        } catch {
            pendingMetadata = all
            return error
        }
    }

    /// 保存の途中の記録 1 件（新しい予定・「Apple Calendarに保存」）
    private func journalEntry(for event: CalendarEvent, metadata: TimyCueEventMetadata, movedFrom: UUID?) -> SaveJournalEntry {
        SaveJournalEntry(id: event.id, title: event.title, day: event.day, startMinute: event.startMinute,
                         endUnset: event.durationMinutes == nil && !event.isAllDay, metadata: metadata,
                         isApple: isConnectedToApple || movedFrom != nil, appleKey: nil, movedFromLocalID: movedFrom,
                         created: nil, metadataSaved: nil, createdAt: Date())
    }

    /// 書けて、設定も結び付けも保存できた新しい予定の記録を消す（「Apple Calendarに保存」の記録は、元の予定を消したときに消す）。
    /// Apple の予定の記録は、Apple とつないで前回の分を復旧したあと（結び付けを持つ保存先のとき）だけ消す。
    /// 起動してすぐ（つなぐ前）に消すと、結び付けを書けないまま終わった予定を次に開いたときに結び付け直せない
    private func settleJournal() {
        guard !repository.hasUnsavedLinks else { return }
        let canSettleApple = repository.managesAppleLinks
        let done = journal.entries.filter {
            $0.movedFromLocalID == nil && $0.created == true && $0.metadataSaved == true && (!$0.isApple || canSettleApple)
        }
        journal.finish(Set(done.map(\.id)))
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
        do {
            try repository.delete(id: id, scope: effectiveScope)
        } catch {
            failure = describeFailure(error, action: .delete)
            throw error
        }
        // 予定は消せた。設定の削除に失敗しても、失敗にはしない（残った設定は使われない。spec §89.9）
        try? metadataRepository.deleteAll(removed)
        pendingMetadata = pendingMetadata.filter { !removed.contains($0.key) }
        reloadEvents()
        startNew(on: day)
    }

    // MARK: - ローカル予定を Apple カレンダーへ移す（追加仕様書 §1.12）

    /// 編集している予定が、つなぐ前から TimyCue の中にあった予定で、Apple カレンダーとつないでいるか（ボタンを出すか）。
    /// 自動・一括では移さない。編集画面でユーザーが「Apple Calendarに保存」を選んだときだけ移す
    var canMoveToAppleCalendar: Bool {
        guard case .edit(let id) = mode, isConnectedToApple,
              let event = events.first(where: { $0.id == id }) else { return false }
        return event.source == .timyCue
    }

    /// 「Apple Calendarに保存」の移す先（予定ごとの指定 → 設定の既定 → iPhone の既定。spec §89.5）
    var moveToAppleTarget: SaveTargetResolution? {
        guard canMoveToAppleCalendar else { return nil }
        return saveTargets.resolve(eventCalendarID: content.calendarID)
    }

    /// 移す先が使えないときに、ボタンを押せなくして出す理由（spec §89.5：移す先がなければ無効にして理由を案内する）
    var moveToAppleUnavailableReason: String? {
        guard let target = moveToAppleTarget, let problem = target.problem else { return nil }
        if saveTargetCandidates.isEmpty {
            return "移せる Apple カレンダーがありません。設定 ＞ カレンダー連携 で表示を ON にしてください（表示のみのカレンダーには移せません）。"
        }
        let place = showsCalendarRow ? "「カレンダー」の行か、設定 ＞ カレンダー連携 で" : "設定 ＞ カレンダー連携 で"
        return "移す先の「\(saveTargets.name(for: target))」には移せません（\(SaveTargetRules.shortReason(problem))）。\(place)選び直してください。"
    }

    /// 前回の「Apple Calendarに保存」の結果を確かめられなかった予定か（押したら、確かめたかを先に聞く）。
    /// Apple に作れたか分からない・作ったはずの予定が見当たらないとき
    var moveNeedsConfirmation: Bool {
        guard case .edit(let id) = mode, let record = journal.move(from: id) else { return false }
        return !(record.created == true && repository.containsEvent(id: record.id))
    }

    /// 「Apple Calendarに保存」：今の内容で Apple カレンダーに新しく作り、TimyCue の設定を引き継いで、
    /// 元のローカル予定を消す（二重に出さない）。作った予定を返す。
    /// 前回作れたか確かめられなかった予定は、confirmedUnknown（確かめたと答えた）のときだけ作る（spec §89.9）
    @discardableResult
    func moveToAppleCalendar(confirmedUnknown: Bool = false) throws -> CalendarEvent {
        guard !isFinished else { throw ScheduleEditorError.alreadySaved }
        guard !moveNeedsConfirmation || confirmedUnknown else { throw ScheduleEditorError.needsConfirmation }
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
        // 移す先が使えなければ、何も作らず、元の予定も消さずに止める（spec §89.5）
        if case .unavailable(let problem, let source)? = moveToAppleTarget {
            failure = .saveTarget(problem, source: source, systemDefaultLabel: saveTargets.systemDefaultLabel,
                                  action: .moveToApple, canChooseInRow: showsCalendarRow)
            throw problem
        }
        do {
            return try performMove(from: id, original: original, day: day, start: start)
        } catch ScheduleEditorError.partiallySaved {
            // 知らせはもう作ってある
            throw ScheduleEditorError.partiallySaved
        } catch {
            failure = describeFailure(error, action: .moveToApple)
            throw error
        }
    }

    /// 移すことそのもの（moveToAppleCalendar から呼ぶ）。保存先の確かめ（呼ぶ前）→ Apple に作る → 作れたか確かめる →
    /// 設定を引き継ぐ → 元のローカル予定を消す の順（spec §89.5・§89.9）。Apple に作れたあとで失敗したら、元の予定は消さずに
    /// 両方を残し、どちらも自動では消さない。押し直しでは Apple に作り直さず、今の内容で直してから続きを行う
    private func performMove(from id: UUID, original: CalendarEvent, day: CalendarDay, start: MinuteOfDay) throws -> CalendarEvent {
        let record = journal.move(from: id)
        // 前に Apple に作った予定（読み込んだ範囲によらず、結び付けで引く）
        let earlierID: UUID? = record.flatMap { $0.created == true && repository.containsEvent(id: $0.id) ? $0.id : nil }
        let moved = content.makeEvent(id: earlierID ?? UUID(),
                                      day: day,
                                      startMinute: start,
                                      durationMinutes: durationMinutes(on: day),
                                      isAllDay: original.isAllDay,
                                      source: .appleCalendar)
        if earlierID != nil {
            // 前に作った Apple の予定を今の内容に直す。直せなくても、作り直さない（両方に残る。押し直せば、また続きから行う）
            do {
                try repository.update(moved)
            } catch {
                journal.markNoticed([moved.id])
                reloadEvents()
                failure = .moveResumeFailed(unconfirmed: (error as? WriteCheckError) == .unconfirmed)
                throw ScheduleEditorError.partiallySaved
            }
        } else {
            var settings = content.metadata
            settings.overrides = nil
            // 確かめたうえで作り直すときは、前の記録を使わない。書く前に記録する（途中で終わったら、次に開いたときに続きか確かめ）
            if let record { journal.finish([record.id]) }
            journal.begin([journalEntry(for: moved, metadata: settings, movedFrom: id)])
            let report = repository.insertEach([moved])
            // 結果不明：記録は残す（次に移すときは、確かめたかを聞く）
            if !report.unknown.isEmpty {
                journal.markNoticed([moved.id])
                throw stopMove(.moveUnconfirmed(), moved: nil)
            }
            guard report.isComplete else {
                journal.finish([moved.id])
                throw report.error ?? WriteCheckError.unconfirmed
            }
            journal.markCreated([moved.id])
        }
        var settings = content.metadata
        settings.overrides = nil
        var entries = [moved.id: settings]
        if moved.repeatRule.isRepeating, let seriesID = repository.seriesID(of: moved.id) { entries[seriesID] = settings }
        // 設定を引き継げなかったら、元の予定（設定を持っている）を消さない
        guard saveMetadata(entries) == nil else {
            journal.markNoticed([moved.id])
            throw stopMove(.moveIncomplete(settingsCopied: false), moved: moved)
        }
        do {
            try SaveFaults.check(.moveAfterAppleWrite)
            try repository.delete(id: id)
        } catch {
            journal.markNoticed([moved.id])
            throw stopMove(.moveIncomplete(settingsCopied: true), moved: moved)
        }
        // 結び付けをファイルに書けていなければ、記録を残す（次に開いたときに鍵で結び付け直す。元の予定はもうないので、そのあと消す）
        if !repository.hasUnsavedLinks { journal.finish([moved.id]) }
        // 元の予定は消せた。その設定の削除に失敗しても、失敗にはしない（残った設定は使われない）
        try? metadataRepository.delete(for: id)
        pendingMetadata[id] = nil

        reloadEvents()
        mode = .edit(eventID: moved.id)
        showsSaveIssue = false
        failure = nil
        baseline = snapshot
        isFinished = true
        savedEventsThisSession = [moved]
        return moved
    }

    /// 「Apple Calendarに保存」が途中で止まったとき：両方の予定を残したまま知らせ、知らせのあと閉じる（その場で押し直させない）
    private func stopMove(_ notice: EditorFailure, moved: CalendarEvent?) -> ScheduleEditorError {
        reloadEvents()
        showsSaveIssue = false
        failure = notice
        isFinished = true
        savedEventsThisSession = moved.map { [$0] } ?? []
        return .partiallySaved
    }

    /// 失敗の知らせを閉じた
    func dismissFailure() {
        failure = nil
    }

    /// 失敗の中身を、知らせる文に分ける。保存先が使えないのに Apple 側で気づいたとき（ほかの画面で設定が変わった直後など）も、理由を出す
    private func describeFailure(_ error: Error, action: EditorFailure.Action) -> EditorFailure {
        if let problem = error as? SaveTargetProblem {
            return .saveTarget(problem, source: (action == .moveToApple ? moveToAppleTarget : pendingSaveTarget)?.source ?? .event,
                               systemDefaultLabel: saveTargets.systemDefaultLabel, action: action,
                               canChooseInRow: showsCalendarRow && !isLocked(.calendar))
        }
        if let editorError = error as? ScheduleEditorError, case .eventNotFound = editorError { return .eventMissing(action: action) }
        if error is EventRepositoryError { return .eventMissing(action: action) }
        // 書けたか・消せたか確かめられなかった（失敗とは言わない）
        if (error as? WriteCheckError) == .unconfirmed { return .unconfirmed(action: action) }
        // 編集の保存の失敗（Apple の予定は、直ったかどうかをその場で確かめられない）
        if action == .save, mode.isEdit {
            return .updateFailed(isAppleEvent: editingEvent?.source == .appleCalendar && !areAppleFieldsLocked)
        }
        // 書いていないと確かめた・書く前に止まった
        return .notWritten(action: action)
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
        failure = nil
    }

    /// 新規・編集を始め直すとき：保存の進み具合を消す（前に保存できなかった設定と、「Apple Calendarに保存」の途中の記録は残す）
    private func resetSaveProgress() {
        plannedEventIDs = [:]
        savedEventsThisSession = []
        isFinished = false
    }

    /// 読み直す。前に保存できなかった TimyCue の設定があれば、先にもう一度保存する。
    /// それでも保存できなければ、画面にはその値を出す（開き直して保存したとき、古い値で上書きしない）
    private func reloadEvents() {
        if !pendingMetadata.isEmpty, (try? metadataRepository.saveAll(pendingMetadata)) != nil {
            journal.markMetadataSaved(Set(pendingMetadata.keys))
            pendingMetadata = [:]
        }
        settleJournal()
        events = repository.allEvents()
        metadataByEventID = metadataRepository.allMetadata().merging(pendingMetadata) { _, pending in pending }
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
