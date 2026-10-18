import SwiftUI

/// 設定タブ（仕様 §81）。今あるのは「カレンダー連携」と「出発・移動」。ほかのカテゴリ（通知・表示・学習など）は、それぞれの段階で
/// v1.2「設定画面」の順番（通知、表示・拡大表示、カレンダー連携、移動・学習…）に足す。各行の右には今の状態を短く出す
struct SettingsTabView: View {
    @Environment(CalendarConnection.self) private var connection
    @Environment(DepartureStore.self) private var departures
    #if TIMYCUE_DEV_TOOLS
    /// 画面写真用に、比べる画面を開いた状態で始める（起動引数 `-TimyCueDevScreen characterSizes`）
    @State private var opensCharacterSizes = UserDefaults.standard.string(forKey: "TimyCueDevScreen") == "characterSizes"
    @State private var opensCharacterDesigns = UserDefaults.standard.string(forKey: "TimyCueDevScreen") == "characterDesigns"
    /// H2 の前提作業の画面（起動引数 `-TimyCueDevScreen characterModes` ／ `clockCheck`）
    @State private var opensCharacterModes = UserDefaults.standard.string(forKey: "TimyCueDevScreen") == "characterModes"
    @State private var opensClockCheck = UserDefaults.standard.string(forKey: "TimyCueDevScreen") == "clockCheck"
    #endif
    #if TIMYCUE_SAVE_FAULTS
    /// S1b の保存の失敗の再現（起動引数 `-TimyCueDevScreen saveFaults`）
    @State private var opensSaveFaults = UserDefaults.standard.string(forKey: "TimyCueDevScreen") == "saveFaults"
    #endif

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CalendarSettingsView()
                } label: {
                    LabeledContent {
                        Text(connection.statusLabel)
                    } label: {
                        Label {
                            Text("カレンダー連携")
                        } icon: {
                            Image(systemName: "calendar").foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }
                // 出発の余裕・自宅・最初の予定の出発地点・普段よく使う移動手段（2026-10-14 決定）
                NavigationLink {
                    DepartureSettingsView()
                } label: {
                    LabeledContent {
                        Text(departures.settings.marginLevel.displayName)
                    } label: {
                        Label {
                            Text("出発・移動")
                        } icon: {
                            Image(systemName: "figure.walk").foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }
                #if TIMYCUE_DEV_TOOLS
                // H1 の比べる画面（2026-10-15 決定 Q80）。検証用のビルドだけで、いちばん下。H1 で大きさが決まったら取り除く
                Section {
                    NavigationLink {
                        CharacterSizeComparisonView()
                    } label: {
                        Label {
                            Text("開発用：キャラクターの大きさ")
                        } icon: {
                            Image(systemName: "figure.stand").foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    // キャラクターの案の比較（2026-10-16 H1 の続き）
                    NavigationLink {
                        CharacterDesignComparisonView()
                    } label: {
                        Label {
                            Text("開発用：キャラクターの案")
                        } icon: {
                            Image(systemName: "person.2").foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    // H2 の前提作業 1：正式キャラクター 3 モードの立ち姿（2026-10-16）
                    NavigationLink {
                        CharacterModeComparisonView()
                    } label: {
                        Label {
                            Text("開発用：キャラクター 3 モード")
                        } icon: {
                            Image(systemName: "hare").foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    // H2 の前提作業 2：時計の表示の時刻を手で進めて確かめる（2026-10-16）
                    NavigationLink {
                        ClockVerificationView()
                    } label: {
                        Label {
                            Text("開発用：時計の確かめ")
                        } icon: {
                            Image(systemName: "clock").foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    // S1b：保存の途中の失敗を再現する（2026-10-18 指示 10）。失敗の再現の印を付けたビルド確認のビルドだけ（TestFlight には入れない）
                    #if TIMYCUE_SAVE_FAULTS
                    NavigationLink {
                        SaveFaultView()
                    } label: {
                        Label {
                            Text("開発用：保存の失敗の再現")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    #endif
                }
                #endif
            }
            .navigationTitle("設定")
            #if TIMYCUE_DEV_TOOLS
            .navigationDestination(isPresented: $opensCharacterSizes) {
                CharacterSizeComparisonView()
            }
            .navigationDestination(isPresented: $opensCharacterDesigns) {
                CharacterDesignComparisonView()
            }
            .navigationDestination(isPresented: $opensCharacterModes) {
                CharacterModeComparisonView()
            }
            .navigationDestination(isPresented: $opensClockCheck) {
                ClockVerificationView()
            }
            #endif
            #if TIMYCUE_SAVE_FAULTS
            .navigationDestination(isPresented: $opensSaveFaults) {
                SaveFaultView()
            }
            #endif
        }
    }
}

/// 設定 ＞ カレンダー連携（Q31〜Q33）：つないでいるかの確認と変更、新しい予定の既定の保存先、読み込むカレンダーの ON/OFF
struct CalendarSettingsView: View {
    @Environment(CalendarConnection.self) private var connection
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("Apple カレンダー") {
                statusRow
            }
            if connection.state == .connected {
                // あとから確かめられるように、重複候補の数を残しておく（Q50）
                Section {
                    NavigationLink {
                        DuplicateListView()
                    } label: {
                        LabeledContent("重複候補",
                                       value: connection.duplicateCandidates.isEmpty ? "なし" : "\(connection.duplicateCandidates.count)件")
                    }
                }
                saveTargetSection
                // 祝日カレンダー（Q55）：ふだんは自動の判定のまま。必要なときだけ手で直す
                Section {
                    NavigationLink {
                        HolidayCalendarsView()
                    } label: {
                        LabeledContent("表示のみのカレンダー（祝日など）",
                                       value: connection.holidayCalendars.isEmpty
                                           ? "なし"
                                           : connection.holidayCalendars.map(\.title).joined(separator: "・"))
                    }
                }
                ForEach(groupedCalendars, id: \.source) { group in
                    Section {
                        ForEach(group.calendars) { calendar in
                            Toggle(isOn: Binding(
                                get: { connection.preferences.isShown(calendar.id) },
                                set: { _ = connection.setShown($0, calendarID: calendar.id) })) {
                                CalendarLabel(calendar: calendar)
                            }
                            .tint(Theme.Colors.accent)
                            // 保存できずに戻したとき、スイッチの見た目も戻す（spec §89.9）
                            .id(connection.settingsRevision)
                        }
                    } header: {
                        Text(group.source.isEmpty ? "カレンダー" : group.source)
                    } footer: {
                        if group.source == groupedCalendars.last?.source {
                            Text("ON のカレンダーの予定を TimyCue に出します。iCloud・Google・Exchange なども、iPhone のカレンダーに入っていれば選べます。")
                        }
                    }
                }
            }
        }
        .navigationTitle("カレンダー連携")
    }

    /// 新しい予定の保存先（spec §89.2・§89.4・§89.11）。選べるのは使えるカレンダーだけ。
    /// 今の保存先が使えないときは、その 1 行を「（使えません：理由）」で出し、注意の行を出し続ける（勝手に切り替えない）
    private var saveTargetSection: some View {
        let rules = connection.saveTargets
        let currentID = connection.preferences.defaultCalendarID
        let current = rules.resolve(eventCalendarID: nil)
        let systemDefault = SaveTargetRules(calendars: rules.calendars, preferences: Self.withoutDefault(rules.preferences),
                                            systemDefaultID: rules.systemDefaultID).resolve(eventCalendarID: nil)
        return Section {
            Picker("新しい予定の保存先", selection: Binding(
                get: { currentID ?? "" },
                set: { connection.setDefaultCalendar($0.isEmpty ? nil : $0) })) {
                if let problem = current.problem {
                    Text(Self.unavailableOptionText(rules: rules, resolution: current, problem: problem))
                        .tag(currentID ?? "")
                }
                if systemDefault.problem == nil {
                    Text(rules.systemDefaultLabel).tag("")
                }
                ForEach(rules.candidates) { calendar in
                    CalendarLabel(calendar: calendar).tag(calendar.id)
                }
            }
            // 保存できずに戻したとき、選んだ表示も戻す（spec §89.9）
            .id(connection.settingsRevision)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let problem = current.problem {
                    Text(Self.unavailableNotice(problem))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Text("表示を OFF にしたカレンダー・表示のみのカレンダー・書き込めないカレンダーには保存しません。予定を作るときに、選べる保存先が 2 つ以上あれば、その予定だけ保存先を変えられます。")
            }
        }
    }

    /// 設定の既定を外した設定（iPhone の既定だけを確かめるため）
    private static func withoutDefault(_ preferences: CalendarPreferences) -> CalendarPreferences {
        var copy = preferences
        copy.defaultCalendarID = nil
        return copy
    }

    /// 今の保存先が使えないときに、選べない 1 行として出す文（例「仕事（使えません：表示 OFF）」）
    private static func unavailableOptionText(rules: SaveTargetRules, resolution: SaveTargetResolution,
                                              problem: SaveTargetProblem) -> String {
        "\(rules.name(for: resolution))（使えません：\(SaveTargetRules.shortReason(problem))）"
    }

    /// 今の保存先が使えないときの注意の行（文言は仮）
    private static func unavailableNotice(_ problem: SaveTargetProblem) -> String {
        switch problem {
        case .hidden(let title): "保存先の「\(title)」は表示を OFF にしています。表示を ON にするか、別の保存先を選んでください。"
        case .displayOnly(let title): "保存先の「\(title)」は表示のみのカレンダーです。別の保存先を選んでください。"
        case .readOnly(let title): "保存先の「\(title)」には予定を書き込めません。別の保存先を選んでください。"
        case .notFound: "保存先にしていたカレンダーが見つかりません。別の保存先を選んでください。"
        case .noSystemDefault: "iPhone の既定のカレンダーが見つかりません。別の保存先を選んでください。"
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch connection.state {
        case .connected:
            Label("つないでいます", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.textPrimary)
        case .notAsked:
            Button("カレンダーを連携") {
                Task { await connection.connect() }
            }
        case .denied:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(connection.authorization == .writeOnly
                     ? "予定の追加だけが許可されています。Apple カレンダーの予定を読み込むには、iPhone の設定でカレンダーを「フルアクセス」にしてください。それまで予定は TimyCue の中に保存します。"
                     : "カレンダーへのアクセスが許可されていません。iPhone の設定から許可してください。それまで予定は TimyCue の中に保存します。")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button("設定アプリで許可する") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        case .restricted:
            Text("この端末では Apple カレンダーを使えません。予定は TimyCue の中に保存しています。")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// アカウント（iCloud・Google など）ごとにまとめる
    private var groupedCalendars: [(source: String, calendars: [CalendarChoice])] {
        let groups = Dictionary(grouping: connection.calendars, by: \.sourceTitle)
        return groups.keys.sorted().map { key in
            (key, groups[key, default: []].sorted { $0.title < $1.title })
        }
    }
}

/// 設定 ＞ カレンダー連携 ＞ 祝日カレンダー（Q55）。祝日カレンダーの予定は、編集画面を出さず、
/// 吹き出しで名前と日付だけを見る。ふだんは自動の判定のままでよく、ここで直した分は自動の判定より優先する。複数選べる
struct HolidayCalendarsView: View {
    @Environment(CalendarConnection.self) private var connection

    var body: some View {
        List {
            Section {
                ForEach(connection.calendars.sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }) { calendar in
                    Toggle(isOn: Binding(
                        get: { connection.isHolidayCalendar(calendar) },
                        set: { connection.setHoliday($0, calendar: calendar) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            CalendarLabel(calendar: calendar)
                            if calendar.isHolidays {
                                Text("自動で ON")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    .tint(Theme.Colors.accent)
                    // 保存できずに戻したとき、スイッチの見た目も戻す（spec §89.9）
                    .id(connection.settingsRevision)
                }
            } footer: {
                // 補足の文は 2026-10-14 決定
                Text("このカレンダーの予定は表示だけで、編集や出発案内の対象にしません。名前に「祝日」「Holiday」が入った読み取りのみのカレンダーは、自動で ON になります。")
            }
        }
        .navigationTitle("表示のみのカレンダー")
    }
}

/// カレンダーの名前と色
private struct CalendarLabel: View {
    let calendar: CalendarChoice

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Circle()
                .fill(EventPalette.color(for: calendar.color))
                .frame(width: 10, height: 10)
            Text(calendar.title)
            if !calendar.isWritable {
                Text("読み取りのみ")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}
