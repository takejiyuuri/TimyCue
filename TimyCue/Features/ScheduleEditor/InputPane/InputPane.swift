import SwiftUI

/// 3 分割画面の右上：予定入力（仕様 §44〜§49・§50〜§55・§62・§64）。
/// 1 項目 1 行で情報を詰めて並べ、行を押すとその直下に編集を開く。同時に開くのは 1 行だけ（§45）
struct InputPane: View {
    @Environment(ScheduleEditorStore.self) private var store
    /// 文字を入れている行（キーボードが出ている間の 3 分割の比率に使う。§67）
    var focusedRow: FocusState<InputRow?>.Binding
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // コピーは既存予定の編集中だけ、右の入力の上（固定ヘッダー付近）に出す。削除とは離す（Q25）
            if case .edit = store.mode {
                CopyBar(onCopy: onCopy)
            }
            rows
        }
        .background(Theme.Colors.surface)
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // 足りない項目があるときの知らせ（§46：保存ボタンを無効にするだけにしない）
                    if let issue = store.presentedIssue {
                        Text(issue.message)
                            .font(EditorMetrics.issueFont)
                            .foregroundStyle(Theme.Colors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.s)
                            .background(Theme.Colors.danger.opacity(0.08))
                    }
                    ForEach(store.visibleRows, id: \.self) { row in
                        InputRowView(row: row,
                                     value: store.valueText(for: row),
                                     isExpanded: store.expandedRow == row,
                                     color: row == .color ? store.content.metadata.color : nil)
                            .id(row)
                            .onTapGesture { store.toggleRow(row) }
                        if store.expandedRow == row {
                            InlineEditor(row: row, focusedRow: focusedRow)
                                .padding(.horizontal, Theme.Spacing.m)
                                .padding(.bottom, Theme.Spacing.m)
                        }
                    }
                    if case .edit = store.mode {
                        DeleteButton(onDelete: onDelete)
                    }
                }
            }
            .onChange(of: store.expandedRow) { _, row in
                if let row { withAnimation { proxy.scrollTo(row, anchor: .top) } }
            }
        }
    }
}

/// 右の入力の上に固定する、コピーの操作（Q25）
private struct CopyBar: View {
    let onCopy: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onCopy) {
                Label("コピー", systemImage: "doc.on.doc")
                    .font(EditorMetrics.chipFont)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
    }
}

/// 右上の 1 行（左に項目名、右に今の値）
private struct InputRowView: View {
    let row: InputRow
    let value: String
    let isExpanded: Bool
    let color: EventColor?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(row.label)
                .font(EditorMetrics.inputLabelFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: EditorMetrics.inputLabelWidth, alignment: .leading)
            if let color {
                Circle()
                    .fill(EventPalette.color(for: color))
                    .frame(width: 12, height: 12)
            }
            Text(value)
                .font(EditorMetrics.inputValueFont)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: EditorMetrics.inputRowHeight)
        .background(isExpanded ? Theme.Colors.accent.opacity(0.10) : Color.clear)
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}

/// 行の直下に開く編集（§45）
private struct InlineEditor: View {
    let row: InputRow
    var focusedRow: FocusState<InputRow?>.Binding
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        switch row {
        case .title:
            TextField("予定名", text: $store.content.title)
                .textFieldStyle(.roundedBorder)
                .focused(focusedRow, equals: .title)
                .submitLabel(.done)
                .onAppear { focusedRow.wrappedValue = .title }
        case .location:
            // 候補（前回の場所・よく使う場所・現在地など。§48）は入力の候補の段階で足す
            TextField("場所", text: Binding(
                get: { store.content.locationName ?? "" },
                set: { store.content.locationName = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
                .focused(focusedRow, equals: .location)
                .submitLabel(.done)
        case .arrivalTarget:
            ChipRow(options: ScheduleEditorStore.arrivalTargetChoices.map(Optional.some) + [nil],
                    label: { $0.map { "\($0)分前" } ?? "未設定" },
                    isSelected: { store.content.metadata.arrivalTargetMinutes == $0 },
                    onTap: { store.content.metadata.arrivalTargetMinutes = $0 })
        case .transport:
            ChipRow(options: TransportMode.allCases,
                    label: \.displayName,
                    isSelected: { store.content.metadata.transport == $0 },
                    onTap: { store.content.metadata.transport = $0 })
        case .route:
            ChipRow(options: RouteOption.allCases,
                    label: \.displayName,
                    isSelected: { store.content.metadata.route == $0 },
                    onTap: { store.content.metadata.route = $0 })
        case .notifications:
            // 複数選べる。何も選ばなければ「通知なし」（§17）。予定開始○分前・カスタムは入力の段階で足す
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ChipRow(options: NotificationTiming.presets,
                        label: { $0 == .atDeparture ? "出発時" : "出発\($0.label)前" },
                        isSelected: { store.content.metadata.notifications.timings.contains($0) },
                        onTap: { timing in
                            if store.content.metadata.notifications.timings.contains(timing) {
                                store.content.metadata.notifications.timings.remove(timing)
                            } else {
                                store.content.metadata.notifications.timings.insert(timing)
                            }
                        })
                ChipRow(options: [true],
                        label: { _ in "通知なし" },
                        isSelected: { _ in store.content.metadata.notifications.isOff },
                        onTap: { _ in store.content.metadata.notifications = .off })
            }
        case .repeatRule:
            // 毎日・毎週・隔週・毎月・カスタム（§54）は繰り返しの段階で足す
            ChipRow(options: [RepeatRule.none],
                    label: \.displayName,
                    isSelected: { store.content.repeatRule == $0 },
                    onTap: { store.content.repeatRule = $0 })
        case .color:
            HStack(spacing: Theme.Spacing.m) {
                ForEach(EventColor.allCases, id: \.self) { color in
                    Circle()
                        .fill(EventPalette.color(for: color))
                        .frame(width: 26, height: 26)
                        .overlay {
                            if store.content.metadata.color == color {
                                Circle().strokeBorder(Theme.Colors.textPrimary, lineWidth: 2)
                            }
                        }
                        .onTapGesture { store.content.metadata.color = color }
                }
            }
        case .end:
            EndEditor()
        }
    }
}

/// 終了の行の編集（Q24）：未設定・30・60・90・120 分・カスタム。時間画面の下端ハンドルとは同じ値を見る
private struct EndEditor: View {
    @Environment(ScheduleEditorStore.self) private var store
    @State private var showsCustom = false

    private enum Choice: Hashable {
        case unset
        case minutes(Int)
        case custom
    }

    var body: some View {
        let current = store.displayedDay.flatMap { store.durationMinutes(on: $0) }
        let isPreset = current.map { ScheduleEditorStore.durationChoices.contains($0) } ?? true
        let hasStart = store.displayedDay.map { store.startMinutes[$0] != nil } ?? false

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if !hasStart {
                Text("先に開始時刻を決めてください")
                    .font(EditorMetrics.inputLabelFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ChipRow(options: [Choice.unset] + ScheduleEditorStore.durationChoices.map(Choice.minutes) + [Choice.custom],
                    label: { choice in
                        switch choice {
                        case .unset: "未設定"
                        case .minutes(let minutes): "\(minutes)分"
                        case .custom: isPreset ? "カスタム" : "\(current ?? 0)分"
                        }
                    },
                    isSelected: { choice in
                        switch choice {
                        case .unset: current == nil && !showsCustom
                        case .minutes(let minutes): current == minutes && !showsCustom
                        case .custom: showsCustom || !isPreset
                        }
                    },
                    onTap: { choice in
                        switch choice {
                        case .unset:
                            showsCustom = false
                            store.setDuration(nil)
                        case .minutes(let minutes):
                            showsCustom = false
                            store.setDuration(minutes)
                        case .custom:
                            showsCustom = true
                            if current == nil { store.setDuration(60) }
                        }
                    })
            if showsCustom, let minutes = current {
                Stepper("所要時間 \(minutes)分",
                        value: Binding(get: { minutes }, set: { store.setDuration($0) }),
                        in: ScheduleEditorStore.customDurationRange,
                        step: ScheduleEditorStore.customDurationStep)
                    .font(EditorMetrics.chipFont)
            }
            if store.canApplyDurationToAllDays {
                // 選んでいる全部の日へ、今の所要時間を入れ直す（Q5）
                Button("全日に適用") { store.applyDurationToAllDays() }
                    .font(EditorMetrics.chipFont)
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// 選択肢を横に並べたもの
private struct ChipRow<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    let isSelected: (Option) -> Bool
    let onTap: (Option) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(options, id: \.self) { option in
                    let selected = isSelected(option)
                    Text(label(option))
                        .font(EditorMetrics.chipFont)
                        .foregroundStyle(selected ? Color.white : Theme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Theme.Colors.accent : Theme.Colors.background))
                        .overlay { Capsule().strokeBorder(Theme.Colors.separator, lineWidth: selected ? 0 : 1) }
                        .contentShape(Capsule())
                        .onTapGesture { onTap(option) }
                }
            }
        }
    }
}

/// 編集のときだけ、右の入力のいちばん下に独立して出す「予定を削除」。誤操作を防ぐため固定ヘッダーには置かない（§64・Q25）
private struct DeleteButton: View {
    let onDelete: () -> Void

    var body: some View {
        Button("予定を削除", role: .destructive, action: onDelete)
            .font(EditorMetrics.chipFont)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            .padding(.top, Theme.Spacing.xl)
    }
}
