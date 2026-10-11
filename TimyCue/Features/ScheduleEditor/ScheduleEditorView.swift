import SwiftUI

/// 予定登録・編集・コピーの専用 3 分割画面（仕様 §31・§32）。カレンダー画面とは分ける。
/// 左上：時間画面、右上：予定入力、下：日付カレンダー。3 つとも常に出し、それぞれ別々に動く。
struct ScheduleEditorView: View {
    /// 下カレンダーを最初に出す月
    let initialMonth: CalendarMonth
    /// 予定を消したとき（予定詳細も閉じるため）
    var onDeleted: () -> Void = {}

    @Environment(ScheduleEditorStore.self) private var store
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(\.dismiss) private var dismiss

    @FocusState private var focusedRow: InputRow?
    @State private var confirmsDiscard = false
    @State private var confirmsDelete = false
    @State private var showsSavedMessage = false

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
                              onDelete: { confirmsDelete = true })
                }
                .frame(height: bodyHeight * topRatio)
                Theme.Colors.separator.frame(height: EditorMetrics.paneSpacing)
                DateCalendarPane(initialMonth: initialMonth)
                    .frame(height: max(bodyHeight * (1 - topRatio) - EditorMetrics.paneSpacing, 0))
            }
            .animation(.easeInOut(duration: 0.2), value: isTyping)
        }
        .background(Theme.Colors.separator.ignoresSafeArea())
        .overlay(alignment: .top) {
            if showsSavedMessage {
                // 保存しても画面は閉じない。少しのあいだ知らせる（§65）
                Text("✓ 保存しました")
                    .font(EditorMetrics.headerTitleFont)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.Colors.textPrimary.opacity(0.85)))
                    .padding(.top, EditorMetrics.headerHeight + 8)
                    .transition(.opacity)
            }
        }
        // 未保存のまま離れるときは確かめる（§66）
        .confirmationDialog("保存していない変更があります", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("変更を破棄して閉じる", role: .destructive) { close() }
            Button("編集を続ける", role: .cancel) {}
        }
        .confirmationDialog("この予定を削除しますか？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("予定を削除", role: .destructive) { deleteEvent() }
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
            Button(store.saveButtonTitle) { save() }
                .font(EditorMetrics.saveButtonFont)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: EditorMetrics.headerHeight)
        .background(Theme.Colors.surface)
    }

    /// 保存する（§65・§66）。足りないものがあれば store が該当の行を開いて知らせる（§46）。
    /// 新規・コピーは保存した予定を保存済みのブロックにして、続けて登録できるよう新規に戻す（表示中の日は残す。仮）
    private func save() {
        do {
            try store.save()
        } catch {
            return
        }
        focusedRow = nil
        calendarStore.reload()
        switch store.mode {
        case .new, .copy:
            store.startNew(on: store.displayedDay)
        case .edit:
            break
        }
        withAnimation { showsSavedMessage = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showsSavedMessage = false }
        }
    }

    private func deleteEvent() {
        do {
            try store.deleteEditingEvent()
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
