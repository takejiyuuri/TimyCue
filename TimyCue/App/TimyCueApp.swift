import SwiftUI

@main
struct TimyCueApp: App {
    @State private var editorStore: ScheduleEditorStore
    @State private var calendarStore: CalendarStore

    init() {
        // 今は見本の予定を入れたメモリ上の保存先。Apple カレンダー（EventKit）版は第4段階で差し替える。
        // 予定編集とカレンダーは同じ保存先を見る
        let samples = SampleEvents.make()
        let events = InMemoryEventRepository(events: samples.events)
        let metadata = InMemoryEventMetadataRepository(metadata: samples.metadata)
        _editorStore = State(initialValue: ScheduleEditorStore(repository: events, metadataRepository: metadata))
        _calendarStore = State(initialValue: CalendarStore(repository: events, metadataRepository: metadata))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(editorStore)
                .environment(calendarStore)
        }
    }
}
