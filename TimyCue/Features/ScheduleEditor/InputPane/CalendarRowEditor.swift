import SwiftUI

/// 「カレンダー」の行を開いたところ（spec §89.3・Q97・Q99・Q113。S3）。
/// 新規・コピーは「TimyCue のみ」と使える Apple カレンダーから、この予定だけの保存先を選ぶ（設定の既定は変えない）。
/// 既存の Apple の予定は所属を変えられる先（使える Apple カレンダー）、連携中のローカルの予定は「Apple Calendarに保存」の移す先を選ぶ。
/// 選んだ保存先の説明をチップの下に出す（TimyCue のみは spec §89.2 の推奨の文。ほかの文言は仮）
struct CalendarRowEditor: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if store.calendarRowIsMoveTarget {
                Text("「Apple Calendarに保存」の移す先")
                    .font(EditorMetrics.lockNoticeFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ChipRow(options: store.calendarRowChoices,
                    label: { store.choiceLabel($0) },
                    isSelected: { $0 == store.selectedSaveChoice },
                    onTap: { store.chooseSaveTarget($0) })
            if let note = store.calendarRowNote {
                Text(note)
                    .font(EditorMetrics.lockNoticeFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
