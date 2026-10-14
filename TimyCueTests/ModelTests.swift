import XCTest
@testable import TimyCue

final class ModelTests: XCTestCase {
    func testCalendarDayOrderingAndMonthBoundary() {
        let oct31 = CalendarDay(year: 2026, month: 10, day: 31)
        let nov1 = oct31.adding(days: 1)
        XCTAssertEqual(nov1, CalendarDay(year: 2026, month: 11, day: 1))
        XCTAssertLessThan(oct31, nov1)
        XCTAssertEqual(nov1.shortLabel, "11/1")
    }

    func testCalendarDayRoundTripsThroughDate() {
        let day = CalendarDay(year: 2026, month: 10, day: 12)
        XCTAssertEqual(CalendarDay(day.date(atMinute: 14 * 60 + 17)), day)
    }

    func testTimeText() {
        XCTAssertEqual(TimeText.hourMinute(857), "14:17")
        XCTAssertEqual(TimeText.hourMinute(0), "0:00")
    }

    // MARK: - 表示に使う名前（Q3）

    func testDisplayTitleFallsBackToPlaceThenGeneric() {
        let day = CalendarDay(year: 2026, month: 10, day: 12)
        var event = CalendarEvent(day: day, startMinute: 600, title: "", source: .appleCalendar)
        XCTAssertEqual(event.displayTitle, "予定", "予定名も場所もなければ汎用の表示")
        event.locationName = "広島駅"
        XCTAssertEqual(event.displayTitle, "広島駅", "予定名がなければ場所名")
        event.title = "病院"
        XCTAssertEqual(event.displayTitle, "病院", "予定名がいちばん優先")
    }

    // MARK: - 通知（仕様 §17）

    func testNotificationSummary() {
        XCTAssertEqual(NotificationPreference().summary, "30分・10分・出発")
        XCTAssertEqual(NotificationPreference.off.summary, "通知なし")
        XCTAssertTrue(NotificationPreference.off.isOff)

        let mixed = NotificationPreference(timings: [
            .atDeparture,
            .beforeStart(minutes: 15),
            .beforeDeparture(minutes: 10),
            .beforeDeparture(minutes: 60),
        ])
        XCTAssertEqual(mixed.summary, "60分・10分・出発・開始15分前",
                       "出発の早い順 → 出発 → 開始前。開始基準は「開始○分前」と書く（Q7・2026-10-14 決定 C3）")
    }

    func testNotificationsFollowWhetherTheEventHasAPlace() {
        XCTAssertEqual(NotificationTiming.presets(hasPlace: false).map(\.fullLabel),
                       ["開始60分前", "開始30分前", "開始10分前", "予定開始"],
                       "場所なしの予定は出発の候補を出さない（2026-10-14 決定 C3）")
        XCTAssertEqual(NotificationTiming.presets(hasPlace: true), NotificationTiming.presets)

        let chosen = NotificationPreference(timings: [.beforeDeparture(minutes: 60), .atDeparture])
        let withoutPlace = chosen.converted(hasPlace: false)
        XCTAssertEqual(withoutPlace.timings, [.beforeStart(minutes: 60), .atStart],
                       "場所を消したら、出発60分前→開始60分前、出発時刻→予定開始（初めの値に戻さない）")
        XCTAssertEqual(withoutPlace.converted(hasPlace: true), chosen, "場所を足したら逆に置き換える")
        XCTAssertTrue(NotificationPreference.off.converted(hasPlace: false).isOff, "通知なしは通知なしのまま")
        XCTAssertEqual(NotificationPreference.noPlaceDefault.timings,
                       [.beforeStart(minutes: 30), .beforeStart(minutes: 10), .atStart],
                       "場所なしの新しい予定の初期値は 開始30分前・開始10分前・予定開始")
    }

    func testNotificationPresetsAreTheFixedCandidates() {
        XCTAssertEqual(NotificationTiming.presets, [
            .beforeDeparture(minutes: 60),
            .beforeDeparture(minutes: 30),
            .beforeDeparture(minutes: 10),
            .atDeparture,
            .atStart,
        ], "出発60分前・出発30分前・出発10分前・出発時刻・予定開始（ほかに「通知なし」。vNext §11.1）")
        XCTAssertEqual(NotificationTiming.presets.map(\.fullLabel),
                       ["出発60分前", "出発30分前", "出発10分前", "出発時刻", "予定開始"])
    }

    func testNoNotificationIsExclusive() {
        var preference = NotificationPreference.off
        XCTAssertTrue(preference.isOff, "「通知なし」を選ぶと、ほかは全部オフ（vNext §11.1）")
        preference.timings.insert(.atStart)
        XCTAssertFalse(preference.isOff, "ほかを 1 つでもオンにしたら「通知なし」ではなくなる")
        XCTAssertEqual(preference.summary, "予定開始")
    }

    func testOldCustomNotificationStillLoads() throws {
        let old = NotificationPreference(timings: [.beforeStart(minutes: 15), .atDeparture])
        let reloaded = try JSONDecoder().decode(NotificationPreference.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(reloaded, old, "カスタムの通知はやめたが、前の版で保存したものは読める")
        let withStart = NotificationPreference(timings: [.atStart, .beforeDeparture(minutes: 10)])
        XCTAssertEqual(try JSONDecoder().decode(NotificationPreference.self, from: JSONEncoder().encode(withStart)), withStart)
        XCTAssertEqual(withStart.summary, "10分・予定開始")
    }

    // MARK: - 移動手段・ルート（仕様 §50・§52）

    func testTransportChoices() {
        XCTAssertEqual(TransportMode.allCases.map(\.displayName), ["自動", "車", "徒歩", "自転車", "公共交通"])
        XCTAssertEqual(TimyCueEventMetadata().transport, .auto)
    }

    func testRouteChoices() {
        XCTAssertEqual(RouteOption.allCases.map(\.displayName), ["自動", "高速優先", "一般道優先"])
    }

    // MARK: - 予定の中身とコピー（仕様 §63・§69・§84）

    func testEndMinuteIsNilWithoutDuration() {
        let event = CalendarEvent(day: CalendarDay(year: 2026, month: 10, day: 12), startMinute: 600, title: "A社")
        XCTAssertNil(event.endMinute, "終了未設定を仮の終了と取り違えない（仕様 §69）")
    }

    func testContentRoundTripsThroughEventAndMetadata() {
        let day = CalendarDay(year: 2026, month: 10, day: 12)
        var content = EventContent()
        content.title = "A社打合せ"
        content.locationName = "広島市中区"
        content.notes = "Apple カレンダーのメモ"
        content.metadata.color = .mint
        content.metadata.transport = .car
        content.metadata.route = .preferHighway

        let event = content.makeEvent(day: day, startMinute: 600, durationMinutes: 60)
        XCTAssertEqual(event.title, "A社打合せ")
        XCTAssertEqual(event.notes, "Apple カレンダーのメモ", "メモは消さずに持つ（仕様 §55）")
        XCTAssertEqual(EventContent(event: event, metadata: content.metadata), content)
    }

    func testCopiedContentDropsRepeatOnly() {
        var content = EventContent()
        content.title = "A社打合せ"
        content.metadata.route = .preferLocalRoads
        content.metadata.notifications = .off
        let copy = content.copiedForNewEvent()
        XCTAssertEqual(copy.repeatRule, .none)
        XCTAssertEqual(copy.metadata, content.metadata, "ルート・通知などはコピーする（仕様 §63）")
    }

    // MARK: - 見本の予定

    func testSampleEventsHaveNoPersonalPlaceholders() {
        let samples = SampleEvents.make(around: CalendarDay(year: 2026, month: 10, day: 12))
        XCTAssertFalse(samples.events.isEmpty)
        XCTAssertTrue(samples.events.contains { $0.isAllDay })
        XCTAssertTrue(samples.events.contains { $0.locationName == nil })
        XCTAssertTrue(samples.events.allSatisfy { !$0.title.isEmpty }, "TimyCue で作る予定は予定名が必須（仕様 §46）")
        XCTAssertEqual(Set(samples.metadata.keys), Set(samples.events.map(\.id)), "どの予定にも TimyCue の情報がある")
    }
}
