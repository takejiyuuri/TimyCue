import SwiftUI

/// カレンダータブ。月表示が主役で、編集の画面は常に出さない（仕様 §18）。予定検索は設けない（v1.1）。
/// 吹き出しの日付を押すとその日の 1 日タイムラインへ（仕様 §25）。予定詳細は別の画面にせず吹き出しで出す（Q27）。
/// 予定詳細の「編集」で 3 分割画面を開き、閉じたら元の画面（日付・スクロール位置・倍率・吹き出し）に戻る（Q30）
struct CalendarTabView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(ScheduleEditorStore.self) private var editorStore
    @Environment(CalendarConnection.self) private var connection
    /// 「＋」で開いた新規の 3 分割画面（Q21）
    @State private var newEventDay: CalendarDay?

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            VStack(spacing: 0) {
                CalendarHeaderView(year: store.stickyMonth.yearLabel,
                                   onNewEvent: { openNewEvent() })
                    .contentShape(Rectangle())
                    .onTapGesture { store.closeAllPopovers() }
                MonthCalendarView()
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CalendarRoute.self) { route in
                switch route {
                case .timeline(let day):
                    DayTimelineView(day: day)
                }
            }
            .fullScreenCover(item: $store.editRequest) { request in
                ScheduleEditorView(initialMonth: request.month,
                                   onSaved: { saved in
                                       // 「別の日にコピー」を保存したら、元の画面のまま軽い完了の知らせを出す（2026-10-14 決定 C8）
                                       if case .copy = editorStore.mode { store.showCopyCompletion(count: saved.count) }
                                   },
                                   onDeleted: { store.closeEventDetail(request.id) })
                    .environment(editorStore)
                    .environment(store)
                    .environment(connection)
            }
        }
        .onAppear {
            store.updateToday()
            openForScreenshot()
        }
        // 保存のあとの軽い知らせ（「3件コピーしました」など。2026-10-14 決定 C8。見た目と出す長さは仮）
        .overlay(alignment: .bottom) {
            if let message = store.completionMessage {
                CompletionToast(message: message)
                    .padding(.bottom, CalendarMetrics.completionToastBottomPadding)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.completionMessage)
        .task(id: store.completionMessage) {
            guard store.completionMessage != nil else { return }
            try? await Task.sleep(for: .seconds(CalendarMetrics.completionToastSeconds))
            if !Task.isCancelled { store.clearCompletionMessage() }
        }
        // 開いただけでは iOS の許可のダイアログを出さない。未連携のときだけ、使う理由と「カレンダーを連携」の案内を出す（Q38）
        .overlay {
            if connection.showsFirstGuidance {
                CalendarGuidanceView(
                    onConnect: { Task { await connection.connect() } },
                    onLater: { connection.dismissGuidance() })
            }
        }
        .fullScreenCover(item: $newEventDay) { day in
            ScheduleEditorView(initialMonth: CalendarMonth(day), onSaved: { saved in
                // 保存したら月カレンダーへ戻り、保存した日（複数日なら最初の日）の吹き出しを開く（Q22）
                if let first = saved.map(\.day).min() {
                    store.showSavedDay(first)
                }
            })
            .environment(editorStore)
            .environment(store)
            .environment(connection)
        }
    }

    /// 月カレンダーの「＋」（Q21）：選択中の日があればその日、なければ今日を選んだ新規。開始時刻は未設定
    private func openNewEvent() {
        let day = store.dayForNewEvent
        editorStore.refresh()
        editorStore.startNew(on: day)
        newEventDay = day
    }

    /// Codemagic で画面写真を撮るときの起動引数（DEBUG のときだけ）。
    /// `-TimyCueOpenDays "0,4"`：今日から 0 日後・4 日後の吹き出しを開く。`-TimyCueTimelineDay 0`：その日の 1 日タイムラインを開く。
    /// `-TimyCueDetailOfFirstEventToday YES`：今日の 1 日タイムラインで、最初の時間指定の予定の詳細の吹き出しを出す
    private func openForScreenshot() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "TimyCueOpenDays"), store.openDays.isEmpty {
            for offset in raw.split(separator: ",").compactMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                store.tapDay(store.today.adding(days: offset))
            }
        }
        if let raw = defaults.string(forKey: "TimyCueTimelineDay"), let offset = Int(raw), store.path.isEmpty {
            store.openTimeline(store.today.adding(days: offset))
        }
        if defaults.bool(forKey: "TimyCueDetailOfFirstEventToday"), store.path.isEmpty,
           let first = store.timedEvents(on: store.today).first {
            store.openTimeline(store.today)
            store.tapTimelineEvent(first.id)
        }
        // `-TimyCueTapNewEvent YES`：月カレンダーの「＋」と同じ処理で新規を開く（2026-10-19 TestFlight 1.0 (30) のクラッシュの再現と確かめ）。
        // 1 日タイムラインを開くときは、タイムラインの「＋」のほうで開く
        if defaults.bool(forKey: "TimyCueTapNewEvent"), defaults.string(forKey: "TimyCueTimelineDay") == nil, newEventDay == nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                openNewEvent()
            }
        }
        #endif
    }
}

/// 保存のあとの軽い知らせ。強い影は付けず、面の色と区切り線で分ける（2026-10-14 決定）
private struct CompletionToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .background(Capsule().fill(Theme.Colors.surface))
            .overlay(Capsule().strokeBorder(Theme.Colors.separator, lineWidth: 1))
    }
}
