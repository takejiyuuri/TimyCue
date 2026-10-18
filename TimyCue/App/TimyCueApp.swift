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
            let samples = SampleEvents.make()
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
        #if DEBUG
        if Self.usesSampleData, let rules = Self.sampleSaveTargets() { editor.setCalendars(rules) }
        #endif
        _editorStore = State(initialValue: editor)
        _calendarStore = State(initialValue: calendar)
        // 出発時刻の計算（第 5 段階）。見本の予定で動かすとき（画面写真・自動テスト）は、現在地も地図も使わない
        _departures = State(initialValue: DepartureStore(isEnabled: !Self.usesSampleData,
                                                         location: LocationProvider(isEnabled: !Self.usesSampleData)))
        _connection = State(initialValue: CalendarConnection(
            eventStore: EKEventStore(),
            switchable: switchable,
            localEvents: localEvents,
            metadata: metadata,
            preferencesFile: preferencesFile,
            journal: journal,
            saveTargetRecords: saveTargetRecords,
            onChange: { calendars, saveTargets in
                calendar.setCalendars(calendars)
                calendar.reload()
                editor.refresh()
                editor.setCalendars(saveTargets)
            }))
    }

    #if DEBUG
    /// Codemagic の画面写真用：起動引数 -TimyCueSampleCalendars で、見本のカレンダーを作成画面に渡す。
    /// Apple カレンダーにはつながず、何も書き込まない（見本の予定はメモリの中だけ）。
    /// hiddenDefault：iPhone の既定（Default）の表示を OFF／displayOnlyDefault：iPhone の既定を手で表示のみ
    private static func sampleSaveTargets() -> SaveTargetRules? {
        guard let kind = UserDefaults.standard.string(forKey: "TimyCueSampleCalendars") else { return nil }
        let calendars = [
            CalendarChoice(id: "sample-default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange),
            CalendarChoice(id: "sample-home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green),
            CalendarChoice(id: "sample-work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue),
            CalendarChoice(id: "sample-holidays", title: "日本の祝日", sourceTitle: "購読", isWritable: false, color: .lavender,
                           isHolidays: true),
        ]
        var preferences = CalendarPreferences()
        switch kind {
        case "hiddenDefault": preferences.hiddenCalendarIDs = ["sample-default"]
        case "displayOnlyDefault": preferences.setHoliday(true, calendarID: "sample-default")
        default: break
        }
        return SaveTargetRules(calendars: calendars, preferences: preferences, systemDefaultID: "sample-default")
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
