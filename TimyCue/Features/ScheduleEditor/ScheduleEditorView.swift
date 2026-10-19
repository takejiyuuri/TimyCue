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
    @Environment(\.dismiss) private var dismiss

    @FocusState private var focusedRow: InputRow?
    @State private var confirmsDiscard = false
    @State private var confirmsDelete = false
    /// 「Apple Calendarに保存」を確かめている（§1.12）
    @State private var confirmsMoveToApple = false
    /// 繰り返し予定を保存するときに、範囲を聞いている（Q44）
    @State private var asksSaveScope = false
    /// 新しい予定の保存先がまだ決まっていないので、初めて保存する前に聞いている（Q111-4）
    @State private var asksFirstSaveTarget = false
    /// 保存先が使えないので、保存の前に選び直してもらっている（spec §89.4・E-10）
    @State private var asksSaveTargetAgain = false
    /// 開いているあいだに連携が外れ、出していた Apple の保存先に保存できないので、TimyCue のみに保存するかを聞いている（2026-10-19 指示 3）。
    /// 連携の設定を確かめられないあいだの新しい予定も、ここで聞く（2026-10-19 決定 3）
    @State private var asksLinkLoss = false
    /// 開いたあとに設定が変わって保存先が変わったので、新しい保存先に保存するかを聞いている（2026-10-19 決定 1）
    @State private var asksSaveTargetChange = false

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
            // 保存先の設定（初めての確かめ・「表示をONにして保存」）を保存できなかったときの知らせ。全画面の上でも出るよう、
            // 作成画面の失敗のアラートとは別の階層に付ける（spec §89.9）
            .settingsFailureAlert()
        }
        .background(Theme.Colors.separator.ignoresSafeArea())
        // 未保存のまま離れるときは確かめる（§66）。一部の日だけ保存できたあとは、保存した日は残ることを添える（spec §89.9）
        .confirmationDialog(store.savedEventsThisSession.isEmpty ? "保存していない変更があります" : "まだ保存していない日があります",
                            isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button(store.savedEventsThisSession.isEmpty ? "変更を破棄して閉じる" : "保存していない日を捨てて閉じる",
                   role: .destructive) { close() }
            Button("編集を続ける", role: .cancel) {}
        } message: {
            if !store.savedEventsThisSession.isEmpty {
                Text("保存できた日の予定は、保存してあります。保存していない日の入力は消えます。")
            }
        }
        // 保存のたびの許可の案内（Q38 の保存時の再案内）はやめた（Q105）。保存先がまだ決まっていないときの初めての確かめと、
        // 保存先が実際に使えないときの保存の前の選び直しだけを出す（SaveTargetDialogs）
        .modifier(SaveTargetDialogs(asksFirstSaveTarget: $asksFirstSaveTarget,
                                    asksSaveTargetAgain: $asksSaveTargetAgain,
                                    asksLinkLoss: $asksLinkLoss,
                                    asksSaveTargetChange: $asksSaveTargetChange,
                                    onSave: { performSave() }))
        // 繰り返し予定は、保存するときに 1 回だけ範囲を聞く（Q44）
        .confirmationDialog("繰り返し予定の変更", isPresented: $asksSaveScope, titleVisibility: .visible) {
            ForEach(RecurrenceScope.allCases, id: \.self) { scope in
                Button(scope.displayName) { performSave(scope: scope) }
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("どの予定に変更を当てますか？")
        }
        // ローカル予定を Apple カレンダーへ移す（追加仕様書 §1.12）。確認を出すこと・文言は仮（未確定）。
        // 前回 Apple に作れたか確かめられなかった予定は、同じ予定がないことを確かめたかを聞いてから作る（spec §89.9）
        .confirmationDialog("Apple Calendarに保存しますか？", isPresented: $confirmsMoveToApple, titleVisibility: .visible) {
            Button(store.moveNeedsConfirmation ? "確かめたので保存する" : "Apple Calendarに保存") { moveToAppleCalendar() }
            Button("やめる", role: .cancel) {}
        } message: {
            if store.moveNeedsConfirmation {
                Text("前回、Apple Calendarに予定を作れたか確認できませんでした。Apple Calendarに同じ予定がないことを確かめてから保存してください。同じ予定があるときは、保存せずに重複候補から選んでください。")
            } else if let target = store.moveToAppleTargetName {
                // 移す先の名前を出す（移す先を確かめの画面で選ぶ形は S5。文言は仮）
                Text("Apple カレンダーの「\(target)」に予定を作り、到着目標などの設定も引き継ぎます。TimyCue の中の予定は削除します。")
            } else {
                Text("Apple Calendarに予定を作り、到着目標などの設定も引き継ぎます。TimyCue の中の予定は削除します。")
            }
        }
        // 保存・移す・削除に失敗したら、閉じずに理由と次の操作を出す（spec §89.9）。設定画面へ直接移るボタンは置かない（Q110）。
        // 一部だけ保存できて残りがない・予定は保存できたが設定を保存できなかったなどの知らせは、「OK」のあと閉じる
        .alert(store.failure?.title ?? "",
               isPresented: Binding(get: { store.failure != nil }, set: { if !$0 { store.dismissFailure() } }),
               presenting: store.failure) { failure in
            Button("OK", role: .cancel) {
                store.dismissFailure()
                if failure.closesEditor { finish(store.savedEventsThisSession) }
            }
        } message: { failure in
            Text(failure.message)
        }
        .task {
            #if DEBUG
            // Codemagic の画面写真用：起動引数 -TimyCueEditorAutoSave YES で、開いてすぐ保存を押す（保存の失敗の知らせを撮る）
            if UserDefaults.standard.bool(forKey: "TimyCueEditorAutoSave") {
                try? await Task.sleep(for: .milliseconds(600))
                save()
            }
            #endif
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

    /// 保存ボタン。開いているあいだに連携が外れて、出していた Apple の保存先に保存できなければ（連携の設定を確かめられないときも）、
    /// TimyCue のみに保存するかを先に聞く（黙って変えない。2026-10-19 指示 3・決定 3）。新しい予定の保存先がまだ決まっていなければ先に聞き
    /// （Q111-4）、保存先が使えなければ保存の前に選び直してもらう（spec §89.4）。開いたあとに設定が変わって保存先が変わっていれば、
    /// 新しい保存先に保存するかを聞く（2026-10-19 決定 1。使えない・未選択になったときは、上の 2 つが先に出るので重ねない）。
    /// 足りない項目があるときは、どれも出さずに行で知らせる（§46）
    private func save() {
        if store.linkLossPrompt != nil {
            asksLinkLoss = true
            return
        }
        if store.needsFirstSaveTargetChoice {
            asksFirstSaveTarget = true
            return
        }
        if store.saveTargetPrompt != nil {
            asksSaveTargetAgain = true
            return
        }
        if store.saveTargetChangePrompt != nil {
            asksSaveTargetChange = true
            return
        }
        if store.isEditingRecurringEvent && store.saveIssues.isEmpty {
            asksSaveScope = true
            return
        }
        performSave()
    }

    /// 保存して元の画面へ戻る（Q22）。足りないものがあれば store が該当の行を開いて知らせ、閉じない（§46）。
    /// 保存に失敗したときも閉じない。理由は store.failure をアラートで出す（spec §89.9）。
    /// 一部の日だけ保存できたときも、保存できた日はすぐカレンダーに出す
    private func performSave(scope: RecurrenceScope = .thisEvent) {
        do {
            try store.save(scope: scope)
        } catch {
            calendarStore.reload()
            return
        }
        focusedRow = nil
        // 知らせ（設定を保存できなかったなど）があれば、先に出す。閉じるのは「OK」のあと
        guard store.failure == nil else { return }
        // 一部の日だけ保存してから残りを保存したときも、この画面で保存した全部の日を渡す
        finish(store.savedEventsThisSession)
    }

    /// 移したら編集画面を閉じる（仮。未確定）
    private func moveToAppleCalendar() {
        let moved: CalendarEvent
        do {
            moved = try store.moveToAppleCalendar(confirmedUnknown: store.moveNeedsConfirmation)
        } catch {
            calendarStore.reload()
            return
        }
        focusedRow = nil
        finish([moved])
    }

    /// 保存が済んで、元の画面へ戻る
    private func finish(_ saved: [CalendarEvent]) {
        calendarStore.reload()
        onSaved(saved)
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

    /// 保存せずに閉じる。一部の日だけ保存できていたら、その日は元の画面に渡す
    private func close() {
        let saved = store.savedEventsThisSession
        if !saved.isEmpty { onSaved(saved) }
        store.discardChanges()
        calendarStore.reload()
        dismiss()
    }
}
