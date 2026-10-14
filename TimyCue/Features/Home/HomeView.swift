import SwiftUI

/// ホーム（§5・v1.1「ホーム」）。初期版：次の予定 1 件と、使い始めるための 2 つの入り口。
/// 長い初回チュートリアルは作らず、初めから通常のホームを開く（Q42-8）。
/// カレンダー未連携なら「カレンダーを連携、または予定を登録すると…」と［カレンダーを連携］［予定を登録］を出す（Q42-8・Q43）。
/// 予定がないときも［予定を登録］を出す（Q43。通常のホームに常設の＋は置かない：Q21）。
/// 何を出すかは主状態（HomeState）で 1 つだけ決める（追加仕様書 §45）。次の行動時刻（場所ありは出発、場所なしは開始）まで
/// 60 分以内は、残り時間を外周の弧で見せる時計を出す（§6・追加仕様書 §44）。
/// 出発時刻の計算（地図の移動時間）・移動中（§7）などは、第 5 段階の続きで足す。それまでは場所ありの予定も開始で仮に動かす
struct HomeView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(ScheduleEditorStore.self) private var editorStore
    @Environment(CalendarConnection.self) private var connection
    @Environment(DepartureStore.self) private var departures
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// ［予定を登録］で開いた新規の 3 分割画面（初期日付は今日、開始時刻は未設定。Q42-8）
    @State private var newEventDay: CalendarDay?
    /// 予定詳細の吹き出しの「編集」で開く 3 分割画面（Q30）
    @State private var editRequest: EditRequest?
    /// ホームの予定を押したときの予定詳細の吹き出し（Q28(c)）
    @State private var showsDetail = false
    /// 重複候補の一覧（Q50）
    @State private var showsDuplicates = false
    /// 「場所を確認」の候補選択／検索（Q66）を開いている予定
    @State private var placeCheck: CalendarEvent?

    var body: some View {
        // 分が変わった瞬間に更新する（時計の針と残りの分を、iPhone の時計の表示とそろえる）
        TimelineView(.everyMinute) { context in
            let now = context.date
            let events = store.loadedEvents
            // 主状態は 1 つだけ。場所ありの予定は推奨出発時刻、場所なしの予定は開始が基準（追加仕様書 §45）
            let state = HomeState.resolve(events: events, now: now, estimate: departures.estimate(for:))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text(dateTitle(now))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.l)

                    if connection.showsDuplicateNotice {
                        duplicateNotice
                    }

                    if let event = state.event {
                        nextEventSection(state, event: event, now: now)
                    } else {
                        Text(state == .noEvents(onlyAllDayToday: true)
                             ? "今日は時間指定の予定はありません"
                             : "予定はありません")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    if connection.state != .connected {
                        setupCard
                    } else if state.event == nil {
                        registerButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.l)
            }
            // 吹き出しの外を押したら閉じる（Q29）
            .contentShape(Rectangle())
            .onTapGesture { showsDetail = false }
            // 出発時刻を計算し直す：ホームを開いたとき・1 分ごと（5 分たったものだけ）・予定が変わったとき（2026-10-14 決定）
            .onChange(of: now, initial: true) { _, _ in refreshDepartures(now: now) }
            .onChange(of: events) { _, _ in refreshDepartures(now: Date()) }
        }
        // アプリを前面へ戻したら、すぐ計算し直す（追加仕様書 §8.6）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDepartures(now: Date(), force: true) }
        }
        // 移動手段が「自動」の予定を初めて計算するとき、1 回だけ聞く（2026-10-14 決定。文言も決定）
        .confirmationDialog("普段よく使う移動手段は？",
                            isPresented: Binding(get: { departures.asksUsualTransport },
                                                 set: { if !$0 { departures.dismissUsualTransportQuestion() } }),
                            titleVisibility: .visible) {
            ForEach(TransportMode.allCases.filter { $0 != .auto }, id: \.self) { mode in
                Button(mode.displayName) {
                    departures.setUsualTransport(mode)
                    refreshDepartures(now: Date(), force: true)
                }
            }
            Button("あとで", role: .cancel) { departures.dismissUsualTransportQuestion() }
        } message: {
            Text("移動手段を『自動』にした予定で、まだ十分な移動実績がないときの出発時刻計算に使います。あとから設定で変更できます。")
        }
        // 場所を確認：候補の一覧／検索から 1 地点を選び、地点を決めて計算し直す（Q66。2026-10-14 決定）
        .sheet(item: $placeCheck) { event in
            PlaceSearchView(title: "場所を確認", initialQuery: event.locationName ?? "",
                            near: departures.location.location?.coordinate) { candidate in
                departures.confirmPlace(candidate.savedPlace(), for: event.locationName ?? "")
                refreshDepartures(now: Date(), force: true)
            }
        }
        .background(Theme.Colors.homeBackground.ignoresSafeArea())
        .onAppear {
            store.updateToday()
            departures.location.startWatching()
        }
        .onDisappear { departures.location.stopWatching() }
        .sheet(isPresented: $showsDuplicates) {
            NavigationStack {
                DuplicateListView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { showsDuplicates = false }
                        }
                    }
            }
            .environment(connection)
        }
        .fullScreenCover(item: $newEventDay) { day in
            ScheduleEditorView(initialMonth: CalendarMonth(day), onSaved: { _ in store.reload() })
                .environment(editorStore)
                .environment(store)
                .environment(connection)
        }
        .fullScreenCover(item: $editRequest) { request in
            ScheduleEditorView(initialMonth: request.month,
                               onSaved: { _ in store.reload() },
                               onDeleted: { showsDetail = false })
                .environment(editorStore)
                .environment(store)
                .environment(connection)
        }
    }

    // MARK: - 次の予定

    private func nextEventSection(_ state: HomeState, event: CalendarEvent, now: Date) -> some View {
        // 時計は、次の行動時刻まで 60 分以内のときだけ（それより前は静かな表示。追加仕様書 §5.2・§44.12）
        let target = state.clockTarget()
        let face = target.flatMap { HomeClockMath.face(now: now, target: $0.date) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let face, let target {
                clock(face, word: target.word)
            }
            // 出発時刻を計算できないときの原因・目安の知らせ。時計の下（時計がなければ予定の上）に小さく（2026-10-14 決定）
            if let problem = state.problem {
                problemNotice(problem, event: event)
                    .frame(maxWidth: .infinity, alignment: face == nil ? .leading : .center)
            } else if let note = departures.note(for: event) {
                Text(note.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: face == nil ? .leading : .center)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let headline = state.headline {
                    // 出発時刻・出発時刻超過・予定開始の知らせ（spec §6・Q46、追加仕様書 §5.1・§8.7）
                    Text(headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    Text("次の予定")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(EventPalette.color(for: store.color(for: event)))
                        .frame(width: 10, height: 10)
                    Text(event.displayTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                }
                Text(timeText(event, now: now))
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let place = event.locationName, !place.isEmpty {
                    Text(place)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.large).fill(Theme.Colors.surface)
            }
            .contentShape(Rectangle())
            // 押したら、別画面へ移らずホームの上に予定詳細の吹き出しを出す（Q28(c)）
            .onTapGesture { showsDetail.toggle() }

            if showsDetail {
                EventDetailCard(event: event, metadata: store.metadata(for: event.id)) {
                    openEditor(for: event)
                }
                .popoverBubble()
                .transition(.opacity)
            }
        }
    }

    /// 出発時刻を計算できない原因の小さな知らせ。地点が決まっていなければ押して「場所を確認」へ（Q66）。
    /// 普段よく使う移動手段をまだ選んでいなければ、押してもう一度選べる
    @ViewBuilder
    private func problemNotice(_ problem: DepartureProblem, event: CalendarEvent) -> some View {
        Group {
            switch problem {
            case .placeUnconfirmed:
                Button { placeCheck = event } label: {
                    Label(problem.message, systemImage: "mappin.and.ellipse")
                }
            case .transportNotChosen:
                Button { departures.askUsualTransport() } label: {
                    Text(problem.message)
                }
            default:
                Text(problem.message)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.Colors.textSecondary)
    }

    /// 出発時刻を計算し直す（5 分たった・入力が変わった・現在地が大きく動いた予定だけ。force なら全部すぐ）
    private func refreshDepartures(now: Date, force: Bool = false) {
        departures.refresh(events: store.loadedEvents, metadata: store.metadata(for:), now: now, force: force)
    }

    /// 時計と、その下の「16:52 → 17:15 出発予定」。時計で空いた所にカードは足さない（追加仕様書 §44）
    private func clock(_ face: HomeClockMath.Face, word: String) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            HomeClockView(face: face, targetWord: word)
                .containerRelativeFrame(.horizontal) { length, _ in length * HomeMetrics.clockWidthRatio }
                .padding(.vertical, HomeMetrics.clockLabelRoom)
            // 「16:52 → 17:15」と「17:15 出発予定」は、同じ時刻が重なるので 1 行にまとめた（2026-10-14 の指示で整理してよい点。仮）
            Text("\(HomeClockMath.flowText(now: face.now, target: face.target)) \(word)予定")
                .font(HomeMetrics.flowFont)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeText(_ event: CalendarEvent, now: Date) -> String {
        let today = CalendarDay(now)
        let dayText: String
        if event.day == today {
            dayText = "今日"
        } else if event.day == today.adding(days: 1) {
            dayText = "明日"
        } else {
            dayText = "\(event.day.month)/\(event.day.day)（\(event.day.weekdaySymbol())）"
        }
        return "\(dayText) \(CalendarStore.timeText(for: event))"
    }

    // MARK: - 重複候補の案内（Q50）

    /// 新しい重複候補が見つかったら、一度だけ強制しない案内を出す。［確認］で一覧へ。閉じたらもう出さない
    private var duplicateNotice: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text("重複している可能性のある予定が\(connection.duplicateCandidates.count)件あります")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                connection.markDuplicatesNotified()
                showsDuplicates = true
            } label: {
                Text("確認").foregroundStyle(Theme.Colors.onAccent)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.accent)
            Button {
                connection.markDuplicatesNotified()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityLabel("閉じる")
        }
        .padding(Theme.Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.medium).fill(Theme.Colors.surface)
        }
    }

    // MARK: - 使い始めるための入り口（Q42-8・Q43）

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("カレンダーを連携、または予定を登録すると、次の出発時刻を計算できます")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if connection.state == .denied {
                // 一度断られたら、自分からは何度も求めず、iPhone の設定へ案内する（Q38）
                Text("カレンダーへのアクセスは、iPhone の設定から許可してください")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("設定アプリで許可する").foregroundStyle(Theme.Colors.onAccent)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
            } else if connection.state == .notAsked {
                Button {
                    Task { await connection.connect() }
                } label: {
                    Text("カレンダーを連携")
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accentFill)
                .controlSize(.large)
            }
            registerButton
        }
        .padding(Theme.Spacing.l)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.large).fill(Theme.Colors.surface)
        }
    }

    /// ［予定を登録］：3 分割の新規予定画面。初期日付は今日、開始時刻は未設定（Q42-8）。
    /// カレンダーを許可しなくても、TimyCue の中に予定を作れる（Q45）
    private var registerButton: some View {
        Button {
            let today = CalendarDay(Date())
            editorStore.refresh()
            editorStore.startNew(on: today)
            newEventDay = today
        } label: {
            Text("予定を登録")
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.Colors.accent)
        .controlSize(.large)
    }

    private func openEditor(for event: CalendarEvent) {
        editorStore.refresh()
        do {
            try editorStore.startEditing(eventID: event.id)
        } catch {
            store.reload()
            return
        }
        editRequest = EditRequest(id: event.id, month: CalendarMonth(event.day))
    }

    private func dateTitle(_ now: Date) -> String {
        let day = CalendarDay(now)
        return "\(day.month)月\(day.day)日（\(day.weekdaySymbol())）"
    }
}
