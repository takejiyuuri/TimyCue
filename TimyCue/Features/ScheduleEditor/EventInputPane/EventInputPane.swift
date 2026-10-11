import SwiftUI

/// 右上：入力画面。1 項目 1 行で情報密度を高くする（仕様 §27）。
/// 保存ボタンのあるヘッダーは固定し、項目の部分だけをスクロールする（仕様 §34）。
/// 各行をタップしてその下に入力欄を開く動き（インライン展開）は次の段階で入れる。
struct EventInputPane: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader()
            Divider().overlay(Theme.Colors.separator)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.label) { row in
                        InputRow(label: row.label, value: row.value, isPlaceholder: row.isPlaceholder)
                        Divider().overlay(Theme.Colors.separator.opacity(0.6))
                    }
                }
            }
        }
        .paneBackground()
    }

    private struct RowModel {
        let label: String
        let value: String
        var isPlaceholder = false
    }

    private var rows: [RowModel] {
        let content = store.content
        let end = store.displayedDay.flatMap(store.endMinute(on:))
        return [
            RowModel(label: "予定名", value: content.title.isEmpty ? "未入力" : content.title,
                     isPlaceholder: content.title.isEmpty),
            RowModel(label: "場所", value: content.locationName ?? "未設定",
                     isPlaceholder: content.locationName == nil),
            RowModel(label: "到着目標", value: content.arrivalTargetMinutes.map { "\($0)分前" } ?? "未設定",
                     isPlaceholder: content.arrivalTargetMinutes == nil),
            RowModel(label: "移動手段", value: content.transport?.displayName ?? "未設定",
                     isPlaceholder: content.transport == nil),
            RowModel(label: "通知", value: content.notifications.summary),
            RowModel(label: "繰り返し", value: content.repeatRule.displayName),
            RowModel(label: "終了", value: end.map(TimeText.hourMinute) ?? "未設定", isPlaceholder: end == nil),
            RowModel(label: "メモ", value: content.memo.isEmpty ? "なし" : content.memo,
                     isPlaceholder: content.memo.isEmpty),
        ]
    }
}

/// 固定ヘッダー：いま新規・編集中・コピー中のどれかと、保存ボタン（仕様 §34・§35）
struct EditorHeader: View {
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(store.mode.headerLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
            Button {
                _ = try? store.save()
            } label: {
                Text(store.saveButtonTitle)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(canSave ? Theme.Colors.accent : Theme.Colors.separator))
                    .foregroundStyle(canSave ? Color.white : Theme.Colors.textSecondary)
            }
            .disabled(!canSave)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs + 2)
    }

    private var canSave: Bool {
        store.dateValidation == .ready && store.hasUnsavedChanges
    }
}

/// 1 項目 1 行
struct InputRow: View {
    let label: String
    let value: String
    var isPlaceholder = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(isPlaceholder ? Theme.Colors.textSecondary.opacity(0.7) : Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
