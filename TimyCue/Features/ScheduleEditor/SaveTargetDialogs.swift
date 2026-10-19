import SwiftUI

/// 作成画面で、保存の前に保存先を選んでもらう確かめ（spec §89.4・Q99・Q111-4。S3）。作成画面の本体を短く保つため、別にする。
/// 開いているあいだに連携が外れたとき・連携の設定を確かめられないときの確かめ（2026-10-19 ユーザー指示 3・決定 3）は LinkLossDialog、
/// 開いたあとに設定が変わって保存先が変わったときの確かめ（2026-10-19 決定 1）は SaveTargetChangeDialog。文言は仮
struct SaveTargetDialogs: ViewModifier {
    @Environment(ScheduleEditorStore.self) private var store
    @Environment(CalendarConnection.self) private var connection
    /// 新しい予定の保存先がまだ決まっていないので、初めて保存する前に聞いている
    @Binding var asksFirstSaveTarget: Bool
    /// 保存先が使えないので、保存の前に選び直してもらっている
    @Binding var asksSaveTargetAgain: Bool
    /// 開いているあいだに連携が外れ、出していた Apple の保存先に保存できない（または連携の設定を確かめられない）ので、
    /// TimyCue のみに保存するかを聞いている
    @Binding var asksLinkLoss: Bool
    /// 開いたあとに設定が変わって保存先が変わったので、新しい保存先に保存するかを聞いている
    @Binding var asksSaveTargetChange: Bool
    /// 保存する（作成画面の保存と同じ。閉じる・失敗を知らせるのも作成画面）
    let onSave: () -> Void

    func body(content: Content) -> some View {
        content
            // 移行で保存先がまだ決まっていない今の利用者には、連携中に初めて保存するときだけ聞く（Q111-4）。
            // 選んだ保存先は、この予定にもこれからの新しい予定にも使う（本文で明示する。spec §89.4 のはっきり確かめた操作）
            .confirmationDialog("新しい予定の保存先を選んでください", isPresented: $asksFirstSaveTarget, titleVisibility: .visible) {
                ForEach(store.firstSaveTargetOptions, id: \.self) { option in
                    Button(store.defaultTargetLabel(option)) { chooseFirstSaveTarget(option) }
                }
                if store.hasMoreFirstSaveTargets {
                    // 行で選んだものは、この予定だけに使う
                    Button("ほかのカレンダーを選ぶ") { store.openCalendarRow() }
                }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("選んだ保存先は、これからの新しい予定にも使います（設定 ＞ カレンダー連携 で変えられます）。「TimyCue のみ」はこのiPhoneに保存し、Appleカレンダーやほかの端末とは同期しません。")
            }
            // 保存先が使えないときは、保存の前に知らせて選び直してもらう（spec §89.4・E-10）。選んだ保存先はこの予定だけに使い、
            // 設定の既定は変えない（Q99）。「表示をONにして保存」は表示 OFF のときだけ（表示のみの解除は勧めない）
            .confirmationDialog("保存先のカレンダーを使えません", isPresented: $asksSaveTargetAgain, titleVisibility: .visible,
                                presenting: store.saveTargetPrompt) { prompt in
                ForEach(store.saveTargetPromptChoices, id: \.self) { choice in
                    Button(store.promptButtonTitle(choice)) {
                        store.chooseSaveTarget(choice)
                        onSave()
                    }
                }
                if store.hasMoreSaveTargets {
                    Button("ほかのカレンダーを選ぶ") { store.openCalendarRow() }
                }
                if let hiddenCalendarID = prompt.hiddenCalendarID {
                    Button(showButtonTitle(prompt)) {
                        // 表示の設定を保存できなければ、知らせて予定は保存しない。利用者が決めたことなので、表示を ON にしたことを
                        // 保存先の変化として確かめない（2026-10-19 決定 1）
                        if store.applyOwnSettingsChange({ connection.setShown(true, calendarID: hiddenCalendarID) }) { onSave() }
                    }
                }
                Button("やめる", role: .cancel) {}
            } message: { prompt in
                Text(prompt.message)
            }
            .modifier(LinkLossDialog(isPresented: $asksLinkLoss, onSave: onSave))
            .modifier(SaveTargetChangeDialog(isPresented: $asksSaveTargetChange, onSave: onSave))
    }

    /// 「「○○」の表示をONにして保存」
    private func showButtonTitle(_ prompt: SaveTargetPrompt) -> String {
        "「\(prompt.calendarTitle)」の表示をONにして保存"
    }

    /// 初めての確かめで既定の保存先を選んだ：設定に保存できたら、その保存先でこの予定も保存する（作成画面の決まりは先に新しくなる）。
    /// 保存できなければ予定は保存せず、この予定の選びだけ残す（設定の失敗の知らせが出る。もう一度保存を押すとその保存先で保存する）。
    /// 利用者が決めたことなので、既定が変わったことを保存先の変化として確かめない（2026-10-19 決定 1）
    private func chooseFirstSaveTarget(_ option: DefaultSaveTarget) {
        if store.applyOwnSettingsChange({ connection.setDefaultSaveTarget(option) }) {
            onSave()
        } else if let choice = store.eventChoice(for: option) {
            store.chooseSaveTarget(choice)
        }
    }
}

/// 作成画面（新規・コピー）を開いたあとに、連携したまま設定（既定の保存先・iPhone の既定・保存先のカレンダーの表示・使えるかどうか）が
/// 変わって、行で選んでいない新しい予定の保存先が変わったときの、保存の前の確かめ（spec §89.4・2026-10-19 決定 1）。
/// 新しい保存先に保存するか、「カレンダー」の行で選び直すか、やめるかを聞く。文言は仮
private struct SaveTargetChangeDialog: ViewModifier {
    @Environment(ScheduleEditorStore.self) private var store
    @Binding var isPresented: Bool
    let onSave: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("保存先が変わりました", isPresented: $isPresented, titleVisibility: .visible,
                                presenting: store.saveTargetChangePrompt) { prompt in
                Button(prompt.saveButtonTitle) {
                    // 確かめた保存先が今も同じときだけ、確かめたことにして保存する（違えば保存は止まる）
                    store.confirmSaveTargetChange(prompt)
                    onSave()
                }
                Button("ほかの保存先を選ぶ") { store.openCalendarRow() }
                Button("やめる", role: .cancel) {}
            } message: { prompt in
                Text(prompt.message)
            }
    }
}

/// 作成画面（新規・コピー）を開いているあいだに連携が外れ（連携 OFF・許可がなくなった）、画面に出していた Apple カレンダーの保存先に
/// 保存できないときの、保存の前の確かめ（2026-10-19 ユーザー指示 3）。黙って TimyCue のみへ変えず、TimyCue のみに保存するかを聞く。
/// 連携の設定を確かめられない（設定のファイルを開けない）あいだの新しい予定も、ここで聞く（2026-10-19 決定 3）。
/// 文言は仮
private struct LinkLossDialog: ViewModifier {
    @Environment(ScheduleEditorStore.self) private var store
    @Binding var isPresented: Bool
    let onSave: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Apple カレンダーには保存できません", isPresented: $isPresented, titleVisibility: .visible,
                                presenting: store.linkLossPrompt) { _ in
                Button("\(SaveTargetRules.timyCueOnlyLabel)に保存") {
                    // TimyCue のみをはっきり選んでから保存する（この予定だけ。設定の既定は変えない）
                    store.chooseSaveTarget(.timyCueOnly)
                    onSave()
                }
                Button("やめる", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }
}
