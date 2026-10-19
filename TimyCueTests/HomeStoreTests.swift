import UIKit
import XCTest
@testable import TimyCue

/// H2 の新しい Home の画面の状態（吹き出し）・電池の表示・画面写真用の見本（spec §88.2・Q84・Q29）
final class HomeStoreTests: XCTestCase {
    // MARK: - 吹き出し（予定詳細・終わった予定）

    func testTappingARowOpensTheDetailAndTappingAgainClosesIt() {
        let store = HomeStore()
        let id = UUID()
        store.tapRow(eventID: id, anchorID: "start-a")
        XCTAssertEqual(store.bubble, .detail(eventID: id, anchorID: "start-a"))
        XCTAssertEqual(store.bubbleAnchorID, "start-a", "押した行の近くに出す")
        store.tapRow(eventID: id, anchorID: "departure-a")
        XCTAssertEqual(store.bubble, .detail(eventID: id, anchorID: "departure-a"), "出発の点を押しても同じ予定の詳細（出す位置は押した行）")
        store.tapRow(eventID: id, anchorID: "departure-a")
        XCTAssertNil(store.bubble, "同じ行をもう一度押したら閉じる")
        store.tapRow(eventID: id, anchorID: "start-a")
        store.closeBubble()
        XCTAssertNil(store.bubble, "吹き出しの外を押したら閉じる（Q29）")
        XCTAssertNil(store.bubbleAnchorID)
    }

    func testTheFinishedListSwitchesToADetailAndBack() {
        let store = HomeStore()
        let id = UUID()
        store.tapFinished()
        XCTAssertEqual(store.bubble, .finished(selected: nil), "「終わった予定 ○件」は Home の中で広げず、吹き出しで一覧（Q84）")
        XCTAssertEqual(store.bubbleAnchorID, HomeStore.finishedAnchorID)
        store.showFinishedDetail(id)
        XCTAssertEqual(store.bubble, .finished(selected: id), "同じ吹き出しの中で予定詳細に切り替える（Q28(a)）")
        store.backToFinishedList()
        XCTAssertEqual(store.bubble, .finished(selected: nil), "もう一度押すと一覧へ戻る（Q29）")
        store.tapFinished()
        XCTAssertNil(store.bubble)
    }

    func testTheBubbleClosesWhenItsEventIsGone() {
        let store = HomeStore()
        let kept = UUID()
        let removed = UUID()
        store.tapRow(eventID: kept, anchorID: "start-kept")
        store.reconcile(eventIDs: [kept])
        XCTAssertEqual(store.bubble, .detail(eventID: kept, anchorID: "start-kept"), "予定が残っていれば閉じない")
        store.tapRow(eventID: removed, anchorID: "start-removed")
        store.reconcile(eventIDs: [kept])
        XCTAssertNil(store.bubble, "Apple 連携を OFF にした・保存先を変えた・消した予定の吹き出しは閉じる")
        store.tapFinished()
        store.showFinishedDetail(removed)
        store.reconcile(eventIDs: [kept])
        XCTAssertEqual(store.bubble, .finished(selected: nil), "終わった予定の一覧は残し、消えた予定の詳細だけ一覧へ戻す")
    }

    // MARK: - 電池の表示（§88.2。形は仮）

    func testBatteryReadingFromTheDevice() throws {
        XCTAssertNil(HomeBatteryReading(level: -1, state: .unknown), "残量が取れないとき（シミュレータなど）は出さない")
        XCTAssertNil(HomeBatteryReading(level: 0.5, state: .unknown))
        let usual = try XCTUnwrap(HomeBatteryReading(level: 0.8, state: .unplugged))
        XCTAssertEqual(usual.text, "80%")
        XCTAssertFalse(usual.isCharging)
        XCTAssertFalse(usual.isLow)
        XCTAssertEqual(usual.symbolName, "battery.75")
        let low = try XCTUnwrap(HomeBatteryReading(level: 0.15, state: .unplugged))
        XCTAssertTrue(low.isLow, "残りが少ないときは色を変える")
        XCTAssertEqual(low.symbolName, "battery.25")
        let charging = try XCTUnwrap(HomeBatteryReading(level: 0.15, state: .charging))
        XCTAssertFalse(charging.isLow, "充電中は少なくても警告の色にしない")
        XCTAssertEqual(charging.symbolName, "battery.100.bolt")
        XCTAssertTrue(try XCTUnwrap(HomeBatteryReading(level: 1, state: .full)).isCharging)
        XCTAssertEqual(HomeBatteryReading(percent: 120, isCharging: false).percent, 100)
    }

    // MARK: - 画面写真用の見本（DEBUG だけ）

    #if DEBUG
    func testScreenshotScenariosShowTheIntendedStates() {
        let today = CalendarDay(year: 2026, month: 10, day: 19)
        func screen(_ scenario: HomeDebugScenario) -> HomeScreenModel {
            let sample = scenario.sample(around: today)
            return HomeScreenModel.make(events: sample.events, now: scenario.now(on: today),
                                        estimate: { scenario.estimate(for: $0) })
        }
        XCTAssertEqual(screen(.empty).timeline.items.map(\.kind), [.message(HomeTimeline.noEventsText)], "1 今日の予定なし")
        XCTAssertEqual(screen(.onePlaceless).clock?.word, "開始", "2 場所なし 1 件")
        XCTAssertEqual(screen(.onePlaceless).clock?.face.remainingMinutes, 23)
        XCTAssertEqual(screen(.onePlace).clock?.word, "出発", "3 場所あり 1 件")
        XCTAssertEqual(screen(.onePlace).clock?.face.remainingMinutes, 23)
        XCTAssertEqual(screen(.two).timeline.eventCount, 2, "4 予定 2 件")
        XCTAssertEqual(screen(.two).mode, .human)
        let several = screen(.several)
        XCTAssertEqual(several.timeline.eventCount, 5, "5 予定 3〜5 件")
        XCTAssertNil(several.clock, "出発まで 85 分：時計なし")
        XCTAssertEqual(several.mode, .turtle)
        XCTAssertEqual(screen(.many).timeline.eventCount, 11, "6 予定 6 件以上")
        XCTAssertEqual(screen(.departure60).clock?.face.remainingMinutes, 60, "7 出発まで 60 分")
        XCTAssertEqual(screen(.departure60).mode, .human)
        XCTAssertEqual(screen(.departure30).clock?.face.remainingMinutes, 30, "8 出発まで 30 分")
        XCTAssertEqual(screen(.departure30).mode, .rabbit)
        XCTAssertEqual(screen(.departure1).clock?.face.remainingMinutes, 1, "9 出発まで 1 分")
        let overdue = screen(.overdue)
        XCTAssertNil(overdue.clock, "10 出発時刻を過ぎた")
        XCTAssertEqual(overdue.headline, "出発時刻を3分過ぎています")
        XCTAssertNotNil(overdue.timeline.pastDeparture)
        let finished = screen(.finished)
        XCTAssertEqual(finished.timeline.finishedEvents.count, 3, "11 終わった予定がある")
        XCTAssertEqual(finished.timeline.items.first?.kind, .inProgress(end: today.date(atMinute: 14 * 60 + 30)))
        XCTAssertEqual(screen(.started).headline, "予定時刻になりました")
        XCTAssertEqual(screen(.allDayOnly).timeline.items.first?.kind, .message(HomeTimeline.onlyAllDayText))
        XCTAssertTrue(screen(.tomorrow).timeline.items.contains { $0.kind == .daySeparator(today.adding(days: 1)) })
        XCTAssertEqual(screen(.longText).clock?.face.remainingMinutes, 23, "14 長い予定名・場所名")
        for scenario in HomeDebugScenario.allCases {
            for event in scenario.sample(around: today).events where !event.isAllDay && event.day == today {
                XCTAssertTrue(event.displayTitle.contains("見本"), "見本の予定と分かる名前（\(scenario.rawValue)：\(event.displayTitle)）")
            }
        }
    }
    #endif
}
