import SwiftUI

@main
struct TimyCueApp: App {
    /// 今は見本の予定を入れたメモリ上の保存先。Apple カレンダー（EventKit）版は後の段階で差し替える
    @State private var editorStore = ScheduleEditorStore(
        repository: InMemoryEventRepository(events: SampleEvents.make())
    )

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(editorStore)
        }
    }
}
