import Combine
import SwiftUI
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase
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
        // 設定（保存先・表示など）を保存できなかったら、変更は戻して知らせる（spec §89.9）
        .settingsFailureAlert()
        // 前回、予定の保存の途中でアプリが終わっていたら、確かめてもらうことを知らせる（spec §89.9）
        .alert("前回の保存を確かめてください",
               isPresented: Binding(get: { connection.recoveryNotice != nil }, set: { _ in })) {
            Button("OK", role: .cancel) { connection.dismissRecoveryNotice() }
        } message: {
            Text(connection.recoveryNotice ?? "")
        }
        .onAppear {
            // 起動のときに設定のファイルを開けなかったら（連携の ON/OFF を確かめられない）、最初の画面を出すときにも読み直す
            // （まだ読めなければ何も変えない。spec §89.6・2026-10-19 決定 3）
            _ = connection.reloadPreferences()
            openEditorForScreenshot()
            changeSampleSettingsForScreenshot()
            applyReproSettings()
            markReadyForScreenshot()
        }
        // カレンダーの「今日」（月カレンダーの今日の丸・［＋］の初めの日・1 日タイムラインの今日）を、アプリを前面に戻したときと、
        // 日付が変わったとき（夜 0 時をまたいだ・時刻やタイムゾーンを変えた）にも本当の今日へ直す。前は起動したときとタブが出たときだけで、
        // 前の日から裏に残したアプリを前面に戻すと、ホームかカレンダーのタブが出るまで前の日のままだった（そのあいだに［＋］を押すと
        // 前の日から始まる）。2026-10-17 の実機の不具合（Home の次の予定に直近の予定が出ない）の原因の候補の一つ（spec の記録の同じ日）。
        // 日が同じなら何もしない
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            calendarStore.updateToday()
            // 保存先の移行の先送りのやり直しと、iPhone の許可の読み直し（spec §89.6・§89.8）
            connection.handleBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
            calendarStore.updateToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .receive(on: DispatchQueue.main)) { _ in
            calendarStore.updateToday()
        }
        // iPhone のロックを解除して、守られたファイルを読めるようになったとき：連携の設定を確かめられなかったら読み直す
        // （確かめられていれば何もしない。spec §89.6・2026-10-19 決定 3）
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .receive(on: DispatchQueue.main)) { _ in
            _ = connection.reloadPreferences()
        }
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
    /// その日を選んだ新規の 3 分割画面を開く。`-TimyCueEditorEdit 予定名` なら、その見本の予定の編集を開く（DEBUG のときだけ）
    private func openEditorForScreenshot() {
        #if DEBUG
        guard !showsEditorForScreenshot else { return }
        // 既存の予定の「カレンダー」の行（所属の表示。Q113）の画面写真
        if let title = UserDefaults.standard.string(forKey: "TimyCueEditorEdit") {
            editorStore.refresh()
            guard let event = editorStore.events.first(where: { $0.title == title }),
                  (try? editorStore.startEditing(eventID: event.id)) != nil else { return }
            if UserDefaults.standard.string(forKey: "TimyCueEditorRow") == "calendar" { editorStore.toggleRow(.calendar) }
            showsEditorForScreenshot = true
            return
        }
        guard let raw = UserDefaults.standard.string(forKey: "TimyCueEditorDays") else { return }
        let today = CalendarDay(Date())
        let days = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.map { today.adding(days: $0) }
        guard let first = days.first else { return }
        editorStore.startNew(on: first)
        days.dropFirst().forEach(editorStore.addDay)
        editorStore.setStartMinute(14 * 60, on: first)
        editorStore.content.title = "見本の打合せ"
        // 起動引数 -TimyCueEditorRow calendar で「カレンダー」の行を開いておく（保存先の画面写真）
        if UserDefaults.standard.string(forKey: "TimyCueEditorRow") == "calendar" { editorStore.toggleRow(.calendar) }
        showsEditorForScreenshot = true
        #endif
    }

    /// Codemagic の画面写真用：起動引数 `-TimyCueSampleDefaultChange work` で、作成画面を開いてから少しあとに、見本の連携の
    /// 新しい予定の既定の保存先を「仕事」（見本のカレンダーの id は sample-＋値）に変える（開いたあとに設定が変わって保存先が変わったときの
    /// 確かめ。2026-10-19 決定 1。DEBUG のときだけ。メモリの中だけで、設定のファイルにも Apple カレンダーにも触れない）
    private func changeSampleSettingsForScreenshot() {
        #if DEBUG
        guard let name = UserDefaults.standard.string(forKey: "TimyCueSampleDefaultChange") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            connection.changeSamplePreferences { preferences in
                preferences.saveTargetKind = .appleCalendar
                preferences.defaultCalendarID = "sample-\(name)"
            }
        }
        #endif
    }

    /// Codemagic の画面写真用：起動引数 `-TimyCueScreenshot YES` のとき、最初の画面を出したら書類のフォルダに印のファイルを書く
    /// （DEBUG のときだけ）。撮る手順は、この印が出るのを待ってから撮る（シミュレータで起動画面が長く残ることがあり、
    /// 決まった秒数だけ待つ撮り方では撮り損ねた：ビルド確認 #36・#39・#43）
    private func markReadyForScreenshot() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "TimyCueScreenshot"),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? Data().write(to: folder.appendingPathComponent("timycue-screenshot-ready"))
        #endif
    }

    /// 2026-10-19 TestFlight 1.0 (30) のクラッシュの再現と確かめ（DEBUG のときだけ。Codemagic のシミュレータで、-TimyCueRealData YES と一緒に使う）。
    /// 起動引数 `-TimyCueReproSystemDefault` で、本物の Apple カレンダー（シミュレータのカレンダー）の設定を実機と同じ形にする。
    /// hidden：新しい予定の保存先を iPhone の既定にして、そのカレンダーの表示を OFF。
    /// explicitHidden：保存先に iPhone の既定のカレンダーをはっきり選んで、そのカレンダーの表示を OFF
    private func applyReproSettings() {
        #if DEBUG
        guard let mode = UserDefaults.standard.string(forKey: "TimyCueReproSystemDefault") else { return }
        Task { @MainActor in
            var tries = 0
            while connection.systemDefaultCalendarID == nil && tries < 40 {
                try? await Task.sleep(for: .milliseconds(250))
                tries += 1
            }
            guard let id = connection.systemDefaultCalendarID else { return }
            if mode == "explicitHidden" {
                connection.setShown(true, calendarID: id)
                connection.setDefaultSaveTarget(.calendar(id))
            } else {
                connection.setDefaultSaveTarget(.systemDefault)
            }
            connection.setShown(false, calendarID: id)
        }
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
