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

    @ObservationIgnored private let eventStore: EKEventStore
    @ObservationIgnored private let switchable: SwitchableEventRepository
    @ObservationIgnored private let localEvents: FileEventRepository?
    @ObservationIgnored private let metadata: EventMetadataRepository
    @ObservationIgnored private let preferencesFile: JSONFile<CalendarPreferences>
    @ObservationIgnored private var eventKit: EventKitEventRepository?
    /// カレンダーの一覧（書き込めないものも含む）と、既定の保存先を知らせる
    @ObservationIgnored private let onChange: @MainActor ([CalendarChoice], String?) -> Void

    /// localEvents が nil のとき（DEBUG の見本の予定で動かしているとき）は、つながない。
    /// 開発用・見本の予定を Apple カレンダーへ書き込まないため（Q34）
    init(eventStore: EKEventStore,
         switchable: SwitchableEventRepository,
         localEvents: FileEventRepository?,
         metadata: EventMetadataRepository,
         preferencesFile: JSONFile<CalendarPreferences> = JSONFile(url: JSONFile<CalendarPreferences>.appSupportURL(named: "calendar-preferences.json"), empty: CalendarPreferences()),
         onChange: @escaping @MainActor (_ calendars: [CalendarChoice], _ defaultCalendarID: String?) -> Void) {
        self.eventStore = eventStore
        self.switchable = switchable
        self.localEvents = localEvents
        self.metadata = metadata
        self.preferencesFile = preferencesFile
        self.onChange = onChange
        preferences = preferencesFile.load()
        // 初期化が済むまでは self のプロパティを読めないので、いったん手元に置く
        let status = EKEventStore.authorizationStatus(for: .event)
        authorization = status
        state = Self.state(for: status)
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
    func dismissGuidance() {
        preferences.guidanceDismissCount = (preferences.guidanceDismissCount ?? 0) + 1
        savePreferences()
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
        checkDefaultCalendar()
        eventKit.reloadCache()
        notify()
    }

    // MARK: - 既定の保存先が使えなくなったとき（v1.2「Apple Calendar」）

    /// 既定の保存先から iPhone の既定へ切り替えたことを、まだ知らせていないか
    var showsSaveTargetNotice: Bool {
        preferences.pendingFallbackNotice == true
    }

    var saveTargetNoticeMessage: String {
        let name = writableCalendars.first { $0.id == defaultSaveCalendarID }.map { "「\($0.title)」" } ?? ""
        return "既定の保存先にしていたカレンダーが使えなくなったため、新しい予定は iPhone の既定のカレンダー\(name)に保存します。保存先は 設定 ＞ カレンダー連携 で変えられます。"
    }

    /// 知らせ終わった。同じことでは二度と知らせない
    func dismissSaveTargetNotice() {
        guard preferences.pendingFallbackNotice != nil else { return }
        preferences.pendingFallbackNotice = nil
        savePreferences()
    }

    // MARK: - 設定 ＞ カレンダー連携

    /// 新しい予定の既定の保存先を変える（Q32）。nil で iPhone の既定に戻す
    func setDefaultCalendar(_ calendarID: String?) {
        preferences.defaultCalendarID = calendarID
        savePreferences()
        notify()
    }

    /// そのカレンダーを読み込むかどうか（Q33）
    func setShown(_ shown: Bool, calendarID: String) {
        if shown {
            preferences.hiddenCalendarIDs.remove(calendarID)
        } else {
            preferences.hiddenCalendarIDs.insert(calendarID)
        }
        savePreferences()
        eventKit?.reloadCache()
        notify()
    }

    /// 書き込めるカレンダー（予定の保存先にできるもの）
    var writableCalendars: [CalendarChoice] {
        calendars.filter(\.isWritable)
    }

    /// 新しい予定の保存先（設定の既定 → iPhone の既定）
    var defaultSaveCalendarID: String? {
        CalendarPreferences.saveTarget(eventCalendarID: nil, preferences: preferences,
                                       systemDefaultID: systemDefaultCalendarID, writable: writableCalendars)
    }

    // MARK: - 重複候補（Q42-8・Q50）

    /// ホームに一度だけ出す、強制しない案内：まだ知らせていない重複候補がある
    var showsDuplicateNotice: Bool {
        let notified = preferences.notifiedDuplicates ?? []
        return duplicateCandidates.contains { !notified.contains($0.id) }
    }

    /// ホームの案内を見た（［確認］か閉じる）。今ある候補は、もうホームでは知らせない
    func markDuplicatesNotified() {
        var notified = preferences.notifiedDuplicates ?? []
        notified.formUnion(duplicateCandidates.map(\.id))
        preferences.notifiedDuplicates = notified
        savePreferences()
    }

    /// 「両方残す」：両方を独立した予定として持ち、同じ組はもう重複候補として聞かない
    func keepBoth(_ candidate: DuplicateCandidate) {
        var kept = preferences.keptBothDuplicates ?? []
        kept.insert(candidate.id)
        preferences.keptBothDuplicates = kept
        savePreferences()
        refreshDuplicates()
    }

    /// 「Apple Calendarの予定を使う」で、両方に付いた TimyCue の設定がぶつかるか（ぶつかるなら、どちらを使うか先に聞く）
    func settingsConflict(_ candidate: DuplicateCandidate) -> Bool {
        let all = metadata.allMetadata()
        return DuplicateCandidates.settingsConflict(local: all[candidate.local.id], apple: all[candidate.apple.id])
    }

    /// 「Apple Calendarの予定を使う」：ローカル予定の TimyCue の設定をできるだけ Apple の予定へ引き継いでから、
    /// ローカル予定を削除する（隠すのではなく削除。Apple の予定を正本にする）
    func useApple(_ candidate: DuplicateCandidate, preferLocalSettings: Bool? = nil) throws {
        guard let localEvents else { return }
        let all = metadata.allMetadata()
        let merged = DuplicateCandidates.mergedMetadata(local: all[candidate.local.id],
                                                        apple: all[candidate.apple.id],
                                                        preferLocal: preferLocalSettings)
        try metadata.save(merged, for: candidate.apple.id)
        try localEvents.delete(id: candidate.local.id)
        try metadata.delete(for: candidate.local.id)
        notify()
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
                                                 preferences: { [weak self] in self?.preferences ?? CalendarPreferences() })
        // 予定は裏で読むので、読み終わったら画面を描き直す
        repository.onLoaded = { [weak self] in self?.notify() }
        eventKit = repository
        calendars = repository.calendars()
        systemDefaultCalendarID = repository.systemDefaultCalendarID
        checkDefaultCalendar()
        switchable.use(CombinedEventRepository(primary: repository, local: localEvents))
        notify()
    }

    /// 既定の保存先がまだ書き込めるか確かめ、使えなければ iPhone の既定へ戻して、知らせる印を付ける
    private func checkDefaultCalendar() {
        if preferences.dropUnavailableDefault(writable: writableCalendars) {
            savePreferences()
        }
    }

    private func savePreferences() {
        try? preferencesFile.save(preferences)
    }

    private func notify() {
        refreshDuplicates()
        onChange(calendars, defaultSaveCalendarID)
    }
}
