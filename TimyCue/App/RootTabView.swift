import SwiftUI

/// 下部タブ（仕様 §3）：ホーム｜カレンダー｜設定
enum RootTab: String, CaseIterable {
    case home
    case calendar
    case settings

    var title: String {
        switch self {
        case .home: "ホーム"
        case .calendar: "カレンダー"
        case .settings: "設定"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "clock"
        case .calendar: "calendar"
        case .settings: "gearshape"
        }
    }
}

struct RootTabView: View {
    @State private var selection: RootTab = RootTabView.initialTab
    @Environment(ScheduleEditorStore.self) private var editorStore
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(CalendarConnection.self) private var connection
    @State private var showsEditorForScreenshot = false

    var body: some View {
        TabView(selection: Binding(get: { selection }, set: { tab in
            // カレンダーのタブを押し直すと、iOS が画面をいちばん上（20 年前の週）までスクロールしてしまう。
            // 押し直しを見つけたら、そのスクロールのあとで今月へ戻す（2026-10-13 実機の不具合。戻す先は仮）
            if tab == selection, tab == .calendar {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    calendarStore.showCurrentMonth()
                }
            }
            selection = tab
        })) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                screen(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(Theme.Colors.accent)
        // 既定の保存先が使えなくなって iPhone の既定へ切り替えたことを、一度だけ知らせる（v1.2「Apple Calendar」）
        .alert("保存先のカレンダーを切り替えました",
               isPresented: Binding(get: { connection.showsSaveTargetNotice },
                                    set: { if !$0 { connection.dismissSaveTargetNotice() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connection.saveTargetNoticeMessage)
        }
        .onAppear { openEditorForScreenshot() }
        .fullScreenCover(isPresented: $showsEditorForScreenshot) {
            ScheduleEditorView(initialMonth: CalendarMonth(CalendarDay(Date())))
                .environment(editorStore)
                .environment(calendarStore)
                .environment(connection)
        }
    }

    /// Codemagic で 3 分割画面の画面写真を撮るとき、起動引数 `-TimyCueEditorDays "0,7,14"`（今日からの日数）で、
    /// その日を選んだ新規の 3 分割画面を開く（DEBUG のときだけ）
    private func openEditorForScreenshot() {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "TimyCueEditorDays"), !showsEditorForScreenshot else { return }
        let today = CalendarDay(Date())
        let days = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.map { today.adding(days: $0) }
        guard let first = days.first else { return }
        editorStore.startNew()
        days.forEach(editorStore.selectDay)
        editorStore.displayDay(first)
        editorStore.setStartMinute(14 * 60, on: first)
        editorStore.content.title = "見本の打合せ"
        showsEditorForScreenshot = true
        #endif
    }

    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        switch tab {
        case .calendar: CalendarTabView()
        case .settings: SettingsTabView()
        case .home: HomeView()
        }
    }

    /// Codemagic でシミュレータの画面写真を撮るとき、起動引数 `-TimyCueTab calendar` で最初のタブを選ぶ
    private static var initialTab: RootTab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "TimyCueTab"), let tab = RootTab(rawValue: raw) {
            return tab
        }
        #endif
        return .home
    }
}
