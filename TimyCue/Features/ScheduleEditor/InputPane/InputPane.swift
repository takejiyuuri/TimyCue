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
            // コピーは既存予定の編集中だけ、右の入力の上（固定ヘッダー付近）に出す。削除とは離す（Q25）。
            // コピー中は同じ所に「コピーをやめる」（2026-10-14 実機の指摘。仮）
            if case .edit = store.mode {
                CopyBar(onCopy: onCopy)
            } else if case .copy = store.mode {
                CopyBar(title: "コピーをやめる", systemImage: "xmark", onCopy: { store.cancelCopy() })
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
                                     values: store.valueTexts(for: row),
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
                        MoveToAppleButton(unavailableReason: store.moveToAppleUnavailableReason, onMove: onMoveToApple)
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

/// 右の入力の上に固定する、コピーの操作（Q25）。ボタンの名前は「別の日にコピー」（2026-10-14 ユーザー決定）
private struct CopyBar: View {
    var title = "別の日にコピー"
    var systemImage = "doc.on.doc"
    let onCopy: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onCopy) {
                Label(title, systemImage: systemImage)
                    .font(EditorMetrics.chipFont)
                    .foregroundStyle(Theme.Colors.onAccent)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.accent)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
    }
}

/// 右上の 1 行（左に項目名、右に今の値）。「同じ内容で追加」だけは、足した日を項目名の 1 段下に出す
private struct InputRowView: View {
    let row: InputRow
    /// 今の値。長い順の候補で、1 行に入るいちばん長いものを出す（「同じ内容で追加」の「+3」）
    let values: [String]
    let isExpanded: Bool
    /// 書き込めない Apple カレンダーの予定の、Apple 由来の項目（§1.7）
    let isLocked: Bool
    let color: EventColor?

    var body: some View {
        Group {
            if row == .additionalDays {
                // 名前が長く、横に並べると日付が少ししか入らないので、足した日は名前の 1 段下に 1 行で出す（2026-10-14 実機の指摘）
                VStack(alignment: .leading, spacing: 2) {
                    label
                    value
                }
                .padding(.vertical, 6)
                .frame(minHeight: EditorMetrics.inputRowHeight)
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    label
                        .frame(width: EditorMetrics.inputLabelWidth, alignment: .leading)
                    if let color {
                        Circle()
                            .fill(EventPalette.color(for: color))
                            .frame(width: 12, height: 12)
                    }
                    value
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(EditorMetrics.lockIconFont)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(height: EditorMetrics.inputRowHeight)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 開いている行は、淡いオレンジの塗りと左端のオレンジの線（2026-10-14 決定。緑は意味のある状態色に残す）
        .background(isExpanded ? Theme.Colors.expandedRow : Color.clear)
        .overlay(alignment: .leading) {
            if isExpanded {
                Theme.Colors.expandedRowBar.frame(width: EditorMetrics.expandedRowBarWidth)
            }
        }
        .overlay(alignment: .bottom) {
            Theme.Colors.separator.frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    private var label: some View {
        Text(row.label)
            .font(EditorMetrics.inputLabelFont)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
    }

    private var value: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(values, id: \.self) { text in
                Text(text)
                    .lineLimit(1)
            }
        }
        .font(EditorMetrics.inputValueFont)
        .foregroundStyle(isLocked ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            // 決まった候補を複数オン・オフする。「通知なし」はほかと一緒に選べない。カスタムの分は作らない（追加仕様書 vNext §11）。
            // 場所なしの予定は出発の候補を出さず、開始の候補にする（2026-10-14 決定 C3）
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ChipRow(options: NotificationTiming.presets(hasPlace: store.content.hasPlace),
                        label: \.fullLabel,
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
        case .calendar:
            // その予定だけ保存先を変える（Q32）。選べるのは使えるカレンダーだけ（spec §89.2・§89.3）。ここで選んでも設定の既定は変えない（Q99）
            ChipRow(options: store.saveTargetCandidates,
                    label: \.title,
                    isSelected: { $0.id == store.selectedSaveTargetID },
                    onTap: { store.content.calendarID = $0.id })
        case .additionalDays:
            AdditionalDaysEditor()
        }
    }
}

/// 「同じ内容で追加」を開いたところ（2026-10-14 ユーザー決定）。開いている間だけ、下のカレンダーをなぞって日を足したり外したりできる。
/// 時刻は「一括」（全部の日で同じ）か「個別」。個別のときは、選んだ日を丸いボタンで並べ、押した日の時刻を左上で決める。
/// 時刻を決めた日は丸の枠の色を変える。多ければ横にすべらせる
private struct AdditionalDaysEditor: View {
    @Environment(ScheduleEditorStore.self) private var store
    /// 個別から一括に戻すと時刻が変わる日があるので、確かめている
    @State private var confirmsBatch = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // 文言は仮
            Text("下のカレンダーで日をなぞって選んでください（選んだ日をなぞると外れます）")
                .font(EditorMetrics.lockNoticeFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("時刻", selection: Binding(get: { store.setsTimesIndividually },
                                            set: { individually in
                                                // 日ごとに値が違うときは、そろえる前に一度確かめる（2026-10-14 決定）
                                                if !individually && store.batchChangesSomeDays {
                                                    confirmsBatch = true
                                                } else {
                                                    store.setTimesIndividually(individually)
                                                }
                                            })) {
                Text("一括").tag(false)
                Text("個別").tag(true)
            }
            .pickerStyle(.segmented)
            .confirmationDialog(store.batchConfirmationMessage, isPresented: $confirmsBatch, titleVisibility: .visible) {
                // ボタンの文言は仮
                Button("そろえる") { store.setTimesIndividually(false) }
                Button("やめる", role: .cancel) {}
            }
            if store.setsTimesIndividually {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: EditorMetrics.dayButtonSpacing) {
                        ForEach(store.selectedDays, id: \.self) { day in
                            DayCircleButton(day: day,
                                            isShown: store.displayedDay == day,
                                            hasTime: store.startMinutes[day] != nil) {
                                store.selectDay(day)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// 「個別」のときの日付の丸いボタン。10/12 なら「10/」を小さく、「12」を大きめに。
/// 時刻を決めた日は枠の色を変え、左上に出している日は塗る（色は仮）
private struct DayCircleButton: View {
    let day: CalendarDay
    let isShown: Bool
    let hasTime: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: -2) {
                Text("\(day.month)/")
                    .font(EditorMetrics.dayButtonMonthFont)
                Text("\(day.day)")
                    .font(EditorMetrics.dayButtonDayFont)
            }
            .foregroundStyle(isShown ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .frame(width: EditorMetrics.dayButtonSize, height: EditorMetrics.dayButtonSize)
            .background(Circle().fill(isShown ? Theme.Colors.accentFill : Theme.Colors.surface))
            .overlay {
                Circle().strokeBorder(hasTime ? Theme.Colors.dayButtonTimeSet : Theme.Colors.separator,
                                      lineWidth: EditorMetrics.dayButtonBorderWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.month)月\(day.day)日\(hasTime ? "、時刻あり" : "、時刻なし")")
    }
}

/// 予定名の編集と、過去の同名・似た名前の予定の候補（§47）。
/// 候補を選ぶと予定名だけ入れ、場所・色・到着目標・移動手段は「この予定の設定も使う」を押したときだけ入れる（勝手にすべて確定しない）。
/// 入力中の値を変えたあとに押したら、置き換える前に確かめる（2026-10-14 決定）
private struct TitleEditor: View {
    var focusedRow: FocusState<InputRow?>.Binding
    @Environment(ScheduleEditorStore.self) private var store
    @State private var chosen: TitleSuggestion?
    @State private var confirmsReplacement = false

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
                Button {
                    if store.settingsReplacementNeedsConfirmation(for: chosen) {
                        confirmsReplacement = true
                    } else {
                        useSettings(of: chosen)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("この予定の設定も使う")
                            .font(EditorMetrics.chipFont)
                            .foregroundStyle(Theme.Colors.onAccent)
                        Text("場所・色・到着目標・移動手段")
                            .font(EditorMetrics.lockNoticeFont)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
                // 文言は 2026-10-14 決定
                .confirmationDialog("入力中の設定を、前回の設定に置き換えますか？", isPresented: $confirmsReplacement,
                                    titleVisibility: .visible) {
                    Button("置き換える") { useSettings(of: chosen) }
                    Button("やめる", role: .cancel) {}
                }
            }
        }
    }

    private func useSettings(of suggestion: TitleSuggestion) {
        store.useSettings(of: suggestion)
        chosen = nil
    }
}

/// 場所の編集と候補（§48）：前回の場所・よく使う場所・最近使った場所・場所なし。
/// 現在地と検索は移動時間の計算（第5段階）で足す
private struct LocationEditor: View {
    var focusedRow: FocusState<InputRow?>.Binding
    @Environment(ScheduleEditorStore.self) private var store
    /// 場所の文字と地図の地点の対応（出発時刻の計算に使う）。画面写真などで渡されていなければ、確かめる入口は出さない
    @Environment(DepartureStore.self) private var departures: DepartureStore?
    @State private var checksPlace = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TextField("場所", text: Binding(
                get: { store.content.locationName ?? "" },
                set: { store.setLocationName($0.isEmpty ? nil : $0) }))
                .textFieldStyle(.roundedBorder)
                .focused(focusedRow, equals: .location)
                .submitLabel(.done)
            // 場所の文字を地図の地点に結びつける（追加仕様書 §23.1「編集画面で場所を触ったとき：候補の選択／検索」。
            // 2026-10-14 実機の指摘「場所を入れても『場所を確認してください』がずっと出る」。見た目と文言は仮）
            if let departures, store.content.hasPlace {
                let text = store.content.locationName ?? ""
                let confirmed = departures.placeBook.place(for: text) != nil
                Button {
                    checksPlace = true
                } label: {
                    Label(confirmed ? "地図の地点：確認済み（変える）" : "地図で場所を確かめる",
                          systemImage: confirmed ? "checkmark.circle" : "mappin.and.ellipse")
                        .font(EditorMetrics.chipFont)
                        .foregroundStyle(Theme.Colors.actionText)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $checksPlace) {
                    PlaceSearchView(title: "場所を確認", initialQuery: text,
                                    near: departures.location.location?.coordinate) { candidate in
                        departures.confirmPlace(candidate.savedPlace(), for: text)
                    }
                }
                if !confirmed {
                    Text("地図の地点を決めると、出発時刻を計算できます")
                        .font(EditorMetrics.lockNoticeFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
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
            Button { store.choosePlace(nil) } label: {
                Text("場所なし").foregroundStyle(Theme.Colors.onAccent)
            }
            .font(EditorMetrics.chipFont)
            .buttonStyle(.bordered)
            .tint(Theme.Colors.accent)
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
                        .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Theme.Colors.accentFill : Theme.Colors.background))
                        .overlay { Capsule().strokeBorder(Theme.Colors.separator, lineWidth: selected ? 0 : 1) }
                        .contentShape(Capsule())
                        .onTapGesture { onTap(option) }
                }
            }
        }
    }
}

/// 編集のときだけ、右の入力のいちばん下に独立して出す「予定を削除」。誤操作を防ぐため固定ヘッダーには置かない（§64・Q25）
/// TimyCue の中の予定を Apple カレンダーへ移す（追加仕様書 §1.12）。下の説明文は仮（未確定）
private struct MoveToAppleButton: View {
    /// 移す先が使えないときの理由。あればボタンを押せなくして出す（spec §89.5）
    let unavailableReason: String?
    let onMove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button(action: onMove) {
                Label("Apple Calendarに保存", systemImage: "calendar.badge.plus")
                    .font(EditorMetrics.chipFont)
                    .foregroundStyle(Theme.Colors.onAccent)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.accent)
            .disabled(unavailableReason != nil)
            Text("この予定は TimyCue の中だけにあります")
                .font(EditorMetrics.lockNoticeFont)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let unavailableReason {
                Text(unavailableReason)
                    .font(EditorMetrics.lockNoticeFont)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
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
