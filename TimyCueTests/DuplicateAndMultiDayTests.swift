import XCTest
@testable import TimyCue

/// 重複候補（Q42-8・Q50）と、複数日登録と繰り返しを併用しないこと（Q49）
final class DuplicateAndMultiDayTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 12)

    // MARK: - 重複候補（Q50）

    func testCandidatesNeedTheSameDayAndStartTime() {
        let local = CalendarEvent(day: day, startMinute: 600, title: "A社")
        let sameTime = CalendarEvent(day: day, startMinute: 600, title: "A社打合せ", source: .appleCalendar)
        let otherTime = CalendarEvent(day: day, startMinute: 630, title: "A社", source: .appleCalendar)
        let otherDay = CalendarEvent(day: day.adding(days: 1), startMinute: 600, title: "A社", source: .appleCalendar)

        let found = DuplicateCandidates.find(local: [local], apple: [sameTime, otherTime, otherDay], keptBoth: [])
        XCTAssertEqual(found.map(\.apple.id), [sameTime.id], "日付＋開始時刻が完全に一致する組だけ（名前が同じでも時刻が違えば候補にしない）")

        let kept = DuplicateCandidates.find(local: [local], apple: [sameTime], keptBoth: [found[0].id])
        XCTAssertTrue(kept.isEmpty, "「両方残す」を選んだ組は、もう聞かない")
    }

    func testAllDayEventsOnTheSameDayAreCandidates() {
        let local = CalendarEvent(day: day, startMinute: 0, title: "休み", isAllDay: true)
        let apple = CalendarEvent(day: day, startMinute: 0, title: "休暇", isAllDay: true, source: .appleCalendar)
        let timedAtMidnight = CalendarEvent(day: day, startMinute: 0, title: "夜間", source: .appleCalendar)
        let found = DuplicateCandidates.find(local: [local], apple: [apple, timedAtMidnight], keptBoth: [])
        XCTAssertEqual(found.map(\.apple.id), [apple.id], "終日どうしは同じ日なら候補。0:00 の時間指定とは別")
    }

    func testTimyCueSettingsAreCarriedOverWithoutOverwritingOnConflict() {
        var localSettings = TimyCueEventMetadata()
        localSettings.arrivalTargetMinutes = 15
        localSettings.transport = .car
        var appleAuto = TimyCueEventMetadata()
        appleAuto.color = .mint   // Apple カレンダーの色から自動で付いただけ
        var appleSettings = TimyCueEventMetadata()
        appleSettings.arrivalTargetMinutes = 30

        XCTAssertFalse(DuplicateCandidates.hasUserSettings(appleAuto), "色だけならユーザーの設定とみなさない")
        XCTAssertEqual(DuplicateCandidates.mergedMetadata(local: localSettings, apple: appleAuto, preferLocal: nil), localSettings,
                       "ローカル予定の設定を Apple の予定へ引き継ぐ")
        XCTAssertTrue(DuplicateCandidates.settingsConflict(local: localSettings, apple: appleSettings),
                      "両方に設定があって違うときは、勝手に上書きせず確かめる")
        XCTAssertEqual(DuplicateCandidates.mergedMetadata(local: localSettings, apple: appleSettings, preferLocal: false), appleSettings)
        XCTAssertEqual(DuplicateCandidates.mergedMetadata(local: localSettings, apple: appleSettings, preferLocal: true), localSettings)
        XCTAssertEqual(DuplicateCandidates.mergedMetadata(local: nil, apple: appleSettings, preferLocal: nil), appleSettings)
    }

    func testOldPreferencesWithoutDuplicateFieldsStillLoad() throws {
        let preferences = try JSONDecoder().decode(CalendarPreferences.self, from: Data(#"{"hiddenCalendarIDs":[]}"#.utf8))
        XCTAssertNil(preferences.keptBothDuplicates)
        XCTAssertNil(preferences.notifiedDuplicates)
    }
}
