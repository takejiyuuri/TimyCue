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
            if tab == selection, tab == .calendar { calendarTabTappedAgain() }
            selection = tab
        })) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                screen(for: tab)
                    // 画面の中の操作の文字（文字だけのボタン・戻る・ダイアログ）は少し濃いオレンジ。タブの選択はブランドのオレンジ（下の tint。2026-10-14 決定）
                    .tint(Theme.Colors.actionText)
                    .tabItem {
                        if tab == .calendar && showsTodayInTab {
                            Label("今日", systemImage: "calendar.badge.clock")
                        } else {
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                    }
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

    /// カレンダーを見ていて今日が画面の外にあるときは、下のカレンダーのタブが「今日」になる（2026-10-13 ユーザー。前の右上の「今日」の代わり）
    private var showsTodayInTab: Bool {
        selection == .calendar && !calendarStore.isTodayVisible
    }

    /// カレンダーのタブの押し直し：「今日」になっていれば今日へ移動して今日を選ぶ。今日が見えていれば、押した瞬間の位置にとどめる
    /// （CalendarStore.tabTappedAgain）。iOS はタブの押し直しで画面をいちばん上（20 年前）へ動かし始めるので、今日へ移動したときは、
    /// iOS の動きが遅れて始まったときのために、少しあとにもう一度だけ確かめる
    private func calendarTabTappedAgain() {
        guard let target = calendarStore.tabTappedAgain() else { return }
        Task { @MainActor in
            for delay in [100, 350] {
                try? await Task.sleep(for: .milliseconds(delay))
                if calendarStore.topWeekID != target { calendarStore.scroll(to: target) }
            }
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
        editorStore.startNew(on: first)
        days.dropFirst().forEach(editorStore.addDay)
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
