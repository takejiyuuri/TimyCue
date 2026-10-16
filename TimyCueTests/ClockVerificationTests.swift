#if TIMYCUE_DEV_TOOLS
import XCTest
@testable import TimyCue

/// 時計の検証画面（H2 の前提作業 2。2026-10-16）。表示の時刻を動かしたとき、今の Home と同じ計算で、
/// 決まりどおりの時計・知らせになるか（時計の計算そのものは HomeClockTests・HomeStateTests）
final class ClockVerificationTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 16)

    private func model(_ offset: Int, _ scenario: ClockVerificationScenario = .withPlace) -> ClockVerificationModel {
        ClockVerificationModel(scenario: scenario, day: day, offsetMinutes: offset)
    }

    func testNoClockBeforeSixtyMinutes() {
        XCTAssertNil(model(-61).face, "60 分より前は時計なし")
        XCTAssertEqual(model(-61).stateTitle, "時計なし（60分より前の静かな表示）")
        XCTAssertNil(model(-61, .withoutPlace).face)
    }

    func testClockAppearsAtSixtyMinutesWithShiftedMarkers() throws {
        let face = try XCTUnwrap(model(-60).face, "60 分前に時計が出る")
        XCTAssertEqual(face.remainingMinutes, 60)
        XCTAssertTrue(face.markersCoincide, "60 分前は、いまの丸と出発の丸をずらす")
        XCTAssertFalse(face.showsNowLabel)
        XCTAssertEqual(model(-60).targetWord, "出発")
    }

    func testEachMinuteMovesTheHandAndShortensTheRing() throws {
        let before = try XCTUnwrap(model(-24).face)
        let after = try XCTUnwrap(model(-23).face)
        XCTAssertEqual(after.minuteHandDegrees - before.minuteHandDegrees, 6, accuracy: 0.001, "分針は 1 分で 6°")
        XCTAssertEqual(after.hourHandDegrees - before.hourHandDegrees, 0.5, accuracy: 0.001)
        XCTAssertEqual(before.ringSweepDegrees - after.ringSweepDegrees, 6, accuracy: 0.001, "弧は 1 分で 6° 短くなる")
        XCTAssertEqual(after.minuteHandDegrees.truncatingRemainder(dividingBy: 360), 37 * 6, accuracy: 0.001, "9:37 なら 37 分の位置")
    }

    func testRingColorAndNowLabel() throws {
        XCTAssertEqual(model(-31).ringColorTitle, "緑（60〜31分）")
        XCTAssertEqual(model(-30).ringColorTitle, "黄（30〜16分）")
        XCTAssertEqual(model(-15).ringColorTitle, "コーラル（15〜1分）")
        XCTAssertFalse(try XCTUnwrap(model(-55).face).showsNowLabel, "55〜60 分は「いま」を出さない")
        XCTAssertTrue(try XCTUnwrap(model(-54).face).showsNowLabel)
        XCTAssertTrue(try XCTUnwrap(model(-6).face).showsNowLabel)
        XCTAssertFalse(try XCTUnwrap(model(-5).face).showsNowLabel, "残り 5 分以内は「いま」を出さない")
    }

    func testClockEndsAtDepartureAndTurnsIntoTheNotices() {
        XCTAssertEqual(model(-1).face?.remainingMinutes, 1)
        XCTAssertNil(model(0).face, "出発時刻で時計は終わる")
        XCTAssertEqual(model(0).state.headline, "出発してください")
        XCTAssertEqual(model(2).state.headline, "出発してください")
        XCTAssertEqual(model(3).state.headline, "出発時刻を3分過ぎています", "3 分以上は「○分過ぎています」")
    }

    func testEventWithoutPlaceCountsToTheStart() throws {
        let face = try XCTUnwrap(model(-23, .withoutPlace).face)
        XCTAssertEqual(face.remainingMinutes, 23)
        XCTAssertEqual(model(-23, .withoutPlace).targetWord, "開始", "場所なしは「開始まで」")
        XCTAssertNil(model(0, .withoutPlace).face)
        XCTAssertEqual(model(0, .withoutPlace).state.headline, "予定時刻になりました")
        XCTAssertEqual(model(2, .withoutPlace).state.headline, "予定時刻になりました", "開始の知らせは約 3 分")
        XCTAssertNil(model(3, .withoutPlace).state.headline)
    }

    func testCenterTextPresets() {
        let texts = ClockVerificationPreset.centerTexts.map { preset -> String in
            let model = ClockVerificationModel(scenario: preset.scenario, day: day, offsetMinutes: preset.offset)
            return "\(model.targetWord ?? "")まで\(model.face?.remainingMinutes ?? -1)分"
        }
        XCTAssertEqual(texts, ["出発まで60分", "出発まで23分", "出発まで1分", "開始まで23分"])
    }

    func testStepStaysInRangeAndStopsAutoAdvance() {
        let store = ClockVerificationStore(offsetMinutes: 38, day: day)
        store.isRunning = true
        store.step(1)
        XCTAssertEqual(store.offsetMinutes, 39)
        XCTAssertTrue(store.isRunning)
        store.step(5)
        XCTAssertEqual(store.offsetMinutes, ClockVerificationStore.range.upperBound)
        XCTAssertFalse(store.isRunning, "範囲の端で自動を止める")
        store.jump(to: -500, scenario: .withoutPlace)
        XCTAssertEqual(store.offsetMinutes, ClockVerificationStore.range.lowerBound)
        XCTAssertEqual(store.scenario, .withoutPlace)
    }

    func testLaunchArgumentOffsets() {
        XCTAssertEqual(ClockVerificationStore.offset(fromArgument: "m23"), -23)
        XCTAssertEqual(ClockVerificationStore.offset(fromArgument: "p3"), 3)
        XCTAssertEqual(ClockVerificationStore.offset(fromArgument: "0"), 0)
        XCTAssertNil(ClockVerificationStore.offset(fromArgument: "x"))
    }

    func testVerificationUsesOnlySampleEvents() {
        XCTAssertTrue(model(0).event.displayTitle.hasPrefix("見本"), "見本の予定だけ（実際の予定は使わない）")
        XCTAssertTrue(model(0, .withoutPlace).event.displayTitle.hasPrefix("見本"))
        XCTAssertFalse(HomeSchedule.hasPlace(model(0, .withoutPlace).event))
        XCTAssertTrue(HomeSchedule.hasPlace(model(0).event))
    }
}
#endif
