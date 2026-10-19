import Combine
import SwiftUI
import UIKit

/// ホーム（H2 の新しい Home。spec §88・§5・§13）。「今、何時に出ればいい？」を一目で分かるようにする（§87）。
/// 縦にスクロールしない 1 画面：上の左に今日の日付、右に電池の残量（Home だけ iOS のステータスバーを出さない。RootTabView）。
/// その下の演出帯の右に時計（画面の幅の 40％。数える先の 60 分前から。Q94 で確かめた時計をそのまま使う）、左に終日の予定・
/// 「終わった予定 ○件」・知らせ、いちばん下（「いま」の直上）に人型（36pt・3 モードの止まった姿）。その下に「いま」と今日のタイムライン。
/// 何を出すかは、実際の予定・今の時刻・出発時刻の見込みから HomeScreenModel で決める（主状態は今の HomeState のまま。追加仕様書 §45）。
/// 予定が変わった（追加・編集・保存先の変更・Apple 連携の ON/OFF で CalendarStore が読み直した）・分が変わった・日付が変わった・
/// 前面に戻ったときに描き直す。長い初回チュートリアルは作らず、初めから通常のホームを開く（Q42-8）
struct HomeView: View {
    /// 「ほか○件」：カレンダーのその日の表示を開く（Q84。RootTabView がカレンダーのタブへ移す）
    private let openDayInCalendar: (CalendarDay) -> Void

    @Environment(CalendarStore.self) private var store
    @Environment(ScheduleEditorStore.self) private var editorStore
    @Environment(CalendarConnection.self) private var connection
    @Environment(DepartureStore.self) private var departures
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var home = HomeStore()
    @State private var battery = HomeBattery()
    /// 文字の大きさの設定に合わせて、タイムラインの行の高さを広げる倍率（100 が標準）
    @ScaledMetric(relativeTo: .subheadline) private var scaledHundred: CGFloat = 100

    init(openDayInCalendar: @escaping (CalendarDay) -> Void = { _ in }) {
        self.openDayInCalendar = openDayInCalendar
    }

    var body: some View {
        // 分が変わった瞬間に更新する（時計の針と残りの分を、iPhone の時計の表示とそろえる。今の Home と同じ仕組み）
        TimelineView(.everyMinute) { context in
            let now = Self.displayNow(context.date)
            let events = store.guidanceEvents
            let today = CalendarDay(now)
            let model = HomeScreenModel.make(events: events,
                                             displayOnlyEvents: store.events(on: today).filter { store.isViewOnly($0) },
                                             now: now,
                                             estimate: { departureEstimate(for: $0) })
            screen(model)
                // 出発時刻を計算し直す：ホームを開いたとき・1 分ごと（5 分たったものだけ）・予定が変わったとき（2026-10-14 決定）
                .onChange(of: now, initial: true) { _, _ in refreshDepartures(now: now) }
                .onChange(of: events) { _, newEvents in
                    refreshDepartures(now: Date())
                    // 消えた予定（Apple 連携を OFF にした・保存先を変えた・削除した）の吹き出しは閉じる
                    home.reconcile(eventIDs: Set(newEvents.map(\.id)))
                }
        }
        .background(Theme.Colors.homeBackground.ignoresSafeArea())
        // アプリを前面へ戻したら、すぐ計算し直す（追加仕様書 §8.6）。日付の「今日」も直す（RootTabView でも直している）
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.updateToday()
            refreshDepartures(now: Date(), force: true)
            battery.refresh()
        }
        // 電池の残量・充電の状態が変わったら読み直す
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification).receive(on: DispatchQueue.main)) { _ in
            battery.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification).receive(on: DispatchQueue.main)) { _ in
            battery.refresh()
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
        .sheet(item: $home.placeCheck) { event in
            PlaceSearchView(title: "場所を確認", initialQuery: event.locationName ?? "",
                            near: departures.location.location?.coordinate) { candidate in
                departures.confirmPlace(candidate.savedPlace(), for: event.locationName ?? "")
                refreshDepartures(now: Date(), force: true)
            }
        }
        .onAppear {
            store.updateToday()
            departures.location.startWatching()
            battery.start()
        }
        .onDisappear {
            departures.location.stopWatching()
            battery.stop()
        }
        .task {
            #if DEBUG
            // 起動引数 -TimyCueTapNewEvent YES：［予定を登録］と同じ処理で新規を開く（2026-10-19 TestFlight 1.0 (30) のクラッシュの再現と確かめ。
            // ［予定を登録］が出ていない状態でも開く）
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "TimyCueTapNewEvent"), (defaults.string(forKey: "TimyCueTab") ?? "home") == "home", home.newEventDay == nil {
                try? await Task.sleep(for: .seconds(1))
                openNewEvent()
            }
            #endif
        }
        .sheet(isPresented: $home.showsDuplicates) {
            NavigationStack {
                DuplicateListView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { home.showsDuplicates = false }
                        }
                    }
            }
            // シートの上では元の画面のアラートが出ないので、ここにも付ける（「両方残す」を保存できなかったとき。spec §89.9）
            .settingsFailureAlert()
            .environment(connection)
        }
        .fullScreenCover(item: $home.newEventDay) { day in
            ScheduleEditorView(initialMonth: CalendarMonth(day), onSaved: { _ in store.reload() })
                .environment(editorStore)
                .environment(store)
                .environment(connection)
        }
        .fullScreenCover(item: $home.editRequest) { request in
            ScheduleEditorView(initialMonth: request.month,
                               onSaved: { _ in store.reload() },
                               onDeleted: { home.closeBubble() })
                .environment(editorStore)
                .environment(store)
                .environment(connection)
        }
    }

    // MARK: - 画面

    /// 上から：日付と電池 → 演出帯（時計・人型）→（過ぎた出発の点）→ いま → タイムライン → 下の案内（重複候補・連携のカード）
    private func screen(_ model: HomeScreenModel) -> some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                HomeTopBar(dateTitle: model.dateTitle, battery: battery.reading)
                    .padding(.top, HomeLayoutMetrics.topPadding)
                HomeStageView(timeline: model.timeline,
                              clock: model.clock,
                              headline: model.headline,
                              note: note(for: model),
                              mode: model.mode,
                              screenWidth: proxy.size.width,
                              onTapFinished: { home.tapFinished() },
                              onTapProblem: { problem in tapProblem(problem, event: model.state.event) })
                HomeRailSection(timeline: model.timeline,
                                scale: typeScale,
                                animates: !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled,
                                showsRegister: !connection.showsSetupCard && model.state.event == nil,
                                color: { store.color(for: $0) },
                                transport: { transportName(for: $0) },
                                onTapRow: { item in
                                    guard let event = item.event else { return }
                                    home.tapRow(eventID: event.id, anchorID: item.id)
                                },
                                onTapPastDeparture: { past in
                                    home.tapRow(eventID: past.event.id, anchorID: HomePastDepartureRow.anchorID)
                                },
                                onMore: { openDayInCalendar(model.timeline.today) },
                                onRegister: { openNewEvent() })
                    .padding(.top, HomeLayoutMetrics.figureBottomGap)
                    .frame(maxHeight: .infinity, alignment: .top)
                bottomCards
            }
            .padding(.horizontal, HomeLayoutMetrics.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .overlayPreferenceValue(HomeBubbleAnchorKey.self) { anchors in
                HomeBubbleLayer(anchors: anchors, home: home, finishedEvents: model.timeline.finishedEvents) { event in
                    openEditor(for: event)
                }
            }
        }
    }

    /// 下の案内：重複候補（Q50）と、まだ連携していないときの連携のカード（Q42-8・Q115）
    @ViewBuilder
    private var bottomCards: some View {
        if connection.showsDuplicateNotice {
            HomeDuplicateNotice(count: connection.duplicateCandidates.count,
                                onConfirm: {
                                    connection.markDuplicatesNotified()
                                    home.showsDuplicates = true
                                },
                                onClose: { connection.markDuplicatesNotified() })
                .padding(.bottom, Theme.Spacing.s)
        }
        // まだ連携していない・許可がないときだけ（Q42-8・Q115）。利用者が連携をわざと OFF にしたとき・確かめられないときは出さない（Q102）
        if connection.showsSetupCard {
            HomeSetupCard(state: connection.state,
                          onConnect: { Task { await connection.connect() } },
                          onOpenSettings: {
                              if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                          },
                          onRegister: { openNewEvent() })
                .padding(.bottom, Theme.Spacing.s)
        }
    }

    // MARK: - 計算

    /// 文字の大きさの設定に合わせた倍率（Home は文字を xxxLarge までにしている。RootTabView）
    private var typeScale: CGFloat {
        let range = HomeLayoutMetrics.typeScaleRange
        return min(max(scaledHundred / 100, range.lowerBound), range.upperBound)
    }

    /// 時計の下などに小さく出す知らせ：出発時刻を計算できない原因、または出発時刻に添える目安・古い値の知らせ（2026-10-14 決定）
    private func note(for model: HomeScreenModel) -> HomeStageNote? {
        if let problem = model.problem { return .problem(problem) }
        if let event = model.state.event, let note = departures.note(for: event) { return .note(note.message) }
        return nil
    }

    private func tapProblem(_ problem: DepartureProblem, event: CalendarEvent?) {
        switch problem {
        case .placeUnconfirmed:
            home.placeCheck = event
        case .transportNotChosen:
            departures.askUsualTransport()
        default:
            break
        }
    }

    /// 出発の点に出す移動手段（設定どおり。「自動」は「自動」のまま：Q81・Q77-5）
    private func transportName(for event: CalendarEvent) -> String {
        (store.metadata(for: event.id)?.transport ?? .auto).displayName
    }

    /// その予定の推奨出発時刻の見込み
    private func departureEstimate(for event: CalendarEvent) -> DepartureEstimate {
        #if DEBUG
        if let scenario = HomeDebugScenario.current { return scenario.estimate(for: event) }
        #endif
        return departures.estimate(for: event)
    }

    /// 画面に使う今の時刻（DEBUG の画面写真の見本では、決めた時刻）
    private static func displayNow(_ date: Date) -> Date {
        #if DEBUG
        if let scenario = HomeDebugScenario.current { return scenario.now(on: CalendarDay(date)) }
        #endif
        return date
    }

    /// 出発時刻を計算し直す（5 分たった・入力が変わった・現在地が大きく動いた予定だけ。force なら全部すぐ）
    private func refreshDepartures(now: Date, force: Bool = false) {
        departures.refresh(events: store.guidanceEvents, metadata: { store.metadata(for: $0) }, now: now, force: force)
    }

    // MARK: - 予定の作成・編集

    /// ［予定を登録］の新規：初期日付は今日、開始時刻は未設定（Q42-8）
    private func openNewEvent() {
        let today = CalendarDay(Date())
        editorStore.refresh()
        editorStore.startNew(on: today)
        home.newEventDay = today
    }

    /// 予定詳細の吹き出しの「編集」（Q30）。閉じたら Home に戻り、吹き出しもそのまま出す
    private func openEditor(for event: CalendarEvent) {
        editorStore.refresh()
        do {
            try editorStore.startEditing(eventID: event.id)
        } catch {
            store.reload()
            return
        }
        home.editRequest = EditRequest(id: event.id, month: CalendarMonth(event.day))
    }
}
