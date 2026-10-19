import Combine
import EventKit
import SwiftUI

@main
struct TimyCueApp: App {
    @State private var editorStore: ScheduleEditorStore
    @State private var calendarStore: CalendarStore
    @State private var connection: CalendarConnection
    @State private var departures: DepartureStore

    init() {
        // 予定編集とカレンダーは同じ保存先を見る。
        // ふだんは端末の中のファイルに保存し、Apple カレンダーとつないだら Apple カレンダーへ切り替える（仕様 §68・§80）。
        // DEBUG のビルド（Codemagic の画面写真・自動テスト）では見本の予定を使う。起動引数 -TimyCueRealData YES で本物の保存先
        let metadata: EventMetadataRepository
        let switchable: SwitchableEventRepository
        let localEvents: FileEventRepository?
        // 保存の途中の記録（spec §89.9）。見本の予定ではメモリの中だけ
        let journal: SaveJournal
        // カレンダー連携の設定と、保存先の移行の済んだ記録（spec §89.8）
        let preferencesFile: JSONFile<CalendarPreferences>
        let saveTargetRecords: SaveTargetRecordStore?
        if Self.usesSampleData {
            #if DEBUG
            var samples = SampleEvents.make()
            // Codemagic の画面写真用：起動引数 -TimyCueSampleAppleEvent YES で、書き込めない Apple カレンダー（見本の「チーム」）の
            // 見本の予定を足す（既存の予定の所属の画面写真。メモリの中だけ。Apple カレンダーにはつながない）
            if UserDefaults.standard.bool(forKey: "TimyCueSampleAppleEvent") {
                let event = CalendarEvent(day: CalendarDay(Date()), startMinute: 15 * 60, durationMinutes: 30, title: "チーム定例（見本）",
                                          source: .appleCalendar, calendarID: "sample-shared")
                var info = TimyCueEventMetadata()
                info.color = .mint
                samples.events.append(event)
                samples.metadata[event.id] = info
            }
            #else
            let samples = SampleEvents.make()
            #endif
            metadata = InMemoryEventMetadataRepository(metadata: samples.metadata)
            switchable = SwitchableEventRepository(InMemoryEventRepository(events: samples.events))
            localEvents = nil
            journal = .inMemory()
            // 見本の予定では、本物の設定のファイルを読まず書かない（使い捨ての一時ファイル）。移行もしない
            preferencesFile = JSONFile(url: FileManager.default.temporaryDirectory
                                           .appendingPathComponent("timycue-sample-preferences-\(UUID().uuidString).json"),
                                       empty: CalendarPreferences(), faultPoint: .settingsWrite)
            saveTargetRecords = nil
        } else {
            let files = FileEventRepository()
            metadata = FileEventMetadataRepository()
            switchable = SwitchableEventRepository(files)
            localEvents = files
            journal = .onDevice()
            preferencesFile = JSONFile(url: JSONFile<CalendarPreferences>.appSupportURL(named: "calendar-preferences.json"),
                                       empty: CalendarPreferences(), faultPoint: .settingsWrite)
            saveTargetRecords = SaveTargetRecordStore.live
        }

        #if TIMYCUE_SAVE_FAULTS
        SaveFaultView.armFromLaunchArguments()
        #endif
        let editor = ScheduleEditorStore(repository: switchable, metadataRepository: metadata, journal: journal)
        let calendar = CalendarStore(repository: switchable, metadataRepository: metadata)
        _editorStore = State(initialValue: editor)
        _calendarStore = State(initialValue: calendar)
        // 出発時刻の計算（第 5 段階）。見本の予定で動かすとき（画面写真・自動テスト）は、現在地も地図も使わない
        _departures = State(initialValue: DepartureStore(isEnabled: !Self.usesSampleData,
                                                         location: LocationProvider(isEnabled: !Self.usesSampleData)))
        // 連携しているときだけ、保存先の決まりを作成画面へ渡す（nil は連携していない。新しい予定はこの iPhone の中へ。spec §89.6）。
        // 連携の状態も渡す（作成画面を開いているあいだに連携が変わったら、画面に出していた保存先を保つ。2026-10-19 ユーザー指示 3。
        // 連携の設定を確かめられないときは、新しい予定を黙って TimyCue のみにせず確かめる。2026-10-19 決定 3）。
        // 連携したまま設定が変わって書く先が変わったら、作成画面が覚えて保存の前に確かめる（2026-10-19 決定 1）
        let connection = CalendarConnection(
            eventStore: EKEventStore(),
            switchable: switchable,
            localEvents: localEvents,
            metadata: metadata,
            preferencesFile: preferencesFile,
            journal: journal,
            saveTargetRecords: saveTargetRecords,
            onChange: { calendars, saveTargets, linkStatus in
                calendar.setCalendars(calendars)
                calendar.reload()
                editor.refresh()
                editor.receiveLink(saveTargets, status: linkStatus)
            })
        #if DEBUG
        if Self.usesSampleData, let link = Self.sampleLink() { connection.useSampleLink(link) }
        #endif
        _connection = State(initialValue: connection)
    }

    #if DEBUG
    /// Codemagic の画面写真用：起動引数 -TimyCueSampleCalendars と -TimyCueSampleLink で、見本のカレンダーと見本の連携を渡す。
    /// Apple カレンダーにはつながず、何も書き込まない（見本の予定・設定はメモリの中だけ）。
    /// -TimyCueSampleCalendars：hiddenDefault（iPhone の既定 Default の表示を OFF）／displayOnlyDefault（Default を手で表示のみ）／
    /// appleDefault（保存先は Apple の iPhone の既定）／timyCueOnlyDefault（保存先は TimyCue のみ）／askDefault（保存先がまだ決まっていない）／
    /// hiddenSettingsDefault・allHidden・allHiddenSettingsDefault・missingSettingsDefault・askHidden（2026-10-19 のクラッシュの再現。下の switch）。
    /// -TimyCueSampleLink：off（フルアクセスのまま連携 OFF）／offDenied（許可なしで連携 OFF）。どちらもなければ連携中
    private static func sampleLink() -> CalendarConnection.SampleLink? {
        let defaults = UserDefaults.standard
        let kind = defaults.string(forKey: "TimyCueSampleCalendars")
        let link = defaults.string(forKey: "TimyCueSampleLink")
        guard kind != nil || link != nil else { return nil }
        let calendars = [
            CalendarChoice(id: "sample-default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange),
            CalendarChoice(id: "sample-home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green),
            CalendarChoice(id: "sample-work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue),
            // 書き込めない共有のカレンダー（保存先の候補には出ない）
            CalendarChoice(id: "sample-shared", title: "チーム", sourceTitle: "Google", isWritable: false, color: .mint),
            CalendarChoice(id: "sample-holidays", title: "日本の祝日", sourceTitle: "購読", isWritable: false, color: .lavender,
                           isHolidays: true),
        ]
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = .appleCalendar
        switch kind ?? "" {
        case "hiddenDefault": preferences.hiddenCalendarIDs = ["sample-default"]
        case "displayOnlyDefault": preferences.setHoliday(true, calendarID: "sample-default")
        case "timyCueOnlyDefault": preferences.saveTargetKind = .timyCueOnly
        case "askDefault": preferences.saveTargetKind = .askBeforeSaving
        // 2026-10-19 TestFlight 1.0 (30) のクラッシュ（設定で Default の表示を OFF にして新しい予定を開くと落ちる）の再現と確かめ
        case "hiddenSettingsDefault":
            // 設定の既定の保存先に Default をはっきり選び、その表示を OFF
            preferences.defaultCalendarID = "sample-default"
            preferences.hiddenCalendarIDs = ["sample-default"]
        case "allHidden":
            // 書き込めるカレンダーを全部表示 OFF（使える Apple カレンダーが 0 件）
            preferences.hiddenCalendarIDs = ["sample-default", "sample-home", "sample-work"]
        case "allHiddenSettingsDefault":
            preferences.defaultCalendarID = "sample-default"
            preferences.hiddenCalendarIDs = ["sample-default", "sample-home", "sample-work"]
        case "missingSettingsDefault":
            // 設定の既定の保存先のカレンダーが見つからない
            preferences.defaultCalendarID = "sample-missing"
        case "askHidden":
            // 保存先がまだ決まっていない（未選択）で、Default の表示 OFF
            preferences.saveTargetKind = .askBeforeSaving
            preferences.hiddenCalendarIDs = ["sample-default"]
        default: break
        }
        var authorization = EKAuthorizationStatus.fullAccess
        switch link ?? "" {
        case "off":
            preferences.appleLinkEnabled = false
        case "offDenied":
            preferences.appleLinkEnabled = false
            authorization = .denied
        default:
            break
        }
        return CalendarConnection.SampleLink(calendars: calendars, systemDefaultID: "sample-default",
                                             preferences: preferences, authorization: authorization)
    }
    #endif

    private static var usesSampleData: Bool {
        #if DEBUG
        return !UserDefaults.standard.bool(forKey: "TimyCueRealData")
        #else
        return false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(editorStore)
                .environment(calendarStore)
                .environment(connection)
                .environment(departures)
                // Apple カレンダー側で予定が変わったら読み直す（§68）
                // この知らせは画面の処理とは別のところから届くことがあるので、画面の処理へ移してから受け取る
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: DispatchQueue.main)) { _ in
                    connection.calendarDidChange()
                }
        }
    }
}
