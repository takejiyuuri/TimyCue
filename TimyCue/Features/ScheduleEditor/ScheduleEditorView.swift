import SwiftUI

/// 予定登録・編集・コピーの専用 3 分割画面（仕様 §31・§32）。カレンダー画面とは分ける。
/// 左上：時間画面、右上：予定入力、下：日付カレンダー。3 つとも常に出し、それぞれ別々に動く。
/// 保存したら元の画面へ戻る（Q22。旧 §65 の「保存しても閉じない」は変更）
struct ScheduleEditorView: View {
    /// 下カレンダーを最初に出す月
    let initialMonth: CalendarMonth
    /// 保存したとき。保存した予定を渡す（元の画面が、保存した日や時刻を見せるため。Q22）
    var onSaved: ([CalendarEvent]) -> Void = { _ in }
    /// 予定を消したとき（予定詳細も閉じるため）
    var onDeleted: () -> Void = {}

    @Environment(ScheduleEditorStore.self) private var store
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(CalendarConnection.self) private var connection
    @Environment(\.dismiss) private var dismiss

    @FocusState private var focusedRow: InputRow?
    @State private var confirmsDiscard = false
    @State private var confirmsDelete = false
    /// 「Apple Calendarに保存」を確かめている（§1.12）
    @State private var confirmsMoveToApple = false
    @State private var showsGuidance = false
    /// 繰り返し予定を保存するときに、範囲を聞いている（Q44）
    @State private var asksSaveScope = false

    var body: some View {
        GeometryReader { geometry in
            // キーボードが出ている間は、右の入力を広げて下のカレンダーを縮める。左の時間軸は残す（§67）
            let isTyping = focusedRow != nil
            let topRatio = isTyping ? EditorMetrics.keyboardTopPaneRatio : EditorMetrics.topPaneRatio
            let leftRatio = isTyping ? EditorMetrics.keyboardTimePaneWidthRatio : EditorMetrics.timePaneWidthRatio
            let bodyHeight = max(geometry.size.height - EditorMetrics.headerHeight, 0)

            VStack(spacing: 0) {
                header
                HStack(spacing: EditorMetrics.paneSpacing) {
                    TimePane()
                        .frame(width: geometry.size.width * leftRatio)
                    InputPane(focusedRow: $focusedRow,
                              onCopy: { try? store.startCopy() },
                              onDelete: { confirmsDelete = true },
                              onMoveToApple: { confirmsMoveToApple = true })
                }
                .frame(height: bodyHeight * topRatio)
                Theme.Colors.separator.frame(height: EditorMetrics.paneSpacing)
                DateCalendarPane(initialMonth: initialMonth)
                    .frame(height: max(bodyHeight * (1 - topRatio) - EditorMetrics.paneSpacing, 0))
            }
            .animation(.easeInOut(duration: 0.2), value: isTyping)
        }
        .background(Theme.Colors.separator.ignoresSafeArea())
        // 未保存のまま離れるときは確かめる（§66）
        .confirmationDialog("保存していない変更があります", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("変更を破棄して閉じる", role: .destructive) { close() }
            Button("編集を続ける", role: .cancel) {}
        }
        // 初回の案内を「あとで」にしていたら、新しい予定を保存するときにもう一度だけ案内する（Q38）
        .sheet(isPresented: $showsGuidance) {
            CalendarGuidanceView(
                onConnect: {
                    showsGuidance = false
                    Task {
                        await connection.connect()
                        performSave()
                    }
                },
                onLater: {
                    connection.dismissGuidance()
                    showsGuidance = false
                    performSave()
                },
                laterTitle: "連携しないで保存")
            .presentationDetents([.medium])
        }
        // 繰り返し予定は、保存するときに 1 回だけ範囲を聞く（Q44）
        .confirmationDialog("繰り返し予定の変更", isPresented: $asksSaveScope, titleVisibility: .visible) {
            ForEach(RecurrenceScope.allCases, id: \.self) { scope in
                Button(scope.displayName) { performSave(scope: scope) }
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("どの予定に変更を当てますか？")
        }
        // ローカル予定を Apple カレンダーへ移す（追加仕様書 §1.12）。確認を出すこと・文言は仮（未確定）
        .confirmationDialog("Apple Calendarに保存しますか？", isPresented: $confirmsMoveToApple, titleVisibility: .visible) {
            Button("Apple Calendarに保存") { moveToAppleCalendar() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("Apple Calendarに予定を作り、到着目標などの設定も引き継ぎます。TimyCue の中の予定は削除します。")
        }
        // 削除も同じ 3 択（§64・Q44）
        .confirmationDialog(store.isEditingRecurringEvent ? "繰り返し予定の削除" : "この予定を削除しますか？",
                            isPresented: $confirmsDelete, titleVisibility: .visible) {
            if store.isEditingRecurringEvent {
                ForEach(RecurrenceScope.allCases, id: \.self) { scope in
                    Button(scope.displayName, role: .destructive) { deleteEvent(scope: scope) }
                }
            } else {
                Button("予定を削除", role: .destructive) { deleteEvent(scope: .thisEvent) }
            }
            Button("やめる", role: .cancel) {}
        }
    }

    /// 固定ヘッダー：閉じる・新規／編集中／コピー中・保存ボタン（§59〜§62）
    private var header: some View {
        HStack {
            Button("閉じる") {
                if store.hasUnsavedChanges {
                    confirmsDiscard = true
                } else {
                    close()
                }
            }
            Spacer()
            Text(store.mode.headerLabel)
                .font(EditorMetrics.headerTitleFont)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button { save() } label: {
                Text(store.saveButtonTitle).foregroundStyle(Theme.Colors.onAccent)
            }
            .font(EditorMetrics.saveButtonFont)
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accentFill)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: EditorMetrics.headerHeight)
        .background(Theme.Colors.surface)
    }

    /// 保存ボタン。足りないものがなく、新しい予定を作るときで、まだカレンダーを連携していなければ、先に案内する（Q38）
    private func save() {
        let isNew: Bool = {
            if case .edit = store.mode { return false }
            return true
        }()
        if isNew && store.saveIssues.isEmpty && connection.showsGuidanceBeforeSaving {
            showsGuidance = true
            return
        }
        if store.isEditingRecurringEvent && store.saveIssues.isEmpty {
            asksSaveScope = true
            return
        }
        performSave()
    }

    /// 保存して元の画面へ戻る（Q22）。足りないものがあれば store が該当の行を開いて知らせ、閉じない（§46）
    private func performSave(scope: RecurrenceScope = .thisEvent) {
        let saved: [CalendarEvent]
        do {
            saved = try store.save(scope: scope)
        } catch {
            return
        }
        focusedRow = nil
        calendarStore.reload()
        onSaved(saved)
        dismiss()
    }

    /// 移したら編集画面を閉じる（仮。未確定）
    private func moveToAppleCalendar() {
        let moved: CalendarEvent
        do {
            moved = try store.moveToAppleCalendar()
        } catch {
            return
        }
        focusedRow = nil
        calendarStore.reload()
        onSaved([moved])
        dismiss()
    }

    private func deleteEvent(scope: RecurrenceScope) {
        do {
            try store.deleteEditingEvent(scope: scope)
        } catch {
            return
        }
        calendarStore.reload()
        onDeleted()
        dismiss()
    }

    private func close() {
        store.discardChanges()
        calendarStore.reload()
        dismiss()
    }
}
