import XCTest
@testable import TimyCue

/// ホームの時計（spec §6・追加仕様書 §44。2026-10-14 の修正指示）
final class HomeClockTests: XCTestCase {
    private let calendar = Calendar.timyCue
    private let day = CalendarDay(year: 2026, month: 10, day: 14)

    private func at(_ minute: Int, seconds: Int = 0) -> Date {
        day.date(atMinute: minute, calendar: calendar).addingTimeInterval(TimeInterval(seconds))
    }

    private func clockFace(_ now: Int, _ target: Int, seconds: Int = 0) -> HomeClockMath.Face? {
        HomeClockMath.face(now: at(now, seconds: seconds), target: at(target), calendar: calendar)
    }

    func testHandsShowTheRealTime() throws {
        let face = try XCTUnwrap(clockFace(16 * 60 + 52, 17 * 60 + 15))
        XCTAssertEqual(face.minuteHandDegrees.truncatingRemainder(dividingBy: 360), 312, "16:52 なら分針は 52 分の位置")
        XCTAssertEqual(face.hourHandDegrees.truncatingRemainder(dividingBy: 360), 146, "時針は 4 と 5 の間で 5 寄り")
    }

    func testRingRunsFromNowToTheTargetOnTheClockFace() throws {
        let face = try XCTUnwrap(clockFace(16 * 60 + 52, 17 * 60 + 15))
        XCTAssertEqual(face.remainingMinutes, 23)
        XCTAssertEqual(face.ringStartDegrees.truncatingRemainder(dividingBy: 360), 312, "いま＝時計の 52 分の位置から")
        XCTAssertEqual(face.ringSweepDegrees, 138, "23 分ぶん（360° × 23 / 60）")
        XCTAssertEqual((face.ringStartDegrees + face.ringSweepDegrees).truncatingRemainder(dividingBy: 360), 90,
                       "出発＝時計の 15 分の位置まで")
    }

    func testRingLengthAndWindow() {
        XCTAssertEqual(clockFace(16 * 60, 17 * 60)?.ringSweepDegrees, 360, "60 分前は 1 周")
        XCTAssertEqual(clockFace(16 * 60 + 30, 17 * 60)?.ringSweepDegrees, 180, "30 分前は半周")
        XCTAssertEqual(clockFace(16 * 60 + 45, 17 * 60)?.ringSweepDegrees, 90, "15 分前は 1/4 周")
        XCTAssertNil(clockFace(15 * 60 + 59, 17 * 60), "60 分より前は時計を出さない（spec §6「出発 60 分前から」）")
        XCTAssertNil(clockFace(17 * 60, 17 * 60), "その時刻になったら出さない")
    }

    func testSecondsDoNotChangeTheMinute() {
        XCTAssertEqual(clockFace(16 * 60 + 52, 17 * 60 + 15, seconds: 40)?.remainingMinutes, 23,
                       "iPhone の時計が 16:52 の間は、残り 23 分のまま")
        XCTAssertEqual(clockFace(16 * 60 + 52, 17 * 60 + 15, seconds: 40)?.now, at(16 * 60 + 52))
    }

    func testAnglesKeepGoingForwardAcrossTheHourAndMidnight() throws {
        let before = try XCTUnwrap(clockFace(16 * 60 + 59, 17 * 60 + 15))
        let after = try XCTUnwrap(clockFace(17 * 60, 17 * 60 + 15))
        XCTAssertEqual(after.minuteHandDegrees - before.minuteHandDegrees, 6, "0 分をまたいでも逆回りしない")
        XCTAssertEqual(after.hourHandDegrees - before.hourHandDegrees, 0.5)

        let lastMinute = try XCTUnwrap(clockFace(23 * 60 + 59, 24 * 60 + 10))
        let nextDay = try XCTUnwrap(HomeClockMath.face(now: day.adding(days: 1).date(atMinute: 0, calendar: calendar),
                                                       target: at(24 * 60 + 10), calendar: calendar))
        XCTAssertEqual(nextDay.minuteHandDegrees - lastMinute.minuteHandDegrees, 6, "0 時をまたいでも逆回りしない")
        XCTAssertEqual(nextDay.minuteHandDegrees.truncatingRemainder(dividingBy: 360), 0)
        XCTAssertEqual(nextDay.hourHandDegrees.truncatingRemainder(dividingBy: 360), 0)
    }

    func testColorBands() {
        XCTAssertEqual(HomeClockMath.band(remainingMinutes: 60), .plenty)
        XCTAssertEqual(HomeClockMath.band(remainingMinutes: 31), .plenty, "60〜31 分（spec §6）")
        XCTAssertEqual(HomeClockMath.band(remainingMinutes: 30), .half)
        XCTAssertEqual(HomeClockMath.band(remainingMinutes: 16), .half, "30〜16 分")
        XCTAssertEqual(HomeClockMath.band(remainingMinutes: 15), .last)
        XCTAssertEqual(HomeClockMath.band(remainingMinutes: 1), .last, "15〜0 分")
    }

    func testNowLabelIsHiddenWhenBothEndsAreWithinFiveMinutesOnTheFace() {
        XCTAssertEqual(clockFace(16 * 60 + 52, 17 * 60 + 15)?.showsNowLabel, true)
        XCTAssertEqual(clockFace(17 * 60 + 9, 17 * 60 + 15)?.showsNowLabel, true, "残り 6 分なら出す")
        XCTAssertEqual(clockFace(17 * 60 + 10, 17 * 60 + 15)?.showsNowLabel, false, "残り 5 分以内は「出発」と近いので出さない（2026-10-14 決定）")
        XCTAssertEqual(clockFace(16 * 60 + 21, 17 * 60 + 15)?.showsNowLabel, true, "残り 54 分なら出す")
        XCTAssertEqual(clockFace(16 * 60 + 20, 17 * 60 + 15)?.showsNowLabel, false, "残り 55〜60 分も、時計の上では 5 分以内なので出さない")
        XCTAssertEqual(clockFace(16 * 60 + 15, 17 * 60 + 15)?.markerDistanceMinutes, 0, "60 分前は同じ位置")
    }

    func testMarkersAreShiftedOnlyWhenTheyCoincide() {
        XCTAssertEqual(clockFace(16 * 60 + 15, 17 * 60 + 15)?.markersCoincide, true, "60 分前は丸がちょうど重なるので、内と外へずらす")
        XCTAssertEqual(clockFace(16 * 60 + 16, 17 * 60 + 15)?.markersCoincide, false)
        XCTAssertEqual(clockFace(17 * 60 + 14, 17 * 60 + 15)?.markersCoincide, false)
    }

    func testFlowText() {
        XCTAssertEqual(HomeClockMath.flowText(now: at(16 * 60 + 52), target: at(17 * 60 + 15), calendar: calendar), "16:52 → 17:15")
    }

    func testClockCountsToTheStartUntilDepartureIsCalculated() {
        var visit = CalendarEvent(day: day, startMinute: 17 * 60 + 15, title: "A社")
        visit.locationName = "広島駅"
        let start = HomeSchedule.startDate(of: visit, calendar: calendar)
        XCTAssertEqual(HomeSchedule.clockTarget(for: visit, calendar: calendar),
                       HomeSchedule.ClockTarget(date: start, isDeparture: false),
                       "出発時刻の計算（第 5 段階）ができるまでは、暫定で予定開始を数える")
        XCTAssertEqual(HomeSchedule.clockTarget(for: visit, calendar: calendar).word, "開始")

        let leaveAt = at(16 * 60 + 40)
        let withDeparture = HomeSchedule.clockTarget(for: visit, calendar: calendar, departure: { _ in leaveAt })
        XCTAssertEqual(withDeparture, HomeSchedule.ClockTarget(date: leaveAt, isDeparture: true))
        XCTAssertEqual(withDeparture.word, "出発")

        let noPlace = CalendarEvent(day: day, startMinute: 17 * 60 + 15, title: "打合せ")
        XCTAssertFalse(HomeSchedule.clockTarget(for: noPlace, calendar: calendar, departure: { _ in leaveAt }).isDeparture,
                       "場所のない予定は、出発ではなく予定開始を基準にする（追加仕様書 §36）")
    }
}
