import SwiftUI

/// 3 分割画面の右上：予定入力（仕様 §44〜§49・§50〜§55・§62・§64）。
/// 1 項目 1 行で情報を詰めて並べ、行を押すとその直下に編集を開く。同時に開くのは 1 行だけ（§45）
struct InputPane: View {
    @Environment(ScheduleEditorStore.self) private var store
    /// 文字を入れている行（キーボードが出ている間の 3 分割の比率に使う。§67）
    var focusedRow: FocusState<InputRow?>.Binding
    let onCopy: () -> Void
    let onDelete: () -> Void
    /// 「Apple Calendarに保存」（ローカル予定を移す。追加仕様書 §1.12）
    let onMoveToApple: () -> Void

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
                    // 書き込めない Apple カレンダーの予定：ロックの短い理由（追加仕様書 §1.7）
                    if let reason = store.appleFieldsLockReason {
                        Label(reason, systemImage: "lock.fill")
                            .font(EditorMetrics.lockNoticeFont)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.s)
                            .background(Theme.Colors.textSecondary.opacity(0.08))
                    }
                    ForEach(store.visibleRows, id: \.self) { row in
                        InputRowView(row: row,
                                     value: store.valueText(for: row),
                                     isExpanded: store.expandedRow == row,
                                     isLocked: store.isLocked(row),
                                     color: row == .color ? store.content.metadata.color : nil)
                            .id(row)
                            .onTapGesture { store.toggleRow(row) }
                        if store.expandedRow == row {
                            InlineEditor(row: row, focusedRow: focusedRow)
                                .padding(.horizontal, Theme.Spacing.m)
                                .padding(.bottom, Theme.Spacing.m)
                        }
                    }
                    if store.canMoveToAppleCalendar {
                        MoveToAppleButton(onMove: onMoveToApple)
                    }
                    // 書き込めないカレンダーの予定は消せない（§1.7）
                    if case .edit = store.mode, !store.areAppleFieldsLocked {
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
    /// 書き込めない Apple カレンダーの予定の、Apple 由来の項目（§1.7）
    let isLocked: Bool
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
                .foregroundStyle(isLocked ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(EditorMetrics.lockIconFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
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
            TitleEditor(focusedRow: focusedRow)
        case .location:
            LocationEditor(focusedRow: focusedRow)
        case .arrivalTarget:
            // ドラムロール。5 分おき（2026-10-13 実機の指摘）
            WheelPicker(options: ScheduleEditorStore.arrivalTargetWheelValues(including: store.content.metadata.arrivalTargetMinutes),
                        selection: $store.content.metadata.arrivalTargetMinutes) { minutes in
                Text(ScheduleEditorStore.arrivalTargetText(minutes))
            }
        case .transport:
            // ドラムロール（2026-10-13 実機の指摘）
            WheelPicker(options: TransportMode.allCases, selection: $store.content.metadata.transport) { mode in
                Text(mode.displayName)
            }
        case .route:
            ChipRow(options: RouteOption.allCases,
                    label: \.displayName,
                    isSelected: { store.content.metadata.route == $0 },
                    onTap: { store.content.metadata.route = $0 })
        case .notifications:
            // 複数選べる。何も選ばなければ「通知なし」（§17）
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
                CustomNotificationEditor()
            }
        case .repeatRule:
            RepeatEditor()
        case .color:
            // ドラムロール（2026-10-13 実機の指摘）
            WheelPicker(options: EventColor.allCases, selection: $store.content.metadata.color) { color in
                HStack(spacing: Theme.Spacing.s) {
                    Circle()
                        .fill(EventPalette.color(for: color))
                        .frame(width: 14, height: 14)
                    Text(color.displayName)
                }
            }
        case .end:
            EndEditor()
        case .calendar:
            // その予定だけ保存先を変える（Q32）
            ChipRow(options: store.writableCalendars,
                    label: \.title,
                    isSelected: { $0.id == (store.content.calendarID ?? store.defaultCalendarID) },
                    onTap: { store.content.calendarID = $0.id })
        }
    }
}

/// 予定名の編集と、過去の同名・似た名前の予定の候補（§47）。
/// 候補を選ぶと予定名だけ入れ、場所・色・到着目標・移動手段は「この予定の設定も使う」を押したときだけ入れる（勝手にすべて確定しない）
private struct TitleEditor: View {
    var focusedRow: FocusState<InputRow?>.Binding
    @Environment(ScheduleEditorStore.self) private var store
    @State private var chosen: TitleSuggestion?

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TextField("予定名", text: $store.content.title)
                .textFieldStyle(.roundedBorder)
                .focused(focusedRow, equals: .title)
                .submitLabel(.done)
                .onAppear { focusedRow.wrappedValue = .title }
            ForEach(store.titleSuggestions()) { suggestion in
                if suggestion.title != store.content.title || suggestion.locationName != store.content.locationName {
                    Button {
                        store.useTitle(of: suggestion)
                        chosen = suggestion
                    } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(suggestion.title)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            if let place = suggestion.locationName {
                                Text(place)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(EditorMetrics.chipFont)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let chosen, chosen.title == store.content.title {
                Button("この予定の設定も使う（場所・色・到着目標・移動手段）") {
                    store.useSettings(of: chosen)
                    self.chosen = nil
                }
                .font(EditorMetrics.chipFont)
                .buttonStyle(.bordered)
            }
        }
    }
}

/// 場所の編集と候補（§48）：前回の場所・よく使う場所・最近使った場所・場所なし。
/// 現在地と検索は移動時間の計算（第5段階）で足す
private struct LocationEditor: View {
    var focusedRow: FocusState<InputRow?>.Binding
    @Environment(ScheduleEditorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TextField("場所", text: Binding(
                get: { store.content.locationName ?? "" },
                set: { store.content.locationName = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
                .focused(focusedRow, equals: .location)
                .submitLabel(.done)
            let candidates = store.placeCandidates()
            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates) { candidate in
                        Button {
                            store.choosePlace(candidate.name)
                        } label: {
                            HStack(spacing: Theme.Spacing.s) {
                                Text(candidate.kind.label)
                                    .font(EditorMetrics.inputLabelFont)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(candidate.name)
                                    .font(EditorMetrics.chipFont)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if store.content.locationName == candidate.name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button("場所なし") { store.choosePlace(nil) }
                .font(EditorMetrics.chipFont)
                .buttonStyle(.bordered)
        }
    }
}

/// 行の直下に出すドラムロール（到着目標・移動手段・色。2026-10-13 実機の指摘）
private struct WheelPicker<Option: Hashable, Row: View>: View {
    let options: [Option]
    @Binding var selection: Option
    @ViewBuilder let label: (Option) -> Row

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                label(option).tag(option)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .frame(height: EditorMetrics.wheelPickerHeight)
        .clipped()
    }
}

/// 到着目標（§49）：5・10・15・20・30 分前・カスタム・未設定（2026-10-13 にドラムロールへ替えたので使わない）
private struct ArrivalTargetEditor: View {
    @Environment(ScheduleEditorStore.self) private var store
    @State private var showsCustom = false

    private enum Choice: Hashable {
        case minutes(Int)
        case custom
    }

    /// 到着目標は必ず値を持つので、「未設定」は出さない（Q70）
    var body: some View {
        let current = store.content.metadata.arrivalTargetMinutes
        let isPreset = ScheduleEditorStore.arrivalTargetChoices.contains(current)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ChipRow(options: ScheduleEditorStore.arrivalTargetChoices.map(Choice.minutes) + [Choice.custom],
                    label: { choice in
                        switch choice {
                        case .minutes(let minutes): "\(minutes)分前"
                        case .custom: isPreset ? "カスタム" : "\(current)分前"
                        }
                    },
                    isSelected: { choice in
                        switch choice {
                        case .minutes(let minutes): current == minutes && !showsCustom
                        case .custom: showsCustom || !isPreset
                        }
                    },
                    onTap: { choice in
                        switch choice {
                        case .minutes(let minutes):
                            showsCustom = false
                            store.content.metadata.arrivalTargetMinutes = minutes
                        case .custom:
                            showsCustom = true
                        }
                    })
            if showsCustom {
                Stepper("到着目標 \(current)分前",
                        value: Binding(get: { current }, set: { store.content.metadata.arrivalTargetMinutes = $0 }),
                        in: ScheduleEditorStore.customArrivalRange)
                    .font(EditorMetrics.chipFont)
            }
        }
    }
}

/// 通知のカスタム（§17）：出発○分前・予定開始○分前を、好きな分で足す。足したものは押すと外せる
private struct CustomNotificationEditor: View {
    @Environment(ScheduleEditorStore.self) private var store
    @State private var minutes = 15
    @State private var basedOnStart = false

    var body: some View {
        let custom = store.content.metadata.notifications.timings
            .filter { !NotificationTiming.presets.contains($0) }
            .sorted { $0.label < $1.label }
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if !custom.isEmpty {
                ChipRow(options: custom,
                        label: { "\($0.fullLabel) ×" },
                        isSelected: { _ in true },
                        onTap: { store.content.metadata.notifications.timings.remove($0) })
            }
            HStack(spacing: Theme.Spacing.s) {
                Picker("基準", selection: $basedOnStart) {
                    Text("出発").tag(false)
                    Text("予定開始").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                Stepper("\(minutes)分前", value: $minutes, in: ScheduleEditorStore.customNotificationRange,
                        step: ScheduleEditorStore.customMinuteStep)
                    .font(EditorMetrics.chipFont)
            }
            Button("この通知を足す") {
                let timing: NotificationTiming = basedOnStart ? .beforeStart(minutes: minutes) : .beforeDeparture(minutes: minutes)
                store.content.metadata.notifications.timings.insert(timing)
            }
            .font(EditorMetrics.chipFont)
            .buttonStyle(.bordered)
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

/// 繰り返し（§54・Q37）：なし・毎日・毎週・隔週・毎月・カスタム。カスタムは間隔・単位・曜日（毎週のとき）。どれも終わりの日を決められる。
/// 本来の繰り返しは Apple カレンダーの繰り返しを正本にするので、連携しているときだけ選べる（2026-10-12 変更。Q48 は仮）
private struct RepeatEditor: View {
    @Environment(ScheduleEditorStore.self) private var store
    @State private var showsCustom = false

    var body: some View {
        @Bindable var store = store
        let rule = store.content.repeatRule

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if !store.canRepeat {
                // 連携していないときは選べない（Q48）。同じ予定を何日も作るなら下カレンダーの複数日登録
                Text("カレンダーを連携すると、繰り返しを使えます")
                    .font(EditorMetrics.inputLabelFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if store.repeatBlockedByMultipleDays {
                // 複数日登録とは併用しない（Q49）
                Text("繰り返しは1日の予定で設定できます")
                    .font(EditorMetrics.inputLabelFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                if store.isEditingRecurringEvent {
                    Text("繰り返しの変更は、保存するときに「これ以降」か「すべて」を選ぶと当たります")
                        .font(EditorMetrics.inputLabelFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                ChipRow(options: RepeatRule.Choice.allCases,
                        label: \.displayName,
                        isSelected: { choice in
                            choice == .custom ? (showsCustom || rule.choice == .custom)
                                              : (!showsCustom && rule.choice == choice)
                        },
                        onTap: { choice in
                            if choice == .custom {
                                showsCustom = true
                                if !rule.isRepeating { store.content.repeatRule = .weekly }
                            } else {
                                showsCustom = false
                                var next = choice.preset
                                next.endDay = choice == .none ? nil : rule.endDay
                                store.content.repeatRule = next
                            }
                        })

                if showsCustom || rule.choice == .custom {
                    customEditor
                }
                if rule.isRepeating {
                    endEditor
                }
            }
        }
    }

    /// カスタム：何日／週／か月／年ごとか、毎週のときはどの曜日か
    private var customEditor: some View {
        @Bindable var store = store
        let rule = store.content.repeatRule
        let frequency = rule.frequency ?? .weekly
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Stepper(value: $store.content.repeatRule.interval, in: 1...99) {
                Text("\(rule.interval)\(frequency.unitName)ごと")
                    .font(EditorMetrics.inputLabelFont)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            ChipRow(options: RepeatFrequency.allCases,
                    label: \.unitName,
                    isSelected: { $0 == frequency },
                    onTap: { unit in
                        store.content.repeatRule.frequency = unit
                        if unit != .weekly { store.content.repeatRule.weekdays = [] }
                    })
            if frequency == .weekly {
                ChipRow(options: Array(0..<7),
                        label: { Weekday.symbols[$0] },
                        isSelected: { rule.weekdays.contains($0) },
                        onTap: { index in
                            if store.content.repeatRule.weekdays.contains(index) {
                                store.content.repeatRule.weekdays.remove(index)
                            } else {
                                store.content.repeatRule.weekdays.insert(index)
                            }
                        })
            }
        }
    }

    /// 終わりの日（なければ終わりなし）
    private var endEditor: some View {
        let rule = store.content.repeatRule
        let fallback = store.displayedDay ?? CalendarDay(Date())
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Toggle(isOn: Binding(get: { rule.endDay != nil },
                                 set: { store.content.repeatRule.endDay = $0 ? fallback.adding(days: 30) : nil })) {
                Text("終わりの日を決める")
                    .font(EditorMetrics.inputLabelFont)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .tint(Theme.Colors.accent)
            if let endDay = rule.endDay {
                DatePicker("終わりの日",
                           selection: Binding(get: { endDay.date() },
                                              set: { store.content.repeatRule.endDay = CalendarDay($0) }),
                           in: fallback.date()...,
                           displayedComponents: .date)
                    .font(EditorMetrics.inputLabelFont)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            }
        }
    }
}

/// 編集のときだけ、右の入力のいちばん下に独立して出す「予定を削除」。誤操作を防ぐため固定ヘッダーには置かない（§64・Q25）
/// TimyCue の中の予定を Apple カレンダーへ移す（追加仕様書 §1.12）。下の説明文は仮（未確定）
private struct MoveToAppleButton: View {
    let onMove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button(action: onMove) {
                Label("Apple Calendarに保存", systemImage: "calendar.badge.plus")
                    .font(EditorMetrics.chipFont)
            }
            .buttonStyle(.bordered)
            Text("この予定は TimyCue の中だけにあります")
                .font(EditorMetrics.lockNoticeFont)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.l)
    }
}

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
