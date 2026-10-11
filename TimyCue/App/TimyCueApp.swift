import Combine
import EventKit
import SwiftUI

@main
struct TimyCueApp: App {
    @State private var editorStore: ScheduleEditorStore
    @State private var calendarStore: CalendarStore
    @State private var connection: CalendarConnection

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
        _connection = State(initialValue: CalendarConnection(
            eventStore: EKEventStore(),
            switchable: switchable,
            localEvents: localEvents,
            metadata: metadata,
            onChange: {
                calendar.reload()
                editor.refresh()
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
                // Apple カレンダー側で予定が変わったら読み直す（§68）
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                    connection.calendarDidChange()
                }
        }
    }
}
