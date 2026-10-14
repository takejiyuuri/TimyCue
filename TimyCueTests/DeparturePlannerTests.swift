import CoreLocation
import XCTest
@testable import TimyCue

/// 出発時刻を計算する前の決まり（2026-10-14 決定）と、計算の流れ（追加仕様書 §8.1〜§8.3）
final class DeparturePlannerTests: XCTestCase {
    private let calendar = Calendar.timyCue
    private let day = CalendarDay(year: 2026, month: 10, day: 14)
    private let office = SavedPlace(name: "A社", address: nil, latitude: 34.39, longitude: 132.46)
    private let home = SavedPlace(name: "自宅", address: nil, latitude: 34.40, longitude: 132.45)

    private func at(_ minute: Int, day: CalendarDay? = nil) -> Date {
        (day ?? self.day).date(atMinute: minute, calendar: calendar)
    }

    private func event(_ title: String, at minute: Int, place: String? = nil, day: CalendarDay? = nil) -> CalendarEvent {
        var event = CalendarEvent(day: day ?? self.day, startMinute: minute, title: title)
        event.locationName = place
        return event
    }

    // MARK: - どの予定を計算するか

    func testOnlyUpcomingPlaceEventsWithinADayAreCalculated() {
        let past = event("朝会", at: 8 * 60, place: "本社")
        let noPlace = event("電話", at: 10 * 60)
        let first = event("A社", at: 11 * 60, place: "A社")
        let second = event("B社", at: 13 * 60, place: "B社")
        let third = event("C社", at: 15 * 60, place: "C社")
        let fourth = event("D社", at: 17 * 60, place: "D社")
        let tomorrowLate = event("E社", at: 12 * 60, place: "E社", day: day.adding(days: 1))
        let result = DeparturePlanner.eventsToCalculate(in: [fourth, past, noPlace, third, first, second, tomorrowLate],
                                                        now: at(9 * 60), calendar: calendar)
        XCTAssertEqual(result.map(\.title), ["A社", "B社", "C社"], "これから 24 時間の場所ありの予定を、近い順に 3 件まで（仮）")
    }

    // MARK: - 起点（2026-10-14 決定：①同じ日の前の場所ありの予定 → ②自宅から出ることが多いなら自宅 → ③当日の現在地）

    func testPlannedOriginIsThePreviousPlaceEventOfTheSameDay() {
        var book = PlaceBook()
        book.confirm(office, for: "A社")
        let morning = event("A社訪問", at: 9 * 60, place: "A社")
        let call = event("電話", at: 11 * 60)
        let visit = event("B社", at: 14 * 60, place: "B社")
        var settings = DepartureSettings()
        settings.firstEventOrigin = .home
        settings.home = home
        XCTAssertEqual(DeparturePlanner.plannedOrigin(for: visit, among: [morning, call, visit], settings: settings, placeBook: book, calendar: calendar),
                       office, "場所なしの予定はさかのぼって、その前の場所ありの予定から")
        XCTAssertEqual(DeparturePlanner.plannedOrigin(for: morning, among: [morning, call, visit], settings: settings, placeBook: book, calendar: calendar),
                       home, "その日の最初の予定は、自宅から出ることが多いなら自宅")
    }

    func testPlannedOriginWhenNothingIsFixed() {
        let visit = event("B社", at: 14 * 60, place: "B社")
        var settings = DepartureSettings()
        settings.firstEventOrigin = .elsewhere
        settings.home = home
        XCTAssertNil(DeparturePlanner.plannedOrigin(for: visit, among: [visit], settings: settings, placeBook: PlaceBook(), calendar: calendar),
                     "自宅以外から出ることが多いなら、固定の起点はない（当日の現在地）")
        settings.firstEventOrigin = .home
        settings.home = nil
        XCTAssertNil(DeparturePlanner.plannedOrigin(for: visit, among: [visit], settings: settings, placeBook: PlaceBook(), calendar: calendar),
                     "自宅が未登録なら固定の起点はない")
    }

    func testOriginSwitchesToCurrentLocation() {
        let visit = event("B社", at: 14 * 60, place: "B社")
        var settings = DepartureSettings()
        settings.firstEventOrigin = .home
        settings.home = home
        let leave = at(13 * 60 + 20)
        XCTAssertEqual(DeparturePlanner.origin(for: visit, among: [visit], settings: settings, placeBook: PlaceBook(),
                                               lastDeparture: leave, now: at(12 * 60 + 19), calendar: calendar),
                       .place(home), "推奨出発時刻の 60 分より前は固定の起点")
        XCTAssertEqual(DeparturePlanner.origin(for: visit, among: [visit], settings: settings, placeBook: PlaceBook(),
                                               lastDeparture: leave, now: at(12 * 60 + 20), calendar: calendar),
                       .currentLocation, "推奨出発時刻の 60 分前から実際の現在地（追加仕様書 §8.5）")
    }

    func testWithoutAFixedOriginCalculationStartsFourHoursBeforeTheStart() {
        let visit = event("B社", at: 14 * 60, place: "B社")
        let settings = DepartureSettings()
        XCTAssertEqual(DeparturePlanner.origin(for: visit, among: [visit], settings: settings, placeBook: PlaceBook(),
                                               lastDeparture: nil, now: at(9 * 60 + 59), calendar: calendar),
                       .notYet, "固定の起点がなければ、予定開始の 4 時間前まではまだ計算しない（暫定）")
        XCTAssertEqual(DeparturePlanner.origin(for: visit, among: [visit], settings: settings, placeBook: PlaceBook(),
                                               lastDeparture: nil, now: at(10 * 60), calendar: calendar),
                       .currentLocation, "4 時間前から現在地で計算する")
    }

    // MARK: - 移動手段

    func testTransportForCalculation() {
        var settings = DepartureSettings()
        var info = TimyCueEventMetadata()
        info.transport = .walk
        XCTAssertEqual(DeparturePlanner.transport(for: info, settings: settings), .walk, "はっきり指定した手段はそのまま")
        info.transport = .auto
        XCTAssertNil(DeparturePlanner.transport(for: info, settings: settings), "「自動」で普段の手段をまだ選んでいなければ決まらない")
        settings.usualTransport = .publicTransit
        XCTAssertEqual(DeparturePlanner.transport(for: info, settings: settings), .publicTransit, "「自動」は普段よく使う移動手段を初めの候補に")
    }

    // MARK: - 計算の流れ

    private struct FakeTravel: TravelTimeProviding {
        var seconds: TimeInterval
        var transitLeave: (Date) -> Date? = { _ in nil }
        var error: TravelTimeError?

        func travelTime(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, transport: TransportMode,
                        departure: Date?, arrival: Date?) async throws -> TravelTime {
            if let error { throw error }
            return TravelTime(seconds: seconds, departure: arrival.flatMap(transitLeave))
        }
    }

    func testCarDepartureUsesTheParkingBufferAndMargin() async throws {
        // 予定開始 10:00・到着目標 10 分前 → 9:50。車 20 分＋駐車 5 分＝25 分、余裕（標準）3 分 → 9:22
        let leave = try await DeparturePlanner.recommendedDeparture(
            from: home.coordinate, to: office.coordinate, transport: .car, start: at(10 * 60), arrivalTargetMinutes: 10,
            margin: .standard, now: at(7 * 60), travel: FakeTravel(seconds: 20 * 60), calendar: calendar)
        XCTAssertEqual(leave, at(9 * 60 + 22))
    }

    func testTransitLooksForATrainArrivingBeforeTheTargetMinusTheMargin() async throws {
        // 到着目標 10:00。乗車 40 分 → 余裕（標準）4 分 → 9:56 までに着く便の出発時刻
        var asked: Date?
        let travel = FakeTravel(seconds: 40 * 60, transitLeave: { arrival in
            asked = arrival
            return arrival.addingTimeInterval(-50 * 60 + 30)
        })
        let leave = try await DeparturePlanner.recommendedDeparture(
            from: home.coordinate, to: office.coordinate, transport: .publicTransit, start: at(10 * 60), arrivalTargetMinutes: 0,
            margin: .standard, now: at(7 * 60), travel: travel, calendar: calendar)
        XCTAssertEqual(asked, at(9 * 60 + 56), "安全マージンを乗車時間に足さず、到着目標を前倒しして便を探す（§8.3）")
        XCTAssertEqual(leave, at(9 * 60 + 6), "出発時刻は分の頭にそろえる")
    }

    func testErrorsAreReported() async {
        do {
            _ = try await DeparturePlanner.recommendedDeparture(
                from: home.coordinate, to: office.coordinate, transport: .bicycle, start: at(10 * 60), arrivalTargetMinutes: 0,
                margin: .standard, now: at(7 * 60), travel: FakeTravel(seconds: 0, error: .bicycleUnsupported), calendar: calendar)
            XCTFail("自転車ルートを使えない iOS では計算できない")
        } catch {
            XCTAssertEqual(error as? TravelTimeError, .bicycleUnsupported)
        }
    }

    // MARK: - 原因の文言・設定（2026-10-14 決定）

    func testProblemMessages() {
        XCTAssertEqual(DepartureProblem.placeUnconfirmed.message, "場所を確認してください")
        XCTAssertEqual(DepartureProblem.transitUnavailable.message, "公共交通ルートを取得できません")
        XCTAssertEqual(DepartureProblem.bicycleUnsupported.message, "このiOSでは自転車ルートを計算できません")
        XCTAssertEqual(DepartureProblem.failed.message, "出発時刻を計算できません")
    }

    func testSettingsDefaultsAndOldFiles() throws {
        let settings = try JSONDecoder().decode(DepartureSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.marginLevel, .standard, "出発の余裕の初期値は「標準」")
        XCTAssertNil(settings.home)
        XCTAssertNil(settings.firstEventOrigin)
        XCTAssertNil(settings.usualTransport)
        XCTAssertFalse(settings.askedUsualTransport)
    }

    func testPlaceBookRemembersConfirmedPlaces() {
        var book = PlaceBook()
        XCTAssertNil(book.place(for: "A社"), "文字だけの場所は、確かめるまで地点がない（Q66）")
        book.confirm(office, for: " A社 ")
        XCTAssertEqual(book.place(for: "A社"), office, "一度確かめた場所の文字と地点の対応は覚えておく（追加仕様書 §23.1）")
        XCTAssertNil(book.place(for: "  "))
    }
}
