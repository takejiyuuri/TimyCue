import EventKit
import Observation
import SwiftUI

/// Apple カレンダーとつなぐ状態（仕様 §68・§79・§80・Q31〜Q36）。
/// 許可は初回に全部求めず、TimyCue で初めてカレンダー連携が必要になったときに求める（Q31）。
/// つないだあとの状態の確認・変更は 設定 ＞ カレンダー連携 で行う。
/// 許可しなくても、TimyCue で作った予定は端末の中に保存して使える（§80）。
/// Apple カレンダー連携（全体）は TimyCue の設定で ON/OFF できる（spec §89.6。S6）。連携しているのは、連携 ON でフルアクセスがあるときだけ。
/// OFF にしても iPhone の許可や iCloud の設定は変えず、Apple 側の予定も消さない。iPhone の許可がなくても OFF にできる（2026-10-19 決定 2）。
/// 起動のときに設定のファイルを開けない（再起動の直後でまだロックを解除していないときなど）あいだは、連携の ON/OFF を確かめられない状態とし、
/// Apple カレンダーを読み書きせず、設定のファイルにも書かない。読めるようになったら読み直して、その設定に従う（2026-10-19 決定 3）
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

    /// iOS のカレンダーの許可から見た状態（連携の ON/OFF は含まない。連携しているかは isLinked）
    private(set) var state: State
    /// iOS のカレンダーの許可の状態そのもの（設定トップに「接続済み」「一部許可」などと出すため）
    private(set) var authorization: EKAuthorizationStatus
    /// 見えるカレンダー（連携しているときだけ）
    private(set) var calendars: [CalendarChoice] = []
    private(set) var preferences: CalendarPreferences
    /// iPhone の「新規イベントのデフォルトカレンダー」（連携しているときだけ）
    private(set) var systemDefaultCalendarID: String?
    /// TimyCue のローカル予定と Apple カレンダーの予定の重複候補（Q42-8・Q50）。同期のたびに見直す。連携 OFF のあいだは空（Q102・Q104）
    private(set) var duplicateCandidates: [DuplicateCandidate] = []
    /// 設定を保存できなかったときの知らせ（変更は元に戻してある。spec §89.9）。失敗のたびに別の値にする
    private(set) var settingsFailure: SettingsFailure?
    /// 設定を保存できなかった回数。スイッチや選択の行を描き直して、戻した値を見せるのに使う
    private(set) var settingsRevision = 0
    /// 前回、予定の保存の途中でアプリが終わっていて、確かめてもらうことがあるときの知らせ（spec §89.9）
    private(set) var recoveryNotice: String?
    /// 設定のファイルがあるのに開けなかった（一時的）ので、連携の ON/OFF を確かめられない（spec §89.6・2026-10-19 決定 3）。
    /// このあいだは Apple カレンダーを読み書きせず（保存先を作らない・カレンダーも予定も読まない）、設定のファイルにも書かず、
    /// 保存先の移行もしない。読み直して読めたら false にして、その設定に従う
    private(set) var isLinkSettingUnconfirmed = false
    /// 設定 ＞ カレンダー連携 の「もう一度読み込む」を押しても、まだ読み込めなかった（画面に出す）
    private(set) var preferencesStillUnreadable = false
    /// 「Appleカレンダー連携」を ON にしたときに始めた、iPhone のカレンダーの許可を求める処理（テストで終わりを待つため）
    @ObservationIgnored private(set) var permissionRequest: Task<Void, Never>?

    @ObservationIgnored private let eventStore: EKEventStore
    @ObservationIgnored private let switchable: SwitchableEventRepository
    @ObservationIgnored private let localEvents: FileEventRepository?
    @ObservationIgnored private let metadata: EventMetadataRepository
    @ObservationIgnored private let preferencesFile: JSONFile<CalendarPreferences>
    /// 保存の途中の記録（作成画面と同じもの。spec §89.9）
    @ObservationIgnored private let journal: SaveJournal
    /// Apple カレンダーの保存先。連携を OFF にしても捨てずに止めておき、ON に戻したら使い直す（メモリの上の結び付けを失わない）
    @ObservationIgnored private var eventKit: AppleCalendarRepository?
    /// Apple カレンダーの保存先を使っている（止めていない）
    @ObservationIgnored private var usesEventKit = false
    /// カレンダーの一覧（書き込めないものも含む。表示のみは手で直した分を当てたもの）と、保存先の決まりと、連携の状態を知らせる。
    /// 決まりが nil なら連携していない（作成画面は、新しい予定をこの iPhone の中へ保存する）。連携の状態は、連携していない理由を
    /// 作成画面に出すため（2026-10-19 ユーザー指示 3）
    @ObservationIgnored private let onChange: @MainActor ([CalendarChoice], SaveTargetRules?, AppleLinkStatus) -> Void
    /// 保存先の移行の済んだ記録（UserDefaults。spec §89.8）。本物の保存先で動くときだけ渡す（見本の予定・今のテストは移行しない）
    @ObservationIgnored private let saveTargetRecords: SaveTargetRecordStore?
    /// 起動の時点で設定のファイルがあったか（移行の材料。使った跡）
    @ObservationIgnored private var preferencesFileExistedAtLaunch = false
    /// 材料のファイルを開けなかったので、移行を先送りしている（メモリの中だけ「保存の前に確かめる」。ファイルには仮の種類を書かない）
    @ObservationIgnored private var migrationDeferred = false
    /// iOS のカレンダーの許可の状態を読む（テストでは決めた値にする）
    @ObservationIgnored private let authorizationStatus: () -> EKAuthorizationStatus
    /// Apple カレンダーの保存先を作る（テストでは EventKit の代わりの保存先にする。nil なら EventKit）
    @ObservationIgnored private let makeAppleRepository: ((@escaping () -> CalendarPreferences, SaveJournal) -> AppleCalendarRepository)?
    /// iPhone のカレンダーのフルアクセスを求める（テストでは差し替える。nil なら EventKit に求める）
    @ObservationIgnored private let requestAccess: (@MainActor () async -> Void)?

    /// localEvents が nil のとき（DEBUG の見本の予定で動かしているとき）は、つながない。
    /// 開発用・見本の予定を Apple カレンダーへ書き込まないため（Q34）。
    /// saveTargetRecords を渡したとき（アプリの本物の保存先）は、読み込みの直後に保存先の移行を一度だけ行う（spec §89.8）。
    /// 連携を OFF にして起動したときは、Apple カレンダーの保存先を作らず、カレンダーも予定も読まない（spec §89.6）。
    /// 設定のファイルを開けないときも同じく Apple カレンダーに触れず、連携の ON/OFF を確かめられないことを画面へ知らせる（2026-10-19 決定 3）
    init(eventStore: EKEventStore,
         switchable: SwitchableEventRepository,
         localEvents: FileEventRepository?,
         metadata: EventMetadataRepository,
         preferencesFile: JSONFile<CalendarPreferences> = JSONFile(url: JSONFile<CalendarPreferences>.appSupportURL(named: "calendar-preferences.json"),
                                                                   empty: CalendarPreferences(), faultPoint: .settingsWrite),
         journal: SaveJournal = .inMemory(),
         saveTargetRecords: SaveTargetRecordStore? = nil,
         authorizationStatus: @escaping () -> EKAuthorizationStatus = { EKEventStore.authorizationStatus(for: .event) },
         makeAppleRepository: ((@escaping () -> CalendarPreferences, SaveJournal) -> AppleCalendarRepository)? = nil,
         requestAccess: (@MainActor () async -> Void)? = nil,
         onChange: @escaping @MainActor (_ calendars: [CalendarChoice], _ saveTargets: SaveTargetRules?,
                                         _ linkStatus: AppleLinkStatus) -> Void) {
        self.eventStore = eventStore
        self.switchable = switchable
        self.localEvents = localEvents
        self.metadata = metadata
        self.preferencesFile = preferencesFile
        self.journal = journal
        self.saveTargetRecords = saveTargetRecords
        self.authorizationStatus = authorizationStatus
        self.makeAppleRepository = makeAppleRepository
        self.requestAccess = requestAccess
        self.onChange = onChange
        let existed = FileManager.default.fileExists(atPath: preferencesFile.url.path)
        preferences = preferencesFile.load()
        // 初期化が済むまでは self のプロパティを読めないので、いったん手元に置く
        let status = authorizationStatus()
        authorization = status
        state = Self.state(for: status)
        preferencesFileExistedAtLaunch = existed
        // 設定のファイルがあるのに開けない：読めた設定がないので、連携の ON/OFF を確かめられない。ON とはみなさず、Apple カレンダーを
        // 読み書きしない（spec §89.6・2026-10-19 決定 3）。空の設定はメモリの中だけで、ファイルには書かない（JSONFile も上書きを止める）
        isLinkSettingUnconfirmed = preferencesFile.couldNotOpen
        // 保存先の移行は、保存の途中の記録の復旧と Apple カレンダーの読み込みより前に行う（確かめられないあいだは今までどおり先送り）
        migrateSaveTargetIfNeeded()
        // この iPhone の中への保存の途中の記録の片付けも、設定を確かめられないあいだはしない（記録を消さない・やり直さない。
        // 次に確かめられた起動で行う）
        if !isLinkSettingUnconfirmed { recoverLocalSaves() }
        if isLinked {
            useEventKit()
        } else if isLinkSettingUnconfirmed {
            // 作成画面へ、確かめられないことを知らせる（新しい予定を、黙って TimyCue のみにしない）
            notify()
        }
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

    // MARK: - 連携の状態（spec §89.6・Q101・Q102・Q115）

    /// Apple カレンダー連携（全体）が ON か（TimyCue の設定。初めは ON）
    var isLinkEnabled: Bool { preferences.isAppleLinkEnabled }

    /// カレンダーのフルアクセスがある
    var hasFullAccess: Bool { state == .connected }

    /// 連携している（連携 ON で、フルアクセスがある）。連携していないあいだは、Apple カレンダーを読まず、書かない。
    /// 連携の設定を確かめられないあいだも、連携していないとして扱う（2026-10-19 決定 3）
    var isLinked: Bool { hasFullAccess && isLinkEnabled && !isLinkSettingUnconfirmed }

    /// 連携の状態（わざと OFF にした・まだ連携していない・許可がない・設定を確かめられない、を分ける）
    var linkStatus: AppleLinkStatus {
        if isLinkSettingUnconfirmed { return .unconfirmed }
        return AppleLinkStatus.resolve(authorization: authorization, linkEnabled: isLinkEnabled)
    }

    /// 設定トップの「カレンダー連携」の右に出す今の状態（v1.2「設定画面」。連携 OFF は「OFF」）
    var statusLabel: String { linkStatus.statusLabel(authorization: authorization) }

    /// iPhone の許可の状態の言い方
    static func statusLabel(for status: EKAuthorizationStatus) -> String {
        AppleLinkStatus.permissionLabel(for: status)
    }

    /// 設定 ＞ カレンダー連携 の「iPhone のカレンダーの許可」（許可あり・許可が必要・未確認・利用できません）。
    /// TimyCue の連携の ON/OFF とは別に出す（2026-10-19 ユーザー指示 4）
    var permissionStateLabel: String {
        AppleLinkStatus.permissionStateLabel(for: authorization)
    }

    /// 連携が ON なのにフルアクセスがないときの説明（Apple を読み書きしていないこと・許可のしかた）。端末の制限は ON/OFF によらず。
    /// 連携の設定を確かめられないあいだは、ON とは言えないので出さない（代わりに確かめられないことの説明を出す。2026-10-19 決定 3）
    var permissionNote: String? {
        guard !isLinkSettingUnconfirmed else { return nil }
        return AppleLinkStatus.permissionNote(authorization: authorization, linkEnabled: isLinkEnabled)
    }

    /// Home に連携のカードを出すか。まだ連携していない・許可がないときだけ（Q42-8・Q115）。わざと OFF にしたときは出さない（Q102）
    var showsSetupCard: Bool { linkStatus.showsSetupCard }

    // MARK: - 案内（Q38）

    /// 本物の保存先で動いているか。DEBUG の見本の予定ではつながず、案内も出さない
    var isLive: Bool { localEvents != nil }

    /// 初回の案内（「カレンダーを連携すると、予定から出発時刻を計算できます」と「カレンダーを連携」）を出すか。
    /// まだ許可を求めておらず（連携 OFF のときは出さない）、案内を一度も「あとで」にしていないとき（Q38）
    var showsFirstGuidance: Bool {
        isLive && linkStatus == .notLinked && (preferences.guidanceDismissCount ?? 0) == 0
    }

    // 初回の案内を「あとで」にしたあと、新しい予定を保存するときにもう一度案内する決まり（Q38）は、2026-10-18 の Q105 でやめた
    // （正常に保存できる状態で、保存のたびに許可の案内を繰り返さない。設定 ＞ カレンダー連携 からはいつでもつなげる）

    /// 案内を「あとで」にする
    /// 保存できなくても知らせない（戻すだけ。次にまた案内が出る。予定の保存の途中で、設定の失敗を混ぜて見せない）
    func dismissGuidance() {
        updatePreferences(reportsFailure: false) { $0.guidanceDismissCount = ($0.guidanceDismissCount ?? 0) + 1 }
    }

    /// 「カレンダーを連携」を押したとき。ここで初めて iOS の許可のダイアログを出す（Q38）。
    /// 自分から何度も出そうとはしない。一度拒否されたら iPhone の設定から許可してもらう
    func connect() async {
        guard localEvents != nil else { return }
        // 返事ではなく、求めたあとの iPhone の許可の状態で決める（フルアクセスがあるときだけ Apple を読み書きする。2026-10-19 ユーザー指示 4）
        if let requestAccess {
            await requestAccess()
        } else {
            _ = try? await eventStore.requestFullAccessToEvents()
        }
        authorization = authorizationStatus()
        state = Self.state(for: authorization)
        // 連携した直後は、前に付けた「見つからない」の記録をやり直す
        if isLinked { useEventKit(resettingMissing: true) }
    }

    /// アプリが前面に戻ったとき（RootTabView）。保存先の移行を先送りしていたら、やり直す（spec §89.8）。
    /// iPhone の許可が変わっていたら、Apple カレンダーを使い始める・止める（spec §89.6）。
    /// 連携の設定を確かめられないあいだは、設定のファイルの読み直しだけを試す（読めたら、その中で移行・使い始めまで行う。2026-10-19 決定 3）
    func handleBecameActive() {
        guard isLive else { return }
        if isLinkSettingUnconfirmed {
            reloadPreferences()
            return
        }
        var changed = retryDeferredMigration()
        let status = authorizationStatus()
        if status != authorization {
            authorization = status
            state = Self.state(for: status)
            changed = true
        }
        if isLinked && !usesEventKit {
            useEventKit(resettingMissing: true)
        } else if !isLinked && usesEventKit {
            stopUsingEventKit()
        } else if changed {
            notify()
        }
    }

    /// Apple カレンダー側が変わったとき（§68）。読み直す。連携していないあいだは Apple カレンダーに触れない
    func calendarDidChange() {
        guard isLinked, usesEventKit, let eventKit else { return }
        calendars = eventKit.calendars()
        systemDefaultCalendarID = eventKit.systemDefaultCalendarID
        eventKit.reloadCache()
        notify()
    }

    // MARK: - 設定 ＞ カレンダー連携

    /// Apple カレンダー連携（全体）を ON/OFF する（spec §89.6・Q101）。OFF にするたびの確認は出さない。
    /// OFF：先に、要るものをすべてファイルに残す（書けていない結び付け → OFF の設定）。どれかを書けなければ OFF にせず、ON のまま戻して
    /// 理由を知らせ、false を返す（アプリが終わっても、ON に戻したときに到着目標などを結び付け直せるように。2026-10-19 ユーザー指示）。
    /// 書けたら Apple カレンダーの保存先を止め、TimyCue のみの予定だけを見せる。Apple 側の予定・結び付け（終了未設定の印・
    /// 繰り返しの共通設定の id・「見つからない」の記録を含む）・TimyCue の設定・保存先の設定・表示の設定は消さない。
    /// ON：許可を読み直し、フルアクセスがあるときだけ最新を取り直す（許可がなければ Apple を読み書きしない。OFF の前の
    /// 「見つからない」の記録はやり直す。表示の設定は勝手に ON にしない。Q103）。保存できなければ戻して知らせ、false を返す。
    /// 連携の設定を確かめられないあいだは変えない（読めない設定のファイルを上書きしない。2026-10-19 決定 3）
    @discardableResult
    func setAppleLinkEnabled(_ enabled: Bool) -> Bool {
        guard !isLinkSettingUnconfirmed else {
            reportSettingsFailure(Self.unconfirmedSettingsFailureMessage)
            return false
        }
        guard enabled != isLinkEnabled else { return true }
        guard enabled else { return turnLinkOff() }
        guard updatePreferences({ $0.appleLinkEnabled = true }) else { return false }
        refreshAuthorization()
        if isLinked {
            useEventKit(resettingMissing: true)
        } else {
            notify()
        }
        return true
    }

    /// 連携を OFF にする（setAppleLinkEnabled から）。書けていない結び付けを書いてから、OFF の設定を書く。
    /// 止めてある保存先（許可が外れたときなど）にも書けていない結び付けがあれば、先に書く
    private func turnLinkOff() -> Bool {
        if let eventKit, !eventKit.saveUnsavedLinks() {
            reportSettingsFailure(Self.linkOffLinksFailureMessage)
            return false
        }
        guard updatePreferences(failureMessage: Self.linkOffSettingsFailureMessage, { $0.appleLinkEnabled = false }) else {
            return false
        }
        stopUsingEventKit()
        return true
    }

    /// 連携を OFF にできなかったときの知らせ（文言は仮）
    static let linkOffLinksFailureMessage = "Apple カレンダー連携を OFF にできませんでした。予定と到着目標などの結び付けを保存できませんでした。もう一度お試しください。"
    static let linkOffSettingsFailureMessage = "Apple カレンダー連携を OFF にできませんでした。設定を保存できませんでした。もう一度お試しください。"
    /// 連携の設定を確かめられないあいだに、連携を変えようとしたときの知らせ（文言は仮）
    static let unconfirmedSettingsFailureMessage = "設定を読み込めないため、Apple カレンダー連携を変えられませんでした。iPhone のロックを解除してから、もう一度お試しください。"

    /// 設定 ＞ カレンダー連携 の「Appleカレンダー連携」のスイッチ（iPhone の許可の状態によらず出す）と「Appleカレンダーを連携する」
    /// （spec §89.6・2026-10-19 決定 2）。OFF：setAppleLinkEnabled と同じ（OFF の前に要るものを残し、残せなければ OFF にせず理由を出す。
    /// 許可がなく Apple カレンダーの保存先を使っていなければ、結び付けのファイルには触れない）。
    /// ON：ON を保存し、まだ許可を求めていなければ、続けて許可を求める（拒否・追加のみ・制限なら、画面は Apple を読み書きしていないことと
    /// 許可のしかたを出す。フルアクセスがないあいだは Apple を読み書きしない）。保存できなければ false（スイッチは戻す）
    @discardableResult
    func switchAppleLink(_ enabled: Bool) -> Bool {
        guard setAppleLinkEnabled(enabled) else { return false }
        if enabled, isLive, authorization == .notDetermined {
            permissionRequest = Task { await connect() }
        }
        return true
    }

    /// 新しい予定の既定の保存先を変える（spec §89.2・§89.4。設定画面での変更と、初めて保存する前の確かめではっきり選んだとき）。
    /// 「TimyCue のみ」にしても、前に選んでいた Apple カレンダー（defaultCalendarID）は消さずに覚えておく。
    /// 保存できなければ値を戻して知らせ、false を返す
    @discardableResult
    func setDefaultSaveTarget(_ target: DefaultSaveTarget) -> Bool {
        let saved = updatePreferences(choosesSaveTarget: true) { preferences in
            switch target {
            case .timyCueOnly:
                preferences.saveTargetKind = .timyCueOnly
            case .systemDefault:
                preferences.saveTargetKind = .appleCalendar
                preferences.defaultCalendarID = nil
            case .calendar(let id):
                preferences.saveTargetKind = .appleCalendar
                preferences.defaultCalendarID = id
            }
        }
        if saved { notify() }
        return saved
    }

    /// 新しい予定の既定の保存先を Apple カレンダーにする（Q32）。nil で iPhone の既定
    func setDefaultCalendar(_ calendarID: String?) {
        setDefaultSaveTarget(calendarID.map(DefaultSaveTarget.calendar) ?? .systemDefault)
    }

    /// そのカレンダーを読み込むかどうか（Q33）。保存できなければ値を戻して知らせ、false を返す
    /// （作成画面の「表示をONにして保存」は、保存できたときだけ予定を保存する。spec §89.4）
    @discardableResult
    func setShown(_ shown: Bool, calendarID: String) -> Bool {
        let saved = updatePreferences { preferences in
            if shown {
                preferences.hiddenCalendarIDs.remove(calendarID)
            } else {
                preferences.hiddenCalendarIDs.insert(calendarID)
            }
        }
        guard saved else { return false }
        if usesEventKit { eventKit?.reloadCache() }
        notify()
        return true
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
    /// 成功でも失敗でも、最後に重複候補を作り直す（spec §89.9・2026-10-18 S1b）。連携を OFF にしているあいだと、
    /// 連携の設定を確かめられないあいだは何もしない（spec §89.6）
    func useApple(_ candidate: DuplicateCandidate, preferLocalSettings: Bool? = nil) throws {
        guard let localEvents, isLinkEnabled, !isLinkSettingUnconfirmed else { return }
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

    /// 同期のたびに重複候補を見直す（見つけるのは Apple カレンダーとの同期のとき。Q50）。
    /// 連携中に「TimyCue のみ」で保存した予定は外す。「Apple Calendarに保存」が途中で止まった元の予定は候補にする（Q104）。
    /// 連携 OFF のあいだは Apple カレンダーに触れず、候補は空（spec §89.6・§89.7）
    private func refreshDuplicates() {
        guard isLinked, usesEventKit, let eventKit, let localEvents else {
            duplicateCandidates = []
            return
        }
        let moving = Set(journal.entries.compactMap(\.movedFromLocalID))
        duplicateCandidates = DuplicateCandidates.find(local: localEvents.allEvents(),
                                                       apple: eventKit.allEvents(),
                                                       keptBoth: preferences.keptBothDuplicates ?? [],
                                                       pendingMoveLocalIDs: moving)
    }

    // MARK: - 内部

    /// 保存先を、Apple カレンダーとつなぐ前から TimyCue の中にあった予定と Apple カレンダーの両方にする。
    /// TimyCue の中の予定は Apple カレンダーへ移さない・複製しない（Q34）。
    /// 止めてあった Apple カレンダーの保存先があれば使い直す（ON に戻したとき）。resettingMissing なら「見つからない」の記録をやり直す
    /// （使っている途中で使い始めたとき：OFF→ON・連携した直後・許可が戻ったとき。起動のときはやり直さない）
    private func useEventKit(resettingMissing: Bool = false) {
        guard let localEvents else { return }
        if usesEventKit {
            notify()
            return
        }
        let repository: AppleCalendarRepository
        if let paused = eventKit {
            paused.resume()
            repository = paused
        } else {
            repository = makeRepository()
            eventKit = repository
        }
        if resettingMissing { repository.resetMissingRecords() }
        // 前回の保存の途中で終わっていたら、読み込みを始める前に結び付け直す（spec §89.9）。
        // 連携 OFF のあいだ残しておいた Apple の記録も、ここで片付け、確かめてもらうことを知らせる
        noteRecovery(askUser: repository.recover(now: Date()), localEvents: localEvents, linksSaved: !repository.hasUnsavedLinks)
        // 予定は裏で読むので、読み終わったら画面を描き直す
        repository.onLoaded = { [weak self] in self?.notify() }
        calendars = repository.calendars()
        systemDefaultCalendarID = repository.systemDefaultCalendarID
        switchable.use(CombinedEventRepository(primary: repository, local: localEvents))
        usesEventKit = true
        notify()
    }

    /// Apple カレンダーの保存先を止める（連携 OFF・許可が外れた）。止めた保存先は捨てない。
    /// 予定の保存先はこの iPhone の中だけにし、カレンダー・重複候補を空にする（設定の値は消さない）
    private func stopUsingEventKit() {
        if let eventKit {
            eventKit.pause()
            eventKit.onLoaded = nil
        }
        if let localEvents { switchable.use(localEvents) }
        calendars = []
        systemDefaultCalendarID = nil
        duplicateCandidates = []
        usesEventKit = false
        notify()
    }

    private func makeRepository() -> AppleCalendarRepository {
        if let makeAppleRepository {
            return makeAppleRepository({ [weak self] in self?.preferences ?? CalendarPreferences() }, journal)
        }
        return EventKitEventRepository(store: eventStore, metadata: metadata,
                                       preferences: { [weak self] in self?.preferences ?? CalendarPreferences() },
                                       journal: journal)
    }

    /// iOS のカレンダーの許可を読み直す（本物の保存先のときだけ）
    private func refreshAuthorization() {
        guard isLive else { return }
        let status = authorizationStatus()
        authorization = status
        state = Self.state(for: status)
    }

    /// 設定を変えて保存する。保存できなければ変更前の値のままにし、知らせる（変更済みと誤って見せない。読み直しより前に戻す。spec §89.9）。
    /// 案内を閉じた印のような、ユーザーが設定として変えたのではないものは `reportsFailure: false`（戻すだけ）。
    /// 新しい版の印（formatVersion）を書き、保存できたら移行の済んだ記録にも写す（spec §89.8）。
    /// 移行を先送りしているあいだは、仮の保存先の種類と印を書かない。利用者が保存先をはっきり選んだとき（choosesSaveTarget）だけ書いて、先送りを解く。
    /// failureMessage：保存できなかったときの知らせの文（nil ならふつうの文）
    @discardableResult
    private func updatePreferences(reportsFailure: Bool = true, choosesSaveTarget: Bool = false, failureMessage: String? = nil,
                                   _ change: (inout CalendarPreferences) -> Void) -> Bool {
        var next = preferences
        change(&next)
        var written = next
        if migrationDeferred && !choosesSaveTarget {
            written.saveTargetKind = nil
            written.formatVersion = nil
        } else {
            next.formatVersion = CalendarPreferences.currentFormatVersion
            written = next
        }
        do {
            try preferencesFile.save(written)
            preferences = next
            if choosesSaveTarget { migrationDeferred = false }
            syncSaveTargetRecord()
            return true
        } catch {
            if reportsFailure {
                reportSettingsFailure(failureMessage ?? "変更は反映していません。もう一度お試しください。")
            } else {
                settingsRevision += 1
            }
            return false
        }
    }

    /// 設定を変えられなかったことを知らせる。スイッチや選択の行を描き直して、元の値を見せる（spec §89.9）
    private func reportSettingsFailure(_ message: String) {
        settingsRevision += 1
        settingsFailure = SettingsFailure(message: message)
    }

    // MARK: - 保存先の移行（spec §89.8・Q98・Q111。S2）

    /// 新しい版を初めて開いたときに一度だけ、新しい予定の既定の保存先の種類を決める。済んだ記録は UserDefaults に置き、
    /// 設定のファイルにも種類と版の印を書く。2 回目からは決め直さない（古い版がファイルを書き直したときは、記録から戻す）。
    /// 予定・TimyCue の設定・結び付け・保存の途中の記録・古い切り替えの印には何も書かない。予定の複製・移動・削除もしない
    private func migrateSaveTargetIfNeeded() {
        guard let records = saveTargetRecords, isLive else { return }
        // 設定のファイルがあるのに開けない（端末のロック中など）：この起動では決めず、メモリの中だけ「保存の前に確かめる」
        if preferencesFile.couldNotOpen {
            preferences.saveTargetKind = .askBeforeSaving
            migrationDeferred = true
            return
        }
        // 新しい版が書いたファイル：そのまま使う（記録の写しが違えば直す）
        if preferences.formatVersion != nil, preferences.saveTargetKind != nil {
            migrationDeferred = false
            syncSaveTargetRecord()
            return
        }
        // 記録があるのに、ファイルに新しい項目がない（古い版が書き直した・前回の保存に失敗した）：記録から戻す
        if let record = records.load() {
            var next = preferences
            next.saveTargetKind = SaveTargetMigration.restoredKind(record: record, file: preferences)
            // 連携の OFF も戻す（OFF を黙って ON にしない）
            next.appleLinkEnabled = record.linkEnabled
            persistMigrated(next)
            return
        }
        // 初めて：材料を集めて一度だけ決める
        let evidence = SaveTargetMigration.collect(folder: preferencesFile.url.deletingLastPathComponent(),
                                                   preferences: preferences,
                                                   preferencesFileExisted: preferencesFileExistedAtLaunch)
        switch SaveTargetMigration.decide(evidence) {
        case .decided(let kind, _):
            var next = preferences
            next.saveTargetKind = kind
            persistMigrated(next)
        case .deferred:
            preferences.saveTargetKind = .askBeforeSaving
            migrationDeferred = true
        }
    }

    /// 移行で決めた値を残す：記録を先に書き、設定のファイルへも書く。利用者の操作ではないので、書けなくても知らせない
    /// （決めた値はメモリで使い、次に開いたときに記録から書き直す）。開発用の失敗の再現も使わない
    private func persistMigrated(_ value: CalendarPreferences) {
        var next = value
        next.formatVersion = CalendarPreferences.currentFormatVersion
        if let kind = next.saveTargetKind {
            saveTargetRecords?.save(SaveTargetRecord(kind: kind, calendarID: next.defaultCalendarID, linkEnabled: next.appleLinkEnabled))
        }
        try? preferencesFile.save(next, allowsFault: false)
        preferences = next
        migrationDeferred = false
    }

    /// 移行の済んだ記録に、今の保存先の種類・保存先のカレンダー・連携の ON/OFF を写す（変わったときだけ）
    private func syncSaveTargetRecord() {
        guard let records = saveTargetRecords, !migrationDeferred, let kind = preferences.saveTargetKind else { return }
        let record = SaveTargetRecord(kind: kind, calendarID: preferences.defaultCalendarID, linkEnabled: preferences.appleLinkEnabled)
        if records.load() != record { records.save(record) }
    }

    /// 移行を先送りしていたら、もう一度やり直す（設定のファイルを開けなかったなら読み直す。設定のファイルを開けない起動は、
    /// 連携の設定を確かめられない状態として reloadPreferences で読み直すので、ここへ来るのは、ほかの材料を開けなかったとき）。決まったら true
    private func retryDeferredMigration() -> Bool {
        guard migrationDeferred else { return false }
        if preferencesFile.couldNotOpen {
            let reloaded = preferencesFile.load()
            guard !preferencesFile.couldNotOpen else { return false }
            preferences = reloaded
        }
        migrationDeferred = false
        migrateSaveTargetIfNeeded()
        return !migrationDeferred
    }

    // MARK: - 連携の設定を確かめられないとき（spec §89.6・2026-10-19 決定 3）

    /// 連携の設定を確かめられないあいだに、設定のファイルを読み直す（アプリが前面に戻ったとき・ロックを解除して読めるようになったとき・
    /// 設定の「もう一度読み込む」）。読めたら、その設定を使い、先送りしていた保存先の移行を行い、連携 ON でフルアクセスがあれば
    /// Apple カレンダーを使い始めて知らせる（起動のときと同じく、「見つからない」の記録はやり直さない）。
    /// 読めないままなら、確かめられない状態のまま（Apple カレンダーにも設定のファイルにも触れない）。確かめられていれば true
    @discardableResult
    func reloadPreferences() -> Bool {
        guard isLinkSettingUnconfirmed else { return true }
        guard isLive else { return false }
        let reloaded = preferencesFile.load()
        guard !preferencesFile.couldNotOpen else {
            // iPhone の許可の行だけは読み直しておく（許可の状態は設定のファイルとは別）
            let status = authorizationStatus()
            if status != authorization {
                authorization = status
                state = Self.state(for: status)
                notify()
            }
            return false
        }
        preferences = reloaded
        isLinkSettingUnconfirmed = false
        preferencesStillUnreadable = false
        // 先送りしていた保存先の移行を、ここで行う（spec §89.8。ほかの材料を開けなければ、今までどおりまた先送り）
        migrationDeferred = false
        migrateSaveTargetIfNeeded()
        refreshAuthorization()
        if isLinked {
            useEventKit()
        } else {
            notify()
        }
        return true
    }

    /// 設定 ＞ カレンダー連携 の「もう一度読み込む」（文言は仮）。読めなければ、まだ読み込めないことを画面に出す
    func retryReadingPreferences() {
        preferencesStillUnreadable = !reloadPreferences()
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

    /// 画面へ知らせる。連携していないときは保存先の決まりを渡さない（作成画面は、新しい予定をこの iPhone の中へ保存する）。
    /// 連携の状態も渡す（作成画面が、開いているあいだの連携の変化と、連携していない理由を出すため）
    private func notify() {
        refreshDuplicates()
        // 祝日カレンダーは、手で直した分を当ててから渡す（Q55）
        let resolved = calendars.map { calendar in
            var copy = calendar
            copy.isHolidays = preferences.isHolidayCalendar(calendar)
            return copy
        }
        onChange(resolved, isLinked ? saveTargets : nil, linkStatus)
    }
}

#if DEBUG
/// Codemagic の画面写真用の見本の連携（DEBUG のときだけ。公開版の形と TestFlight の形には入らない）
extension CalendarConnection {
    /// 見本のカレンダー・iPhone の既定・設定・許可の状態
    struct SampleLink {
        var calendars: [CalendarChoice]
        var systemDefaultID: String?
        var preferences: CalendarPreferences
        var authorization: EKAuthorizationStatus
    }

    /// 見本の予定で動いているときだけ、見本の連携をメモリの中に入れて画面へ知らせる。
    /// 設定のファイルにも Apple カレンダーにも触れない。連携 OFF・許可なしの見本では、カレンダーを空にする
    func useSampleLink(_ link: SampleLink) {
        guard !isLive else { return }
        authorization = link.authorization
        state = Self.state(for: link.authorization)
        preferences = link.preferences
        calendars = isLinked ? link.calendars : []
        systemDefaultCalendarID = isLinked ? link.systemDefaultID : nil
        notify()
    }
}
#endif
