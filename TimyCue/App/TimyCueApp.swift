import SwiftUI

@main
struct TimyCueApp: App {
    /// 今は見本の予定を入れたメモリ上の保存先。Apple カレンダー（EventKit）版は第4段階で差し替える
    @State private var editorStore: ScheduleEditorStore = {
        let samples = SampleEvents.make()
        return ScheduleEditorStore(
            repository: InMemoryEventRepository(events: samples.events),
            metadataRepository: InMemoryEventMetadataRepository(metadata: samples.metadata)
        )
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(editorStore)
        }
    }
}
