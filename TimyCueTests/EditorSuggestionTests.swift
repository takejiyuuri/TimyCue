import XCTest
@testable import TimyCue

@MainActor
final class EditorSuggestionTests: XCTestCase {
    private let today = CalendarDay(year: 2026, month: 10, day: 12)

    private func event(_ title: String, daysAgo: Int, place: String? = nil, start: MinuteOfDay = 600,
                       duration: Int? = 60) -> CalendarEvent {
        CalendarEvent(day: today.adding(days: -daysAgo), startMinute: start, durationMinutes: duration,
                      title: title, locationName: place)
    }

    private func makeStore(_ events: [CalendarEvent], metadata: [UUID: TimyCueEventMetadata] = [:]) -> ScheduleEditorStore {
        ScheduleEditorStore(repository: InMemoryEventRepository(events: events),
                            metadataRepository: InMemoryEventMetadataRepository(metadata: metadata))
    }

    // MARK: - 予定名の候補（§47）

    func testTitleSuggestionsPreferSameNameThenNewest() {
        let store = makeStore([
            event("A社打合せ", daysAgo: 20, place: "広島市中区"),
            event("A社定例", daysAgo: 3, place: "本社"),
            event("A社打合せ", daysAgo: 7, place: "広島市中区"),
            event("A社打合せ", daysAgo: 14, place: "福山"),
            event("B社", daysAgo: 1),
            event("A社見積", daysAgo: 2),
        ])
        store.startNew(on: today)
        XCTAssertTrue(store.titleSuggestions().isEmpty, "何も入れていなければ出さない")

        store.content.title = "A社打合せ"
        let suggestions = store.titleSuggestions()
        XCTAssertLessThanOrEqual(suggestions.count, 3, "最大 2〜3 件（§47）")
        XCTAssertEqual(suggestions.map(\.title), ["A社打合せ", "A社打合せ"])
        XCTAssertEqual(suggestions.map(\.locationName), ["広島市中区", "福山"],
                       "新しい順。名前と場所が同じものは 1 つにまとめる")

        store.content.title = "a社"
        XCTAssertEqual(store.titleSuggestions().count, 3, "大文字小文字を区別せず、似た名前も")
    }

    func testChoosingSuggestionDoesNotApplyEverythingByItself() {
        let past = event("A社打合せ", daysAgo: 7, place: "広島市中区")
        var info = TimyCueEventMetadata()
        info.color = .mint
        info.arrivalTargetMinutes = 10
        info.transport = .car
        let store = makeStore([past], metadata: [past.id: info])
        store.startNew(on: today)
        store.content.title = "A社"
        let suggestion = store.titleSuggestions()[0]

        store.useTitle(of: suggestion)
        XCTAssertEqual(store.content.title, "A社打合せ")
        XCTAssertNil(store.content.locationName, "勝手にすべて確定しない（§47）")
        XCTAssertEqual(store.content.metadata.transport, .auto)

        store.useSettings(of: suggestion)
        XCTAssertEqual(store.content.locationName, "広島市中区", "選んだときだけ場所・色・到着目標・移動手段も使う")
        XCTAssertEqual(store.content.metadata.color, .mint)
        XCTAssertEqual(store.content.metadata.arrivalTargetMinutes, 10)
        XCTAssertEqual(store.content.metadata.transport, .car)
    }

    // MARK: - 場所の候補（§48・§49）

    func testPlaceCandidates() {
        let store = makeStore([
            event("A社打合せ", daysAgo: 30, place: "広島市中区"),
            event("歯医者", daysAgo: 20, place: "見本クリニック"),
            event("歯医者", daysAgo: 10, place: "見本クリニック"),
            event("現場", daysAgo: 5, place: "見本ビル"),
            event("A社打合せ", daysAgo: 2, place: "本社"),
        ])
        store.startNew(on: today)
        store.content.title = "A社打合せ"
        let candidates = store.placeCandidates()
        XCTAssertEqual(candidates.first, PlaceCandidate(name: "本社", kind: .previous), "同じ予定名の前回の場所")
        XCTAssertTrue(candidates.contains(PlaceCandidate(name: "見本クリニック", kind: .frequent)), "よく使う場所")
        XCTAssertTrue(candidates.contains(PlaceCandidate(name: "見本ビル", kind: .recent)), "最近使った場所")
        XCTAssertEqual(Set(candidates.map(\.name)).count, candidates.count, "同じ場所は 1 回だけ")
    }

    func testChoosingPastPlaceDoesNotRewriteArrivalTargetOrTransport() {
        let past = event("現場", daysAgo: 5, place: "見本ビル")
        var info = TimyCueEventMetadata()
        info.arrivalTargetMinutes = 15
        info.transport = .publicTransit
        let store = makeStore([past], metadata: [past.id: info])

        store.startNew(on: today)
        store.choosePlace("見本ビル")
        XCTAssertEqual(store.content.locationName, "見本ビル")
        XCTAssertNil(store.content.metadata.arrivalTargetMinutes, "その場所で前回使った到着目標は入れない（全体既定値のまま。Q70・Q75）")
        XCTAssertEqual(store.content.metadata.transport, .auto, "「自動」は「自動」のまま。画面の設定を勝手に変えない（Q75）")

        store.startNew(on: today)
        store.content.metadata.arrivalTargetMinutes = 5
        store.content.metadata.transport = .walk
        store.choosePlace("見本ビル")
        XCTAssertEqual(store.content.metadata.arrivalTargetMinutes, 5, "今回決めた到着目標はそのまま")
        XCTAssertEqual(store.content.metadata.transport, .walk, "はっきり指定した移動手段は上書きしない（Q75）")

        store.choosePlace(nil)
        XCTAssertNil(store.content.locationName, "場所なし")
    }

    // MARK: - 予定の重なり（§58）

    func testOverlapWarning() {
        let others = [CalendarEvent(day: today, startMinute: 600, durationMinutes: 60, title: "A")]
        XCTAssertEqual(ScheduleEditorStore.warnings(start: 630, end: nil, others: others), [.overlap], "予定が重複")
        XCTAssertEqual(ScheduleEditorStore.warnings(start: 540, end: 610, others: others), [.overlap])
        XCTAssertEqual(ScheduleEditorStore.warnings(start: 660, end: 700, others: others), [], "ちょうど終わってから始まるなら重ならない")
        XCTAssertEqual(ScheduleWarning.overlap.message, "予定が重複")
    }

    func testPreviousEndUnknownWarning() {
        let others = [CalendarEvent(day: today, startMinute: 600, title: "終了なし")]
        XCTAssertEqual(ScheduleEditorStore.warnings(start: 615, end: nil, others: others), [.previousEndUnknown],
                       "終了の分からない予定を 15 分の予定とは見なさず、「前の予定の終了時刻未設定」（§58・Q15）")
        XCTAssertEqual(ScheduleEditorStore.warnings(start: 600, end: nil, others: others), [.overlap], "同じ時刻に始まるなら重複")
        XCTAssertEqual(ScheduleWarning.previousEndUnknown.message, "前の予定の終了時刻未設定")
    }

    func testWarningsDoNotBlockSaving() throws {
        let other = CalendarEvent(day: today, startMinute: 600, durationMinutes: 60, title: "A")
        let store = makeStore([other])
        store.startNew(on: today)
        store.content.title = "B"
        store.setStartMinute(630)
        XCTAssertEqual(store.warnings(on: today), [.overlap])
        XCTAssertEqual(try store.save().count, 1, "警告があっても保存できる（Soft Constraint）")
    }

    func testCustomNotificationLabels() {
        XCTAssertEqual(NotificationTiming.beforeDeparture(minutes: 45).fullLabel, "出発45分前")
        XCTAssertEqual(NotificationTiming.beforeStart(minutes: 15).fullLabel, "予定開始15分前", "Q7")
    }
}
