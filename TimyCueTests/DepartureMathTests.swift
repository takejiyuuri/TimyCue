import XCTest
@testable import TimyCue

/// 推奨出発時刻の計算（追加仕様書 §8.1〜§8.3）
final class DepartureMathTests: XCTestCase {
    private let calendar = Calendar.timyCue
    private let day = CalendarDay(year: 2026, month: 10, day: 14)

    func testFormulaExample() {
        // 予定開始 10:00、到着目標 9:50、予測移動 30 分、安全マージン 5 分 → 推奨出発 9:15（§8.1 の例）
        let start = day.date(atMinute: 10 * 60, calendar: calendar)
        XCTAssertEqual(DepartureMath.recommendedDeparture(start: start, arrivalTargetMinutes: 10, travelMinutes: 30, marginMinutes: 5),
                       day.date(atMinute: 9 * 60 + 15, calendar: calendar))
        XCTAssertEqual(DepartureMath.arrivalTarget(start: start, arrivalTargetMinutes: 0), start, "0 分前は予定開始時刻")
    }

    func testTravelTimeIsRoundedUpToTheMinute() {
        XCTAssertEqual(DepartureMath.minutes(ofTravel: 28 * 60 + 34), 29, "28 分 34 秒 → 29 分（§8.2）")
        XCTAssertEqual(DepartureMath.minutes(ofTravel: 20 * 60), 20)
        XCTAssertEqual(DepartureMath.minutes(ofTravel: 0), 0)
    }

    func testCarAddsTheGenericParkingBufferUntilLearned() {
        XCTAssertEqual(DepartureMath.predictedTravelMinutes(mapSeconds: 20 * 60, transport: .car), 25,
                       "車は地図の移動時間＋汎用の 5 分（§8.2）")
        XCTAssertEqual(DepartureMath.predictedTravelMinutes(mapSeconds: 20 * 60, transport: .car, learnedParkingMinutes: 8), 28,
                       "学習がたまったら学習の値に置き換える")
        XCTAssertEqual(DepartureMath.predictedTravelMinutes(mapSeconds: 20 * 60, transport: .walk), 20, "徒歩には足さない")
    }

    func testSafetyMargin() {
        XCTAssertEqual(DepartureMath.safetyMarginMinutes(travelMinutes: 37, level: .standard), 4, "37 分 × 10％ ＝ 3.7 → 4 分（§8.3）")
        XCTAssertEqual(DepartureMath.safetyMarginMinutes(travelMinutes: 30, level: .standard), 3, "ちょうど 3 分は 3 分のまま")
        XCTAssertEqual(DepartureMath.safetyMarginMinutes(travelMinutes: 20, level: .standard), 3, "いちばん短くて 3 分")
        XCTAssertEqual(DepartureMath.safetyMarginMinutes(travelMinutes: 40, level: .relaxed), 6, "やや余裕は 15％・最低 5 分")
        XCTAssertEqual(DepartureMath.safetyMarginMinutes(travelMinutes: 30, level: .generous), 10, "かなり余裕は 25％・最低 10 分")
        XCTAssertEqual(DepartureMath.safetyMarginMinutes(travelMinutes: 60, level: .generous), 15)
        XCTAssertEqual(DepartureMath.MarginLevel.allCases.map(\.displayName), ["標準", "やや余裕", "かなり余裕"])
    }
}
