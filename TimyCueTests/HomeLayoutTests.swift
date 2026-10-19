import XCTest
@testable import TimyCue

/// H2 の新しい Home の配置（spec §88.2・§88.3・Q84）：縦にスクロールしない。使える高さ・予定の数・時刻の間隔から、
/// 密度・出す行・行の間を決め、入りきらない予定は「ほか○件」。時計 40％・人型 36pt・外周の文字・甲羅が重ならないこと
final class HomeLayoutTests: XCTestCase {
    private let calendar = Calendar.timyCue
    private let day = CalendarDay(year: 2026, month: 10, day: 19)

    private func at(_ minute: Int) -> Date {
        day.date(atMinute: minute, calendar: calendar)
    }

    private func estimate(_ event: CalendarEvent) -> DepartureEstimate {
        guard HomeSchedule.hasPlace(event) else { return .notNeeded }
        return .available(HomeSchedule.startDate(of: event, calendar: calendar).addingTimeInterval(-15 * 60))
    }

    private func timeline(_ events: [CalendarEvent], now minute: Int = 9 * 60) -> HomeTimeline {
        HomeScreenModel.make(events: events, now: at(minute), calendar: calendar, estimate: { estimate($0) }).timeline
    }

    /// 10:00 から gap 分おきに count 件。最初の予定（主状態）だけ場所あり（出発の点つき）
    private func items(events count: Int, gap: Int = 60) -> [HomeTimeline.Item] {
        let events = (0..<count).map { index in
            CalendarEvent(day: day, startMinute: 10 * 60 + index * gap, title: "予定\(index + 1)",
                          locationName: index == 0 ? "広島駅" : nil)
        }
        return timeline(events).items
    }

    private func total(_ items: [HomeTimeline.Item], _ density: HomeDensity, scale: CGFloat = 1) -> CGFloat {
        items.reduce(CGFloat(0)) { $0 + HomeTimelineLayout.rowHeight($1, density: density, scale: scale) }
    }

    // MARK: - 密度（予定 0 件・1〜2 件・3〜5 件・6 件以上）

    func testDensityFollowsTheNumberOfEventsWhenThereIsRoom() {
        let table: [(count: Int, density: HomeDensity)] = [(1, .spacious), (2, .spacious), (3, .regular), (5, .regular),
                                                          (6, .compact), (10, .compact)]
        for row in table {
            let plan = HomeTimelineLayout.plan(items: items(events: row.count), availableHeight: 2000)
            XCTAssertEqual(plan.density, row.density, "予定 \(row.count) 件")
            XCTAssertEqual(plan.hiddenEventCount, 0)
            XCTAssertFalse(plan.showsMore)
        }
    }

    func testDensityTightensWhenTheScreenIsShort() {
        let four = items(events: 4)
        let regular = total(four, .regular)
        let compact = total(four, .compact)
        let tight = total(four, .tight)
        XCTAssertGreaterThan(regular, compact)
        XCTAssertGreaterThan(compact, tight)
        XCTAssertEqual(HomeTimelineLayout.plan(items: four, availableHeight: regular).density, .regular)
        let short = HomeTimelineLayout.plan(items: four, availableHeight: regular - 1)
        XCTAssertEqual(short.density, .compact, "予定の数だけで決めず、収まらなければ詰める")
        XCTAssertEqual(short.hiddenEventCount, 0)
        XCTAssertLessThanOrEqual(short.height, regular - 1)
        XCTAssertEqual(HomeTimelineLayout.plan(items: four, availableHeight: tight).density, .tight)
    }

    func testEmptyTimelineHasOnlyTheMessage() {
        let plan = HomeTimelineLayout.plan(items: timeline([]).items, availableHeight: 300)
        XCTAssertEqual(plan.rows.count, 1)
        XCTAssertEqual(plan.rows.first?.item.kind, .message(HomeTimeline.noEventsText))
        XCTAssertEqual(plan.hiddenEventCount, 0)
    }

    // MARK: - 入りきらないとき（Q84）

    func testOverflowKeepsTheMainEventAndItsDepartureAndCountsHiddenEvents() throws {
        let many = items(events: 12)
        let available: CGFloat = 200
        let plan = HomeTimelineLayout.plan(items: many, availableHeight: available)
        XCTAssertEqual(plan.density, .tight)
        XCTAssertTrue(plan.showsMore)
        let mainID = try XCTUnwrap(many.first { $0.isMain && $0.isEventRow }?.event?.id)
        XCTAssertTrue(plan.shownEventIDs.contains(mainID), "主状態の予定はいつも出す")
        XCTAssertTrue(plan.rows.contains { $0.item.isMain && $0.item.isDeparture }, "主状態の予定の出発の点も出す")
        XCTAssertEqual(plan.hiddenEventCount, 12 - plan.shownEventIDs.count, "「ほか○件」は出していない予定の数（出発の点は数えない）")
        XCTAssertLessThanOrEqual(plan.height, available, "画面の中に収める（スクロールさせない）")
        let shown = plan.rows.compactMap { $0.item.isEventRow ? $0.item.event?.title : nil }
        XCTAssertEqual(shown, (1...shown.count).map { "予定\($0)" }, "時刻の順に前から出し、間を飛ばさない")
        XCTAssertGreaterThan(shown.count, 1)
    }

    func testTheMainEventIsShownEvenAfterInProgressEvents() throws {
        var events = (0..<3).map { index in
            CalendarEvent(day: day, startMinute: 13 * 60 + index * 10, durationMinutes: 120, title: "進行中\(index + 1)")
        }
        events.append(CalendarEvent(day: day, startMinute: 16 * 60, title: "A社", locationName: "広島駅"))
        events += (0..<5).map { CalendarEvent(day: day, startMinute: 17 * 60 + $0 * 30, title: "夕方\($0 + 1)") }
        let rows = timeline(events, now: 14 * 60).items
        let tight = HomeLayoutMetrics.rows(.tight)
        let available = tight.departureRow + tight.mainRow + tight.eventRow + tight.moreRow
        let plan = HomeTimelineLayout.plan(items: rows, availableHeight: available)
        let mainID = try XCTUnwrap(rows.first { $0.isMain && $0.isEventRow }?.event?.id)
        XCTAssertTrue(plan.shownEventIDs.contains(mainID), "進行中の予定が先に並んでいても、主状態の予定は出す")
        XCTAssertEqual(plan.shownEventIDs.count, 2)
        XCTAssertEqual(plan.hiddenEventCount, 7)
        XCTAssertLessThanOrEqual(plan.height, available + 0.01)
    }

    func testASeparatorIsDroppedWhenItsDayIsHidden() {
        let today = CalendarEvent(day: day, startMinute: 19 * 60, title: "夕食")
        let tomorrow = CalendarEvent(day: day.adding(days: 1), startMinute: 30, title: "早朝", locationName: "空港")
        let rows = HomeScreenModel.make(events: [today, tomorrow], now: at(17 * 60), calendar: calendar, estimate: { event in
            event.id == tomorrow.id ? .available(self.at(23 * 60 + 30)) : .notNeeded
        }).timeline.items
        XCTAssertTrue(rows.contains { if case .daySeparator = $0.kind { return true } else { return false } })
        let filtered = HomeTimelineLayout.filtered(rows, showing: [today.id])
        XCTAssertEqual(filtered.map(\.id), ["start-\(today.id.uuidString)"], "その日の行を出さないなら区切りも出さない")
    }

    // MARK: - 行の間（予定が少ない日は広く。時刻の間が長いところほど少し広く）

    func testExtraSpacingGrowsWithTheTimeGap() {
        let visit = CalendarEvent(day: day, startMinute: 10 * 60, title: "A社", locationName: "広島駅")
        let call = CalendarEvent(day: day, startMinute: 13 * 60, title: "電話")
        let rows = timeline([visit, call]).items
        XCTAssertEqual(rows.count, 3, "出発 9:45・開始 10:00・開始 13:00")
        let plan = HomeTimelineLayout.plan(items: rows, availableHeight: 1000)
        XCTAssertEqual(plan.density, .spacious)
        let maxExtra = HomeLayoutMetrics.rows(.spacious).maxExtraGap
        XCTAssertEqual(plan.rows[1].spacingAfter, maxExtra, accuracy: 0.01, "いちばん長い間（3 時間）は上限まで")
        XCTAssertLessThan(plan.rows[0].spacingAfter, plan.rows[1].spacingAfter, "15 分の間は少しだけ")
        XCTAssertGreaterThan(plan.rows[0].spacingAfter, 0)
        XCTAssertEqual(plan.rows[2].spacingAfter, 0)
        XCTAssertLessThanOrEqual(plan.height, 1000)

        let base = total(rows, .spacious)
        let snug = HomeTimelineLayout.plan(items: rows, availableHeight: base + 10)
        XCTAssertEqual(snug.height, base + 10, accuracy: 0.01, "余った分だけ広げ、はみ出さない")
        XCTAssertEqual(HomeTimelineLayout.plan(items: rows, availableHeight: base).height, base, accuracy: 0.01)
    }

    // MARK: - 文字の大きさの設定

    func testLargerTextEnlargesRowsAndTightensWhenNeeded() {
        let two = items(events: 2)
        let normal = HomeTimelineLayout.plan(items: two, availableHeight: 2000, scale: 1)
        let large = HomeTimelineLayout.plan(items: two, availableHeight: 2000, scale: 1.4)
        XCTAssertEqual(large.rows[0].height, normal.rows[0].height * 1.4, accuracy: 0.01)
        let need = total(two, .spacious)
        let squeezed = HomeTimelineLayout.plan(items: two, availableHeight: need, scale: 1.4)
        XCTAssertGreaterThan(squeezed.density, .spacious, "文字を大きくして入らなくなったら詰める")
        XCTAssertEqual(squeezed.hiddenEventCount, 0)
        XCTAssertLessThanOrEqual(squeezed.height, need)
    }

    // MARK: - 縦の線（Q81・Q83）

    func testRailLinesConnectAllDotsAndEachDepartureToItsStart() throws {
        let visitID = UUID()
        let callID = UUID()
        let dots: [HomeRailDot: CGRect] = [
            HomeRailDot(rowID: "past", role: .pastDeparture, eventID: visitID, color: .orange): CGRect(x: 20, y: 0, width: 10, height: 10),
            HomeRailDot(rowID: "now", role: .now, eventID: nil, color: nil): CGRect(x: 18, y: 30, width: 14, height: 14),
            HomeRailDot(rowID: "start-visit", role: .start, eventID: visitID, color: .orange): CGRect(x: 20, y: 80, width: 10, height: 10),
            HomeRailDot(rowID: "start-call", role: .start, eventID: callID, color: .mint): CGRect(x: 20, y: 140, width: 10, height: 10),
        ]
        let base = try XCTUnwrap(HomeRailGeometry.base(dots))
        XCTAssertEqual(base.top, CGPoint(x: 25, y: 5))
        XCTAssertEqual(base.bottom, CGPoint(x: 25, y: 145))
        let pairs = HomeRailGeometry.pairs(dots)
        XCTAssertEqual(pairs.count, 1, "出発の点がない予定（場所なし）は結ばない")
        XCTAssertEqual(pairs.first?.top, CGPoint(x: 25, y: 5), "過ぎた出発の点から「いま」をはさんで予定開始の点まで（Q83）")
        XCTAssertEqual(pairs.first?.bottom, CGPoint(x: 25, y: 85))
        XCTAssertEqual(pairs.first?.color, .orange)
        XCTAssertNil(HomeRailGeometry.base([HomeRailDot(rowID: "now", role: .now, eventID: nil, color: nil): .zero]),
                     "点が「いま」だけなら線を引かない")
    }

    // MARK: - 演出帯（時計 40％・人型 36pt）

    func testTheDecidedSizesAreKept() {
        XCTAssertEqual(HomeMetrics.clockWidthRatio, 0.40, accuracy: 0.0001, "時計の直径は画面の幅の約 40％（§88.3）")
        XCTAssertEqual(HomeLayoutMetrics.figureHeight, 36, "人型の本体は 36pt（§88.4）")
        XCTAssertEqual(HomeMetrics.centerPlateRatio, 0.34, accuracy: 0.0001, "中央のプレートは直径の約 34％（Q94）")
        let style = HomeClockStyle.scaled(diameter: HomeStageLayout.clockDiameter(screenWidth: 393))
        XCTAssertEqual(style.centerNumberSize, 27, accuracy: 0.5, "中央の数字は約 27pt（外径の 17％）")
        XCTAssertGreaterThanOrEqual(style.centerCaptionSize, HomeMetrics.minimumClockText, "「出発まで」「開始まで」は 11pt 以上")
    }

    func testTheFigureAndTheClockDoNotOverlapOnAnyWidth() {
        for width: CGFloat in [375, 390, 393, 402, 414, 428, 430, 440] {
            for mode in CharacterMode.allCases {
                let layout = CharacterLayout(height: HomeLayoutMetrics.figureHeight, mode: mode)
                XCTAssertLessThan(HomeStageLayout.figureRightEdge(layout), HomeStageLayout.clockLeftEdge(screenWidth: width),
                                  "幅 \(width)・\(mode.title)：人型と時計（外周の文字を含む）が横に重ならない")
                XCTAssertGreaterThanOrEqual(HomeStageLayout.figureLeftEdge(layout), 0, "甲羅を含めて画面の外へ出ない")
            }
            XCTAssertLessThanOrEqual(HomeStageLayout.clockRightEdge(screenWidth: width), width, "外周の「いま」「出発」が画面の外へ出ない")
            XCTAssertEqual(HomeStageLayout.clockDiameter(screenWidth: width), (width * 0.40).rounded())
        }
    }
}
