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
        if Self.usesSampleData {
            let samples = SampleEvents.make()
            metadata = InMemoryEventMetadataRepository(metadata: samples.metadata)
            switchable = SwitchableEventRepository(InMemoryEventRepository(events: samples.events))
            localEvents = nil
        } else {
            let files = FileEventRepository()
            metadata = FileEventMetadataRepository()
            switchable = SwitchableEventRepository(files)
            localEvents = files
        }

        let editor = ScheduleEditorStore(repository: switchable, metadataRepository: metadata)
        let calendar = CalendarStore(repository: switchable, metadataRepository: metadata)
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
            onChange: { calendars, defaultCalendarID in
                calendar.setCalendars(calendars)
                calendar.reload()
                editor.refresh()
                editor.setCalendars(calendars, defaultCalendarID: defaultCalendarID)
            }))
    }

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
