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
    /// 見えるカレンダー（つないでいるときだけ）
    private(set) var calendars: [CalendarChoice] = []
    private(set) var preferences: CalendarPreferences
    /// iPhone の「新規イベントのデフォルトカレンダー」
    private(set) var systemDefaultCalendarID: String?

    @ObservationIgnored private let eventStore: EKEventStore
    @ObservationIgnored private let switchable: SwitchableEventRepository
    @ObservationIgnored private let localEvents: FileEventRepository?
    @ObservationIgnored private let metadata: EventMetadataRepository
    @ObservationIgnored private let preferencesFile: JSONFile<CalendarPreferences>
    @ObservationIgnored private var eventKit: EventKitEventRepository?
    @ObservationIgnored private let onChange: @MainActor ([CalendarChoice], String?) -> Void

    /// localEvents が nil のとき（DEBUG の見本の予定で動かしているとき）は、つながない。
    /// 開発用・見本の予定を Apple カレンダーへ書き込まないため（Q34）
    init(eventStore: EKEventStore,
         switchable: SwitchableEventRepository,
         localEvents: FileEventRepository?,
         metadata: EventMetadataRepository,
         preferencesFile: JSONFile<CalendarPreferences> = JSONFile(url: JSONFile<CalendarPreferences>.appSupportURL(named: "calendar-preferences.json"), empty: CalendarPreferences()),
         onChange: @escaping @MainActor (_ writableCalendars: [CalendarChoice], _ defaultCalendarID: String?) -> Void) {
        self.eventStore = eventStore
        self.switchable = switchable
        self.localEvents = localEvents
        self.metadata = metadata
        self.preferencesFile = preferencesFile
        self.onChange = onChange
        preferences = preferencesFile.load()
        state = Self.state(for: EKEventStore.authorizationStatus(for: .event))
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

    // MARK: - 内部

    /// 保存先を、Apple カレンダーとつなぐ前から TimyCue の中にあった予定と Apple カレンダーの両方にする。
    /// TimyCue の中の予定は Apple カレンダーへ移さない・複製しない（Q34）
    private func useEventKit() {
        guard let localEvents else { return }
        let repository = EventKitEventRepository(store: eventStore, metadata: metadata,
                                                 preferences: { [weak self] in self?.preferences ?? CalendarPreferences() })
        eventKit = repository
        calendars = repository.calendars()
        systemDefaultCalendarID = repository.systemDefaultCalendarID
        switchable.use(CombinedEventRepository(primary: repository, local: localEvents))
        notify()
    }

    private func savePreferences() {
        try? preferencesFile.save(preferences)
    }

    private func notify() {
        onChange(writableCalendars, defaultSaveCalendarID)
    }
}
