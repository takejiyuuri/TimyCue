import SwiftUI

/// 設定タブ（仕様 §81）。今あるのは「カレンダー連携」だけ。ほかのカテゴリ（通知・表示・移動・学習など）は、それぞれの段階で
/// v1.2「設定画面」の順番（通知、表示・拡大表示、カレンダー連携、移動・学習…）に足す。各行の右には今の状態を短く出す
struct SettingsTabView: View {
    @Environment(CalendarConnection.self) private var connection

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CalendarSettingsView()
                } label: {
                    LabeledContent {
                        Text(connection.statusLabel)
                    } label: {
                        Label("カレンダー連携", systemImage: "calendar")
                    }
                }
            }
            .navigationTitle("設定")
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
                if !connection.writableCalendars.isEmpty {
                    Section {
                        Picker("新しい予定の保存先", selection: Binding(
                            get: { connection.preferences.defaultCalendarID ?? "" },
                            set: { connection.setDefaultCalendar($0.isEmpty ? nil : $0) })) {
                            Text("iPhone の既定").tag("")
                            ForEach(connection.writableCalendars) { calendar in
                                CalendarLabel(calendar: calendar).tag(calendar.id)
                            }
                        }
                    } footer: {
                        Text("予定を作るときに、書き込めるカレンダーが 2 つ以上あれば、その予定だけ保存先を変えられます。")
                    }
                }
                // 祝日カレンダー（Q55）：ふだんは自動の判定のまま。必要なときだけ手で直す
                Section {
                    NavigationLink {
                        HolidayCalendarsView()
                    } label: {
                        LabeledContent("祝日カレンダー",
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
                                set: { connection.setShown($0, calendarID: calendar.id) })) {
                                CalendarLabel(calendar: calendar)
                            }
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
                                Text("自動で祝日と判定")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("ON のカレンダーの予定は祝日として扱い、押すと名前と日付だけを出します（編集画面は開きません）。名前に「祝日」「Holiday」が入った読み取りのみのカレンダーは、自動で ON になります。")
            }
        }
        .navigationTitle("祝日カレンダー")
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
