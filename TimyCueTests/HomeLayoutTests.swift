import UIKit
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

    // MARK: - 右上の電池の位置（2026-10-19 の上の段の最終調整）
    // 前（e45cf2d）の「日付の行から決まった量（28pt）だけ上げる」形のテスト 3 件（上へ 25〜30pt・SE で上げる量を抑える・
    // 中央の切り欠きより右）は、画面の形（Dynamic Island・ノッチ・なし）と Safe Area の上の高さから置き場所を決める形に変えたので、
    // 下のテスト（帯の中心・切り欠きと角と上の端からの余白・切り欠きのない機種）に置き換えた

    /// テストで使う機種の画面の上の形（pt。実際の機種の値の見込み。置き方の計算の見込みの値とは別に持ち、見込みが実際より広いかも確かめる）
    private struct PhoneTop {
        let name: String
        let width: CGFloat
        let safeTop: CGFloat
        /// ノッチ・Dynamic Island の枠（画面の座標）。切り欠きのない機種は nil
        let cutout: CGRect?
        /// 画面の角の丸みの半径（切り欠きのない機種は 0）
        let cornerRadius: CGFloat
    }

    /// 画面の幅の中央にある切り欠き
    private static func centeredCutout(width: CGFloat, screen: CGFloat, top: CGFloat = 0, height: CGFloat) -> CGRect {
        CGRect(x: (screen - width) / 2, y: top, width: width, height: height)
    }

    private static let dynamicIslandPhones: [PhoneTop] = [
        PhoneTop(name: "iPhone 14 Pro・15・15 Pro・16", width: 393, safeTop: 59,
                 cutout: centeredCutout(width: 126, screen: 393, top: 11, height: 37.33), cornerRadius: 55),
        PhoneTop(name: "iPhone 14 Pro Max・15 Plus・15 Pro Max・16 Plus", width: 430, safeTop: 59,
                 cutout: centeredCutout(width: 126, screen: 430, top: 11, height: 37.33), cornerRadius: 55),
        PhoneTop(name: "iPhone 16 Pro", width: 402, safeTop: 62,
                 cutout: centeredCutout(width: 126, screen: 402, top: 14, height: 37.33), cornerRadius: 62),
        PhoneTop(name: "iPhone 16 Pro Max", width: 440, safeTop: 62,
                 cutout: centeredCutout(width: 126, screen: 440, top: 14, height: 37.33), cornerRadius: 62),
        // 表示の拡大（14 Pro Max を幅 375pt で。Safe Area・切り欠き・角は 375/430 倍）
        PhoneTop(name: "iPhone 14 Pro Max（拡大表示）", width: 375, safeTop: 51.4,
                 cutout: centeredCutout(width: 110, screen: 375, top: 9.6, height: 32.6), cornerRadius: 48),
    ]

    private static let notchPhones: [PhoneTop] = [
        PhoneTop(name: "iPhone XS・11 Pro", width: 375, safeTop: 44,
                 cutout: centeredCutout(width: 209, screen: 375, height: 30), cornerRadius: 39),
        PhoneTop(name: "iPhone XS Max・11 Pro Max", width: 414, safeTop: 44,
                 cutout: centeredCutout(width: 209, screen: 414, height: 30), cornerRadius: 39),
        PhoneTop(name: "iPhone XR・11", width: 414, safeTop: 48,
                 cutout: centeredCutout(width: 223, screen: 414, height: 32), cornerRadius: 41.5),
        PhoneTop(name: "iPhone 12・12 Pro", width: 390, safeTop: 47,
                 cutout: centeredCutout(width: 210, screen: 390, height: 32), cornerRadius: 47.33),
        PhoneTop(name: "iPhone 12 Pro Max", width: 428, safeTop: 47,
                 cutout: centeredCutout(width: 210, screen: 428, height: 32), cornerRadius: 53.33),
        PhoneTop(name: "iPhone 12 mini", width: 375, safeTop: 50,
                 cutout: centeredCutout(width: 226, screen: 375, height: 35), cornerRadius: 44),
        PhoneTop(name: "iPhone 13・13 Pro・14・16e", width: 390, safeTop: 47,
                 cutout: centeredCutout(width: 168, screen: 390, height: 34), cornerRadius: 47.33),
        PhoneTop(name: "iPhone 13 Pro Max・14 Plus", width: 428, safeTop: 47,
                 cutout: centeredCutout(width: 168, screen: 428, height: 34), cornerRadius: 53.33),
        PhoneTop(name: "iPhone 13 mini", width: 375, safeTop: 50,
                 cutout: centeredCutout(width: 182, screen: 375, height: 36), cornerRadius: 44),
        // 表示の拡大（12 mini を幅 320pt で）
        PhoneTop(name: "iPhone 12 mini（拡大表示）", width: 320, safeTop: 42.7,
                 cutout: centeredCutout(width: 193, screen: 320, height: 30), cornerRadius: 37.5),
        // Dynamic Island の機種を表示の拡大にすると Safe Area の上が 51pt より小さくなり、ノッチとして扱う（14 Pro を幅 320pt で）
        PhoneTop(name: "iPhone 14 Pro（拡大表示）", width: 320, safeTop: 48,
                 cutout: centeredCutout(width: 102.6, screen: 320, top: 9, height: 30.4), cornerRadius: 44.8),
    ]

    private static let flatPhones: [PhoneTop] = [
        PhoneTop(name: "iPhone SE（ステータスバーを隠す）", width: 375, safeTop: 0, cutout: nil, cornerRadius: 0),
        PhoneTop(name: "iPhone SE（ステータスバーあり）", width: 375, safeTop: 20, cutout: nil, cornerRadius: 0),
        PhoneTop(name: "iPhone SE（拡大表示）", width: 320, safeTop: 0, cutout: nil, cornerRadius: 0),
    ]

    /// ステータスバーを隠した Home での Safe Area の上の高さの取り方：Dynamic Island・ノッチの機種はセンサーの張り出しの分が残り、
    /// SE 系は 0 になりうる。画面全体の電池の層で測った値と窓（UIKit）の値の大きいほうを使い、どちらかが 0 でも取り違えない。
    /// 2026-10-19 ビルド確認 #77 の直しで、画面の中の位置（global の座標）を使うのをやめた（引数から外した）
    func testTopInsetKeepsTheSensorHousingWithoutTheStatusBar() {
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: 59, window: 59), 59, "Dynamic Island の機種")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: 62, window: 62), 62, "Dynamic Island の機種（16 Pro・Pro Max）")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: 47, window: 47), 47, "ノッチの機種")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: 0, window: 62), 62, "SwiftUI の値が 0 で返っても、窓の値で補う")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: 59, window: 0), 59, "窓の値が 0 で返っても取り違えない")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: 59, window: nil), 59, "窓の値が取れないとき")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: 0, window: 0), 0, "SE 系：ステータスバーを隠すと 0")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: 20, window: 20), 20, "SE 系：ステータスバーを出しているとき")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: .nan, window: .infinity), 0, "おかしな値は使わない")
        XCTAssertEqual(HomeBatteryPlacement.topInset(swiftUI: -5, window: nil), 0, "負の値は使わない")
    }

    /// 画面の上の形は Safe Area の上の高さから見分ける。ステータスバーの帯の高さは、切り欠きのある機種は Safe Area の上、
    /// 切り欠きのない機種はふつうのステータスバーの 20pt
    func testScreenTopShapeAndStatusBarBandFromTheSafeArea() {
        for top: CGFloat in [59, 62] {
            XCTAssertEqual(HomeTopShape.from(safeAreaTop: top), .dynamicIsland, "\(top)pt")
            XCTAssertEqual(HomeBatteryPlacement.statusBarBandHeight(safeAreaTop: top), top)
        }
        for top: CGFloat in [44, 47, 48, 50] {
            XCTAssertEqual(HomeTopShape.from(safeAreaTop: top), .notch, "\(top)pt")
            XCTAssertEqual(HomeBatteryPlacement.statusBarBandHeight(safeAreaTop: top), top)
        }
        for top: CGFloat in [0, 20] {
            XCTAssertEqual(HomeTopShape.from(safeAreaTop: top), .flat, "\(top)pt")
            XCTAssertEqual(HomeBatteryPlacement.statusBarBandHeight(safeAreaTop: top), HomeLayoutMetrics.flatStatusBarHeight)
        }
        XCTAssertEqual(HomeTopShape.from(safeAreaTop: 48), .notch, "表示の拡大の Dynamic Island の機種（約 48pt）はノッチとして扱う（安全な側）")
        XCTAssertEqual(HomeTopShape.from(safeAreaTop: 51.4), .dynamicIsland, "14 Pro Max の表示の拡大")
    }

    /// Dynamic Island の機種：電池はステータスバーの帯の縦の中心（Safe Area の上の半分）にあり、Dynamic Island と縦の中心がほぼそろう。
    /// Dynamic Island の見込みの枠は、実際より広く・下まで見る
    func testBatteryCentersOnTheDynamicIslandBand() throws {
        for phone in Self.dynamicIslandPhones {
            let placement = HomeBatteryPlacement.make(screenWidth: phone.width, safeAreaTop: phone.safeTop)
            let island = try XCTUnwrap(phone.cutout)
            let estimate = try XCTUnwrap(HomeBatteryPlacement.cutoutEstimate(screenWidth: phone.width, safeAreaTop: phone.safeTop))
            XCTAssertEqual(placement.shape, .dynamicIsland, phone.name)
            XCTAssertEqual(placement.mode, .statusBarBand, phone.name)
            XCTAssertEqual(placement.centerY, phone.safeTop / 2, accuracy: 0.01, phone.name)
            XCTAssertEqual(placement.centerY, island.midY, accuracy: 3, "\(phone.name)：Dynamic Island と縦の中心がそろう")
            XCTAssertGreaterThanOrEqual(estimate.maxX, island.maxX, "\(phone.name)：見込みは実際より広い")
            XCTAssertGreaterThanOrEqual(estimate.maxY, island.maxY, "\(phone.name)：見込みは実際より下まで")
        }
    }

    /// ノッチの機種：ノッチの右の「耳」は「100%」とマークをひとまとめに置くには狭い（いちばん広いノッチ・表示の拡大まで見ると
    /// 8pt の余白を取れない）ので、ノッチの下に 8pt 以上あけて置く。日付の中心より上（日付・時計・タイムラインは動かさない）
    func testNotchPhonesPutTheBatteryJustBelowTheNotch() throws {
        for phone in Self.notchPhones {
            let placement = HomeBatteryPlacement.make(screenWidth: phone.width, safeAreaTop: phone.safeTop)
            let notch = try XCTUnwrap(phone.cutout)
            let estimate = try XCTUnwrap(HomeBatteryPlacement.cutoutEstimate(screenWidth: phone.width, safeAreaTop: phone.safeTop))
            XCTAssertEqual(placement.shape, .notch, phone.name)
            XCTAssertEqual(placement.mode, .belowCutout, phone.name)
            XCTAssertGreaterThanOrEqual(placement.frame(screenWidth: phone.width).minY - notch.maxY, 8, "\(phone.name)：ノッチの下に 8pt 以上")
            XCTAssertGreaterThanOrEqual(estimate.maxX, notch.maxX, "\(phone.name)：見込みは実際より広い")
            XCTAssertGreaterThanOrEqual(estimate.maxY, notch.maxY, "\(phone.name)：見込みは実際より下まで")
            // 日付の中心は Safe Area の上から約 20.7pt（上の段 10＋約 23.9pt の下の端に、22pt の日付の下をそろえる）。少し上で見る
            let dateCenter = phone.safeTop + 20
            XCTAssertLessThan(placement.centerY, dateCenter, "\(phone.name)：日付の中心より上")
        }
    }

    /// 切り欠きのない機種（SE 系）：ふつうのステータスバーの高さ 20pt の帯の中心を目安にし、画面の上の端から 6pt を残す
    func testBatteryOnPhonesWithoutACutoutUsesTheUsualStatusBarHeight() {
        let expected = max(HomeLayoutMetrics.flatStatusBarHeight / 2,
                           HomeLayoutMetrics.batteryMinimumScreenTop + HomeLayoutMetrics.batteryEstimatedSize.height / 2)
        for phone in Self.flatPhones {
            let placement = HomeBatteryPlacement.make(screenWidth: phone.width, safeAreaTop: phone.safeTop)
            XCTAssertEqual(placement.shape, .flat, phone.name)
            XCTAssertEqual(placement.mode, .statusBarBand, phone.name)
            XCTAssertEqual(placement.centerY, expected, accuracy: 0.01, phone.name)
            XCTAssertEqual(placement.trailingInset, HomeLayoutMetrics.horizontalPadding, accuracy: 0.01, "\(phone.name)：角が丸くない")
            XCTAssertNil(HomeBatteryPlacement.cutoutEstimate(screenWidth: phone.width, safeAreaTop: phone.safeTop))
        }
    }

    /// どの機種（表示の拡大を含む）でも、電池（見込みの大きさ）は切り欠きから 8pt 以上（横か縦）離れ、画面の上の端から 6pt 以上、
    /// 画面の角の丸みより 2pt 以上内側、右の余白の内側で、画面の右半分にある
    func testBatteryKeepsClearOfTheCutoutTheCornersAndTheTopEdge() {
        for phone in Self.dynamicIslandPhones + Self.notchPhones + Self.flatPhones {
            let placement = HomeBatteryPlacement.make(screenWidth: phone.width, safeAreaTop: phone.safeTop)
            let frame = placement.frame(screenWidth: phone.width)
            // 電池の層は、この枠の中心に画面の座標で置く（#77 の直し）：中心の高さは centerY、右の端は画面の幅 − trailingInset
            XCTAssertEqual(frame.midY, placement.centerY, accuracy: 0.01, phone.name)
            XCTAssertEqual(frame.maxX, phone.width - placement.trailingInset, accuracy: 0.01, phone.name)
            XCTAssertGreaterThanOrEqual(frame.minY, HomeLayoutMetrics.batteryMinimumScreenTop - 0.01, "\(phone.name)：画面の上の端")
            XCTAssertLessThanOrEqual(frame.maxX, phone.width - HomeLayoutMetrics.horizontalPadding + 0.01, "\(phone.name)：右の余白")
            XCTAssertGreaterThan(frame.minX, phone.width / 2, "\(phone.name)：画面の右半分")
            if let cutout = phone.cutout {
                let sideGap = frame.minX - cutout.maxX
                let belowGap = frame.minY - cutout.maxY
                XCTAssertTrue(sideGap >= 8 || belowGap >= 8, "\(phone.name)：切り欠きとの横 \(sideGap)pt・縦 \(belowGap)pt")
            }
            let corner = CGPoint(x: phone.width - phone.cornerRadius, y: phone.cornerRadius)
            if phone.cornerRadius > 0, frame.minY < corner.y, frame.maxX > corner.x {
                let dx = frame.maxX - corner.x
                let dy = frame.minY - corner.y
                let distance = (dx * dx + dy * dy).squareRoot()
                XCTAssertLessThanOrEqual(distance, phone.cornerRadius - 2, "\(phone.name)：画面の角の丸みの内側")
            }
        }
    }

    // MARK: - 日付と「終わった予定」の高さ（2026-10-19 ビルド確認 #78 の直し）

    /// 日本語の文字を 1 行で並べたときの高さ（UILabel で測る。SwiftUI の文字の行の高さとほぼ同じ）
    @MainActor
    private func lineHeight(_ text: String, _ font: UIFont) -> CGFloat {
        let label = UILabel()
        label.font = font
        label.text = text
        label.numberOfLines = 1
        return label.sizeThatFits(CGSize(width: 2000, height: 2000)).height
    }

    /// 上の段の並べ方の高さは前と同じ「上の余白 10pt＋前の大きさ（20pt）の日付の行」で、本当の日付（22pt）はその中に収まり（はみ出さない）、
    /// 上に 6pt 以上の余白が残る。「終わった予定」も、前の大きさ（footnote）の行＋ゆとりの中に本当の文字（14pt）が収まる。
    /// どちらも日本語の文字で、標準と最大（xxxLarge）の文字の大きさで測る（前は SF の見込みの数で余白を減らし、日本語の日付で
    /// 足りなかった：小さい iPhone の予定 11 件で 1 件減った）。前のテスト（見込みの数どおりか）を、この形に直した
    @MainActor
    func testTheLargerDateAndFinishedLinesFitInTheFormerHeights() {
        let date = "10月19日（月）"
        let finished = "終わった予定 3件"
        for category in [UIContentSizeCategory.large, .extraExtraExtraLarge] {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let newDate = lineHeight(date, UIFont.preferredFont(forTextStyle: .title2, compatibleWith: traits))
            let formerDate = lineHeight(date, UIFont.preferredFont(forTextStyle: .title3, compatibleWith: traits))
            XCTAssertLessThanOrEqual(newDate, HomeLayoutMetrics.topPadding + formerDate - 6,
                                     "\(category.rawValue)：22pt の日付が前の上の段の高さに収まり、上に 6pt 以上の余白が残る")
            let footnote = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits)
            let newFinished = lineHeight(finished, UIFontMetrics(forTextStyle: .footnote)
                .scaledFont(for: .systemFont(ofSize: HomeLayoutMetrics.finishedTextSize), compatibleWith: traits))
            XCTAssertLessThanOrEqual(newFinished, lineHeight(finished, footnote) + HomeLayoutMetrics.finishedLineAllowance,
                                     "\(category.rawValue)：14pt の「終わった予定」が、前の行＋ゆとりの中に収まる")
        }
        XCTAssertEqual(HomeLayoutMetrics.topPadding, 10, "上の段の並べ方の高さの余白は前と同じ")
        XCTAssertEqual(HomeLayoutMetrics.figureTopGapWithFinished + HomeLayoutMetrics.finishedLineAllowance, HomeLayoutMetrics.figureTopGap,
                       accuracy: 0.01, "時計がないとき：「終わった予定」の行に足した分だけ人型の上の最小の間を縮め、合わせて前と同じ")
        XCTAssertGreaterThanOrEqual(HomeLayoutMetrics.figureTopGapWithFinished, 5, "人型の上の間を削りすぎない")
    }

    /// 小さい iPhone（SE 系）の予定 11 件の画面（small-home-h2-many）で出せる件数。#76 は 14:00 まで出て「ほか4件」で、
    /// そのときのタイムラインに使える高さは 300〜330pt の範囲（詰めた段の行の高さから）。上の段・演出帯の並べ方の高さを前と同じに
    /// 保つので、その範囲の高さで 14:00 まで・「ほか4件」が出る。300pt より少しでも低いと 13:00 まで・「ほか5件」になる（#78 の形）
    #if DEBUG
    func testManyEventsOnASmallPhoneShowUntil14WithFourMore() throws {
        let today = CalendarDay(year: 2026, month: 10, day: 19)
        let scenario = HomeDebugScenario.many
        let sample = scenario.sample(around: today)
        let items = HomeScreenModel.make(events: sample.events, now: scenario.now(on: today),
                                         estimate: { scenario.estimate(for: $0) }).timeline.items
        for available: CGFloat in [300, 315, 329.9] {
            let plan = HomeTimelineLayout.plan(items: items, availableHeight: available)
            XCTAssertEqual(plan.density, .tight, "\(available)pt")
            XCTAssertEqual(plan.hiddenEventCount, 4, "\(available)pt：ほか4件")
            let last = try XCTUnwrap(plan.rows.last(where: { $0.item.isEventRow })?.item.event)
            XCTAssertEqual(last.startMinute, 14 * 60, "\(available)pt：14:00 まで")
        }
        let short = HomeTimelineLayout.plan(items: items, availableHeight: 299.9)
        XCTAssertEqual(short.hiddenEventCount, 5, "300pt より低いと 1 件減る（#78 の 13:00 まで・ほか5件）")
    }
    #endif

    // MARK: - 文字の段と行の間（2026-10-19 の見やすさの調整）

    /// 予定名が主役：どの段でも、主状態の予定名（札）がほかの予定名より大きい。詰める段ほど小さくなる（大きくはならない）
    func testEventTitlesLeadAndShrinkOnlyAsTheTimelineTightens() {
        let order: [HomeDensity] = [.spacious, .regular, .compact, .tight]
        for density in order {
            let sizes = HomeLayoutMetrics.titleSizes(density)
            XCTAssertGreaterThan(sizes.mainTitle, sizes.title, "\(density)：主状態の予定名がいちばん大きい")
        }
        for (wider, tighter) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThanOrEqual(HomeLayoutMetrics.titleSizes(wider).title, HomeLayoutMetrics.titleSizes(tighter).title,
                                        "\(wider) → \(tighter)：ほかの予定名")
            XCTAssertGreaterThanOrEqual(HomeLayoutMetrics.titleSizes(wider).mainTitle, HomeLayoutMetrics.titleSizes(tighter).mainTitle,
                                        "\(wider) → \(tighter)：主状態の予定名")
        }
    }

    /// 予定が少ない日は、余った高さで行の間を広げる（出発の点と開始の点のような 15 分の間も少し広げる。広げすぎない上限つき）。
    /// 予定が多い段ほど上限は小さく、いちばん詰めた段では広げない
    func testQuietDaysUseTheSpareHeightBetweenRows() throws {
        let one = items(events: 1)
        let first = try XCTUnwrap(one.first)
        XCTAssertTrue(first.isDeparture, "出発 9:45・開始 10:00")
        let plan = HomeTimelineLayout.plan(items: one, availableHeight: 1000)
        XCTAssertEqual(plan.density, .spacious)
        let maxExtra = HomeLayoutMetrics.rows(.spacious).maxExtraGap
        XCTAssertGreaterThanOrEqual(plan.rows[0].spacingAfter, 8, "15 分の間でも少し広げる")
        XCTAssertLessThan(plan.rows[0].spacingAfter, maxExtra, "短い間は長い間ほどは広げない")
        XCTAssertGreaterThan(maxExtra, HomeLayoutMetrics.rows(.regular).maxExtraGap)
        XCTAssertGreaterThan(HomeLayoutMetrics.rows(.regular).maxExtraGap, HomeLayoutMetrics.rows(.compact).maxExtraGap)
        XCTAssertEqual(HomeLayoutMetrics.rows(.tight).maxExtraGap, 0)
    }

    // MARK: - 予定が少ない日の流れ（2026-10-20「出発ポイントの視認性」）

    /// 予定 1〜2 件の日は、余った高さで「いま」→ 出発 → 開始の流れを読み取りやすくする：「いま」と最初の行のあいだをあけ、
    /// 出発の点と開始の点の短い間も上限の半分まで広げる。ただし画面全体へは引き伸ばさない（足すのは決まった上限まで）
    func testQuietDaysSpreadTheFlowFromNowToDepartureToStart() throws {
        let metrics = HomeLayoutMetrics.rows(.spacious)
        let one = items(events: 1)   // 出発 9:45・開始 10:00
        let base = total(one, .spacious)
        let plan = HomeTimelineLayout.plan(items: one, availableHeight: 1000)
        XCTAssertEqual(plan.density, .spacious)
        XCTAssertEqual(plan.leadingSpace, metrics.leadingGap, accuracy: 0.01, "「いま」と出発の点のあいだ")
        XCTAssertGreaterThan(plan.leadingSpace, 0)
        XCTAssertEqual(plan.rows[0].spacingAfter, metrics.maxExtraGap * metrics.minGapWeight, accuracy: 0.01,
                       "出発の点と開始の点（15 分）のあいだも、上限の半分まで")
        XCTAssertGreaterThanOrEqual(plan.rows[0].spacingAfter, 16)
        XCTAssertLessThanOrEqual(plan.height, base + metrics.leadingGap + metrics.maxExtraGap, "画面全体へは引き伸ばさない")
        XCTAssertLessThan(plan.height, 1000 / 2)

        // 余りが少ないときは、余った分だけを割り振る（はみ出さない）
        let snug = HomeTimelineLayout.plan(items: one, availableHeight: base + 6)
        XCTAssertEqual(snug.height, base + 6, accuracy: 0.01)
        XCTAssertLessThan(snug.leadingSpace, metrics.leadingGap)

        // 予定がない日（「予定はありません」だけ）は、前の位置のまま（「いま」との間を足さない）
        XCTAssertEqual(HomeTimelineLayout.plan(items: timeline([]).items, availableHeight: 1000).leadingSpace, 0)
    }

    /// 予定が 3 件以上の段（ふつう・詰める・さらに詰める）は前の密度の調整のまま（「いま」との間は足さない・短い間の下限なし）。
    /// どの件数・高さでも、足す間は余った高さの中だけで、並べた高さは使える高さを超えない（出せる予定の数を減らさない）
    func testSpacingOnlyUsesTheSpareHeight() {
        for density in [HomeDensity.regular, .compact, .tight] {
            XCTAssertEqual(HomeLayoutMetrics.rows(density).leadingGap, 0, "\(density)")
            XCTAssertEqual(HomeLayoutMetrics.rows(density).minGapWeight, 0, "\(density)")
        }
        for count in 1...12 {
            let rows = items(events: count, gap: 45)
            for available in stride(from: CGFloat(120), through: 900, by: 30) {
                let plan = HomeTimelineLayout.plan(items: rows, availableHeight: available)
                XCTAssertLessThanOrEqual(plan.height, available + 0.01, "予定 \(count) 件・高さ \(available)")
                if plan.density > .spacious {
                    XCTAssertEqual(plan.leadingSpace, 0, "予定 \(count) 件・高さ \(available)：多い日は「いま」との間を足さない")
                }
            }
        }
    }

    // MARK: - 出発の点の見た目（2026-10-20「出発ポイントの視認性」）

    /// 控えめ（quiet）は前のまま。60〜31 分・30 分以内と段が上がるほど、文字は大きく・太く、点ははっきりする。
    /// 強い警告の色（赤）は使わず、強調しても出発の点の行の高さに収まる（行の高さ・出せる予定の数は変えない）
    func testDepartureLookGetsStrongerByStageAndFitsTheRow() throws {
        for density in HomeDensity.allCases {
            let quiet = HomeLayoutMetrics.departureLook(.quiet, density: density)
            let soon = HomeLayoutMetrics.departureLook(.soon, density: density)
            let imminent = HomeLayoutMetrics.departureLook(.imminent, density: density)
            XCTAssertNil(quiet.textSize, "\(density)：控えめは前の文字のまま")
            XCTAssertEqual(quiet.weight, .regular)
            XCTAssertEqual(quiet.color, Theme.Colors.textSecondary)
            XCTAssertEqual(quiet.dotDiameter, HomeLayoutMetrics.departureDot)
            XCTAssertFalse(quiet.dotFilled)

            let soonSize = try XCTUnwrap(soon.textSize)
            let imminentSize = try XCTUnwrap(imminent.textSize)
            let timeSize: CGFloat = density <= .regular ? 15 : 13   // 控えめなときの時刻の文字（subheadline・footnote）
            XCTAssertGreaterThan(soonSize, timeSize, "\(density)：60〜31 分は時刻の文字より大きい")
            XCTAssertGreaterThan(imminentSize, soonSize, "\(density)：30 分以内はさらに大きい")
            XCTAssertEqual(soon.weight, .semibold)
            XCTAssertEqual(imminent.weight, .bold)
            XCTAssertGreaterThan(soon.dotDiameter, quiet.dotDiameter)
            XCTAssertGreaterThanOrEqual(imminent.dotDiameter, soon.dotDiameter)
            XCTAssertTrue(imminent.dotFilled, "30 分以内は点を塗りつぶす")
            for look in [soon, imminent] {
                XCTAssertNotEqual(look.color, Theme.Colors.danger, "強い警告の色は使わない")
                XCTAssertNotEqual(look.color, Theme.Colors.textSecondary, "ブランドの色で見やすく")
                // 行の高さに収まる（文字の行の高さは大きさの約 1.2 倍。上下に少し余白を残す）
                let lineHeight = try XCTUnwrap(look.textSize) * 1.2
                XCTAssertLessThanOrEqual(lineHeight + 2, HomeLayoutMetrics.rows(density).departureRow, "\(density)：行の高さに収まる")
                XCTAssertLessThanOrEqual(look.dotDiameter, HomeLayoutMetrics.railWidth, "点は左の列の幅に収まる")
            }
        }
    }

    /// 文字を大きくしても、予定が多い日に出せる予定の数と密度の選び方を変えない（2026-10-19 の見やすさの調整の指示）。
    /// 件数と密度を決める行の高さ（ふつう・詰める・さらに詰める段、「いま」・過ぎた出発の点の行）は TestFlight 1.0 (32) のまま。
    /// 行の間の上限（maxExtraGap）は余った高さだけを使うので件数に関わらない。実機で決めてここを変えるときは、
    /// 予定 11 件・小さい iPhone の画面で出せる件数が変わらないかを確かめてから、このテストも直す
    func testRowHeightsThatDecideHowManyEventsFitAreKept() {
        func heights(_ density: HomeDensity) -> [CGFloat] {
            let rows = HomeLayoutMetrics.rows(density)
            return [rows.eventRow, rows.mainRow, rows.departureRow, rows.separatorRow, rows.messageRow, rows.moreRow]
        }
        XCTAssertEqual(heights(.regular), [44, 58, 34, 28, 40, 32])
        XCTAssertEqual(heights(.compact), [36, 52, 28, 26, 36, 30])
        XCTAssertEqual(heights(.tight), [30, 46, 24, 22, 32, 26])
        XCTAssertEqual(HomeLayoutMetrics.nowRowHeight, 30)
        XCTAssertEqual(HomeLayoutMetrics.pastDepartureRowHeight, 26)
    }
}
