import EventKit
import Observation
import SwiftUI

/// Apple カレンダーとつなぐ状態（仕様 §68・§79・§80・Q31〜Q36）。
/// 許可は初回に全部求めず、TimyCue で初めてカレンダー連携が必要になったときに求める（Q31）。
/// つないだあとの状態の確認・変更は 設定 ＞ カレンダー連携 で行う。
/// 許可しなくても、TimyCue で作った予定は端末の中に保存して使える（§80）
@MainActor
@Observable
final class CalendarConnection {
    enum State: Equatable {
        /// まだ求めていない
        case notAsked
        /// つないでいる
        case connected
        /// 許可されなかった（設定アプリから許可できる）
        case denied
        /// 端末の制限で使えない
        case restricted
    }

    private(set) var state: State
    /// iOS のカレンダーの許可の状態そのもの（設定トップに「接続済み」「一部許可」などと出すため）
    private(set) var authorization: EKAuthorizationStatus
    /// 見えるカレンダー（つないでいるときだけ）
    private(set) var calendars: [CalendarChoice] = []
    private(set) var preferences: CalendarPreferences
    /// iPhone の「新規イベントのデフォルトカレンダー」
    private(set) var systemDefaultCalendarID: String?
    /// TimyCue のローカル予定と Apple カレンダーの予定の重複候補（Q42-8・Q50）。同期のたびに見直す
    private(set) var duplicateCandidates: [DuplicateCandidate] = []
    /// 設定を保存できなかったときの知らせ（変更は元に戻してある。spec §89.9）。失敗のたびに別の値にする
    private(set) var settingsFailure: SettingsFailure?
    /// 設定を保存できなかった回数。スイッチや選択の行を描き直して、戻した値を見せるのに使う
    private(set) var settingsRevision = 0
    /// 前回、予定の保存の途中でアプリが終わっていて、確かめてもらうことがあるときの知らせ（spec §89.9）
    private(set) var recoveryNotice: String?

    @ObservationIgnored private let eventStore: EKEventStore
    @ObservationIgnored private let switchable: SwitchableEventRepository
    @ObservationIgnored private let localEvents: FileEventRepository?
    @ObservationIgnored private let metadata: EventMetadataRepository
    @ObservationIgnored private let preferencesFile: JSONFile<CalendarPreferences>
    /// 保存の途中の記録（作成画面と同じもの。spec §89.9）
    @ObservationIgnored private let journal: SaveJournal
    @ObservationIgnored private var eventKit: EventKitEventRepository?
    /// カレンダーの一覧（書き込めないものも含む。表示のみは手で直した分を当てたもの）と、保存先の決まりを知らせる
    @ObservationIgnored private let onChange: @MainActor ([CalendarChoice], SaveTargetRules) -> Void

    /// localEvents が nil のとき（DEBUG の見本の予定で動かしているとき）は、つながない。
    /// 開発用・見本の予定を Apple カレンダーへ書き込まないため（Q34）
    init(eventStore: EKEventStore,
         switchable: SwitchableEventRepository,
         localEvents: FileEventRepository?,
         metadata: EventMetadataRepository,
         preferencesFile: JSONFile<CalendarPreferences> = JSONFile(url: JSONFile<CalendarPreferences>.appSupportURL(named: "calendar-preferences.json"),
                                                                   empty: CalendarPreferences(), faultPoint: .settingsWrite),
         journal: SaveJournal = .inMemory(),
         onChange: @escaping @MainActor (_ calendars: [CalendarChoice], _ saveTargets: SaveTargetRules) -> Void) {
        self.eventStore = eventStore
        self.switchable = switchable
        self.localEvents = localEvents
        self.metadata = metadata
        self.preferencesFile = preferencesFile
        self.journal = journal
        self.onChange = onChange
        preferences = preferencesFile.load()
        // 初期化が済むまでは self のプロパティを読めないので、いったん手元に置く
        let status = EKEventStore.authorizationStatus(for: .event)
        authorization = status
        state = Self.state(for: status)
        recoverLocalSaves()
        if state == .connected { useEventKit() }
    }

    static func state(for status: EKAuthorizationStatus) -> State {
        switch status {
        case .fullAccess, .authorized: .connected
        case .denied, .writeOnly: .denied
        case .restricted: .restricted
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }

    /// 設定トップの「カレンダー連携」の右に出す今の状態（v1.2「設定画面」）
    var statusLabel: String { Self.statusLabel(for: authorization) }

    static func statusLabel(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess, .authorized: "接続済み"
        case .writeOnly: "一部許可"
        case .denied: "許可が必要"
        case .restricted: "利用できません"
        case .notDetermined: "未接続"
        @unknown default: "未接続"
        }
    }

    // MARK: - 案内（Q38）

    /// 本物の保存先で動いているか。DEBUG の見本の予定ではつながず、案内も出さない
    var isLive: Bool { localEvents != nil }

    /// 初回の案内（「カレンダーを連携すると、予定から出発時刻を計算できます」と「カレンダーを連携」）を出すか。
    /// まだ許可を求めておらず、案内を一度も「あとで」にしていないとき（Q38）
    var showsFirstGuidance: Bool {
        isLive && state == .notAsked && (preferences.guidanceDismissCount ?? 0) == 0
    }

    /// 初回の案内を「あとで」にしたあと、次に Apple カレンダーが実際に必要になる操作（新しい予定の保存）で、もう一度だけ案内するか（Q38。
    /// 二度目も「あとで」なら、それ以上は自分からは案内しない。設定 ＞ カレンダー連携 からはいつでもつなげる）
    var showsGuidanceBeforeSaving: Bool {
        isLive && state == .notAsked && (preferences.guidanceDismissCount ?? 0) == 1
    }

    /// 案内を「あとで」にする
    /// 保存できなくても知らせない（戻すだけ。次にまた案内が出る。予定の保存の途中で、設定の失敗を混ぜて見せない）
    func dismissGuidance() {
        updatePreferences(reportsFailure: false) { $0.guidanceDismissCount = ($0.guidanceDismissCount ?? 0) + 1 }
    }

    /// 「カレンダーを連携」を押したとき。ここで初めて iOS の許可のダイアログを出す（Q38）。
    /// 自分から何度も出そうとはしない。一度拒否されたら iPhone の設定から許可してもらう
    func connect() async {
        guard localEvents != nil else { return }
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            state = granted ? .connected : .denied
        } catch {
            state = .denied
        }
        authorization = EKEventStore.authorizationStatus(for: .event)
        if state == .connected { useEventKit() }
    }

    /// Apple カレンダー側が変わったとき（§68）。読み直す
    func calendarDidChange() {
        guard state == .connected, let eventKit else { return }
        calendars = eventKit.calendars()
        systemDefaultCalendarID = eventKit.systemDefaultCalendarID
        eventKit.reloadCache()
        notify()
    }

    // MARK: - 設定 ＞ カレンダー連携

    /// 新しい予定の既定の保存先を変える（Q32）。nil で iPhone の既定に戻す
    func setDefaultCalendar(_ calendarID: String?) {
        guard updatePreferences({ $0.defaultCalendarID = calendarID }) else { return }
        notify()
    }

    /// そのカレンダーを読み込むかどうか（Q33）
    func setShown(_ shown: Bool, calendarID: String) {
        let saved = updatePreferences { preferences in
            if shown {
                preferences.hiddenCalendarIDs.remove(calendarID)
            } else {
                preferences.hiddenCalendarIDs.insert(calendarID)
            }
        }
        guard saved else { return }
        eventKit?.reloadCache()
        notify()
    }

    /// 祝日カレンダーとして扱うか（設定 ＞ カレンダー連携 ＞ 祝日カレンダー。Q55）
    func isHolidayCalendar(_ calendar: CalendarChoice) -> Bool {
        preferences.isHolidayCalendar(calendar)
    }

    /// 祝日カレンダーとして扱うかを手で決める。自動の判定より優先する（Q55）
    func setHoliday(_ isHoliday: Bool, calendar: CalendarChoice) {
        guard updatePreferences({ $0.setHoliday(isHoliday, calendarID: calendar.id) }) else { return }
        notify()
    }

    /// 祝日カレンダーとして扱っているカレンダー
    var holidayCalendars: [CalendarChoice] {
        calendars.filter { preferences.isHolidayCalendar($0) }
    }

    /// 新しい予定の保存先の決まり（spec §89.2・§89.4）。使えるのは、表示 ON・書き込める・表示のみでない・今も見えるカレンダーだけ。
    /// 使えなくなっても、設定の既定を消したり、iPhone の既定へ勝手に切り替えたりしない（v1.2 の自動の切り替えは廃止）
    var saveTargets: SaveTargetRules {
        SaveTargetRules(calendars: calendars, preferences: preferences, systemDefaultID: systemDefaultCalendarID)
    }

    // MARK: - 重複候補（Q42-8・Q50）

    /// ホームに一度だけ出す、強制しない案内：まだ知らせていない重複候補がある
    var showsDuplicateNotice: Bool {
        let notified = preferences.notifiedDuplicates ?? []
        return duplicateCandidates.contains { !notified.contains($0.id) }
    }

    /// ホームの案内を見た（［確認］か閉じる）。今ある候補は、もうホームでは知らせない
    /// 保存できなくても知らせない（戻すだけ。次にまた案内が出る。押した「確認」の一覧は開く）
    func markDuplicatesNotified() {
        let ids = duplicateCandidates.map(\.id)
        updatePreferences(reportsFailure: false) { preferences in
            var notified = preferences.notifiedDuplicates ?? []
            notified.formUnion(ids)
            preferences.notifiedDuplicates = notified
        }
    }

    /// 「両方残す」：両方を独立した予定として持ち、同じ組はもう重複候補として聞かない
    func keepBoth(_ candidate: DuplicateCandidate) {
        let saved = updatePreferences { preferences in
            var kept = preferences.keptBothDuplicates ?? []
            kept.insert(candidate.id)
            preferences.keptBothDuplicates = kept
        }
        guard saved else { return }
        refreshDuplicates()
    }

    /// 「Apple Calendarの予定を使う」で、両方に付いた TimyCue の設定がぶつかるか（ぶつかるなら、どちらを使うか先に聞く）
    func settingsConflict(_ candidate: DuplicateCandidate) -> Bool {
        let all = metadata.allMetadata()
        return DuplicateCandidates.settingsConflict(local: all[candidate.local.id], apple: all[candidate.apple.id])
    }

    /// 「Apple Calendarの予定を使う」：ローカル予定の TimyCue の設定をできるだけ Apple の予定へ引き継いでから、
    /// ローカル予定を削除する（隠すのではなく削除。Apple の予定を正本にする）。
    /// 途中で失敗したら、両方の予定を残して投げる（設定の引き継ぎに失敗：何も変えない／ローカル予定の削除に失敗：両方に残る）。
    /// ローカル予定を消せたあとの、その設定の削除の失敗は失敗にしない（残った設定は使われない）。
    /// 成功でも失敗でも、最後に重複候補を作り直す（spec §89.9・2026-10-18 S1b）
    func useApple(_ candidate: DuplicateCandidate, preferLocalSettings: Bool? = nil) throws {
        guard let localEvents else { return }
        defer { notify() }
        // もうローカル予定がなければ、前の操作で済んでいる
        guard localEvents.allEvents().contains(where: { $0.id == candidate.local.id }) else { return }
        let all = metadata.allMetadata()
        let merged = DuplicateCandidates.mergedMetadata(local: all[candidate.local.id],
                                                        apple: all[candidate.apple.id],
                                                        preferLocal: preferLocalSettings)
        try metadata.save(merged, for: candidate.apple.id)
        try localEvents.delete(id: candidate.local.id)
        try? metadata.delete(for: candidate.local.id)
    }

    /// 同期のたびに重複候補を見直す（見つけるのは Apple カレンダーとの同期のとき。Q50）
    private func refreshDuplicates() {
        guard state == .connected, let eventKit, let localEvents else {
            duplicateCandidates = []
            return
        }
        duplicateCandidates = DuplicateCandidates.find(local: localEvents.allEvents(),
                                                       apple: eventKit.allEvents(),
                                                       keptBoth: preferences.keptBothDuplicates ?? [])
    }

    // MARK: - 内部

    /// 保存先を、Apple カレンダーとつなぐ前から TimyCue の中にあった予定と Apple カレンダーの両方にする。
    /// TimyCue の中の予定は Apple カレンダーへ移さない・複製しない（Q34）
    private func useEventKit() {
        guard let localEvents else { return }
        let repository = EventKitEventRepository(store: eventStore, metadata: metadata,
                                                 preferences: { [weak self] in self?.preferences ?? CalendarPreferences() },
                                                 journal: journal)
        // 前回の保存の途中で終わっていたら、読み込みを始める前に結び付け直す（spec §89.9）
        noteRecovery(askUser: repository.recover(), localEvents: localEvents, linksSaved: !repository.hasUnsavedLinks)
        // 予定は裏で読むので、読み終わったら画面を描き直す
        repository.onLoaded = { [weak self] in self?.notify() }
        eventKit = repository
        calendars = repository.calendars()
        systemDefaultCalendarID = repository.systemDefaultCalendarID
        switchable.use(CombinedEventRepository(primary: repository, local: localEvents))
        notify()
    }

    /// 設定を変えて保存する。保存できなければ変更前の値のままにし、知らせる（変更済みと誤って見せない。読み直しより前に戻す。spec §89.9）。
    /// 案内を閉じた印のような、ユーザーが設定として変えたのではないものは `reportsFailure: false`（戻すだけ）
    @discardableResult
    private func updatePreferences(reportsFailure: Bool = true, _ change: (inout CalendarPreferences) -> Void) -> Bool {
        var next = preferences
        change(&next)
        do {
            try preferencesFile.save(next)
            preferences = next
            return true
        } catch {
            settingsRevision += 1
            if reportsFailure {
                settingsFailure = SettingsFailure(message: "変更は反映していません。もう一度お試しください。")
            }
            return false
        }
    }

    /// 設定の保存の失敗の知らせを閉じた
    func dismissSettingsFailure() {
        settingsFailure = nil
    }

    // MARK: - 保存の途中で終わったあとの復旧（spec §89.9・2026-10-18 S1b 指示 5）

    /// 前回、この iPhone の中への保存の途中でアプリが終わっていたら、書けた予定に、まだ保存していない設定を当てる。
    /// 端末の中の保存は、書けたか書けていないかのどちらかなので、確かめてもらうことはない
    private func recoverLocalSaves() {
        guard let localEvents else { return }
        let ids = Set(localEvents.allEvents().map(\.id))
        var finished = Set<UUID>()
        for entry in journal.entries where !entry.isApple {
            if ids.contains(entry.id), entry.metadataSaved != true, let settings = entry.metadata {
                // 当てられなければ、次に開いたときにもう一度
                guard (try? metadata.save(settings, for: entry.id)) != nil else { continue }
            }
            finished.insert(entry.id)
        }
        journal.finish(finished)
    }

    /// 確かめてもらうことを知らせに書く。「Apple Calendarに保存」が途中までで、元の予定も残っているものも書く。
    /// 元の予定がもうない「Apple Calendarに保存」の記録は、済んでいるので消す
    private func noteRecovery(askUser: [SaveJournalEntry], localEvents: FileEventRepository, linksSaved: Bool) {
        let localIDs = Set(localEvents.allEvents().map(\.id))
        let moves = journal.entries.filter { $0.movedFromLocalID != nil }
        // 元の予定がもうない記録は済んでいるので消す。ただし Apple に作った記録は、結び付けをファイルに書けたときだけ
        // （書けなければ、次に開いたときにもう一度結び付け直す）
        journal.finish(Set(moves.filter { !localIDs.contains($0.movedFromLocalID!) && ($0.created != true || linksSaved) }.map(\.id)))
        // 同じことを起動のたびに知らせない（その場で知らせたもの・前に知らせたものは出さない）
        var lines: [String] = []
        var noticed = Set<UUID>()
        for entry in askUser where entry.noticed != true {
            if let localID = entry.movedFromLocalID {
                guard localIDs.contains(localID) else { continue }
                lines.append("\(entry.label)：「Apple Calendarに保存」の途中でした。Apple Calendarに同じ予定があるか確かめてください。")
            } else {
                lines.append("\(entry.label)：Apple カレンダーに保存されているか確かめてください。")
            }
            noticed.insert(entry.id)
        }
        let asked = Set(askUser.map(\.id))
        for entry in journal.entries where entry.created == true && entry.noticed != true && !asked.contains(entry.id) {
            guard let localID = entry.movedFromLocalID, localIDs.contains(localID) else { continue }
            lines.append("\(entry.label)：Apple Calendarに作ってあり、TimyCue の中の予定も残っています。もう一度「Apple Calendarに保存」を押すと、作り直さずに続きを行います。")
            noticed.insert(entry.id)
        }
        journal.markNoticed(noticed)
        guard !lines.isEmpty else { return }
        recoveryNotice = (["前回、予定の保存の途中でアプリが終わりました。重複を防ぐため、自動では保存し直していません。"] + lines)
            .joined(separator: "\n")
    }

    /// 復旧の知らせを閉じた
    func dismissRecoveryNotice() {
        recoveryNotice = nil
    }

    private func notify() {
        refreshDuplicates()
        // 祝日カレンダーは、手で直した分を当ててから渡す（Q55）
        let resolved = calendars.map { calendar in
            var copy = calendar
            copy.isHolidays = preferences.isHolidayCalendar(calendar)
            return copy
        }
        onChange(resolved, saveTargets)
    }
}
