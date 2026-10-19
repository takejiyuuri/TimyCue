import XCTest
@testable import TimyCue

/// 作成画面を開いているあいだに連携の状態が変わったとき（連携 OFF・iPhone の許可がなくなった・連携した）、保存先を黙って変えない
/// （2026-10-19 ユーザー指示「S2・S3・S6 の確認結果と TestFlight 配信指示」3）。実際に書く先は、画面に出していたものか、確かめたものと同じ
@MainActor
final class EditorLinkChangeTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private let defaultCalendar = CalendarChoice(id: "default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)

    private func rules(_ kind: SaveTargetKind, hidden: Set<String> = [], systemDefault: String? = "home") -> SaveTargetRules {
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = kind
        preferences.hiddenCalendarIDs = hidden
        return SaveTargetRules(calendars: [defaultCalendar, home, work], preferences: preferences, systemDefaultID: systemDefault)
    }

    private struct Setup {
        let store: ScheduleEditorStore
        let local: InMemoryEventRepository
        let apple: InMemoryEventRepository
        let switchable: SwitchableEventRepository
    }

    /// アプリと同じ形：連携中は Apple とこの iPhone の両方、連携していないときはこの iPhone の中だけを見る
    private func makeSetup(apple events: [CalendarEvent] = [], linked rules: SaveTargetRules?) -> Setup {
        let local = InMemoryEventRepository()
        let apple = InMemoryEventRepository(events: events)
        let initial: EventRepository = rules == nil ? local : CombinedEventRepository(primary: apple, local: local)
        let switchable = SwitchableEventRepository(initial)
        let store = ScheduleEditorStore(repository: switchable, metadataRepository: InMemoryEventMetadataRepository())
        store.receiveLink(rules, status: rules == nil ? .off : .linked)
        return Setup(store: store, local: local, apple: apple, switchable: switchable)
    }

    /// アプリと同じ順：保存先を切り替え、読み直してから、連携の知らせを渡す
    private func unlink(_ setup: Setup, status: AppleLinkStatus) {
        setup.switchable.use(setup.local)
        setup.store.refresh()
        setup.store.receiveLink(nil, status: status)
    }

    private func link(_ setup: Setup, _ rules: SaveTargetRules) {
        setup.switchable.use(CombinedEventRepository(primary: setup.apple, local: setup.local))
        setup.store.refresh()
        setup.store.receiveLink(rules, status: .linked)
    }

    private func fill(_ store: ScheduleEditorStore) {
        store.content.title = "A社"
        store.setStartMinute(600)
    }

    // MARK: - 連携が外れた（新規）

    func testAnAppleTargetIsNotSilentlySwitchedWhenTheLinkIsTurnedOff() throws {
        let setup = makeSetup(linked: rules(.appleCalendar))
        let store = setup.store
        store.startNew(on: day)
        fill(store)
        XCTAssertEqual(store.calendarRowValue, "iPhoneの既定（家）")

        unlink(setup, status: .off)
        XCTAssertEqual(store.lostAppleTargetName, "iPhoneの既定（家）")
        XCTAssertTrue(store.showsCalendarRow, "実際の保存先が見えるように行を出したまま")
        XCTAssertEqual(store.calendarRowValues, ["iPhoneの既定（家）（保存できません）", "保存できません"], "黙って TimyCue のみと出さない")
        XCTAssertFalse(store.isLocked(.calendar), "行で TimyCue のみを選べる")
        XCTAssertEqual(store.calendarRowChoices, [.timyCueOnly])
        XCTAssertTrue(store.calendarRowNote?.contains("連携が OFF です") ?? false)
        let prompt = try XCTUnwrap(store.linkLossPrompt, "保存の前に確かめる")
        XCTAssertTrue(prompt.contains("「iPhoneの既定（家）」"))
        XCTAssertTrue(prompt.contains("連携が OFF です"))
        XCTAssertTrue(prompt.hasSuffix("TimyCue のみ（このiPhone）に保存しますか？"))
        XCTAssertThrowsError(try store.save(), "確かめずに保存しようとしても書かない（最後の守り）") { error in
            XCTAssertEqual(error as? ScheduleEditorError, .needsLinkLossConfirmation)
        }
        XCTAssertTrue(setup.local.allEvents().isEmpty, "確かめるまで、どこにも書かない")
        XCTAssertTrue(setup.apple.allEvents().isEmpty)

        // 「TimyCue のみ（このiPhone）に保存」：はっきり選んでから保存する
        store.chooseSaveTarget(.timyCueOnly)
        XCTAssertNil(store.lostAppleTargetName)
        XCTAssertNil(store.linkLossPrompt)
        XCTAssertEqual(store.calendarRowValue, "TimyCue のみ（このiPhone）")
        try store.save()
        XCTAssertEqual(setup.local.allEvents().count, 1)
        XCTAssertTrue(setup.apple.allEvents().isEmpty)
        XCTAssertNil(setup.local.allEvents().first?.savedOnDeviceWhileLinked, "連携していないときの保存なので、印は付けない（Q104）")
    }

    func testTheShownAppleCalendarIsUsedWhenTheLinkComesBackBeforeSaving() throws {
        let setup = makeSetup(linked: rules(.timyCueOnly))
        let store = setup.store
        store.startNew(on: day)
        fill(store)
        store.chooseSaveTarget(.calendar("work"))
        XCTAssertEqual(store.calendarRowValue, "仕事")

        unlink(setup, status: .needsPermission)
        XCTAssertEqual(store.calendarRowValue, "仕事（保存できません）")
        XCTAssertTrue(store.linkLossPrompt?.contains("カレンダーの許可がありません") ?? false, "許可がなくなったときの理由")

        link(setup, rules(.timyCueOnly))
        XCTAssertNil(store.lostAppleTargetName)
        XCTAssertNil(store.linkLossPrompt)
        XCTAssertEqual(store.calendarRowValue, "仕事", "連携が戻ったら、画面に出していた保存先へ保存する")
        try store.save()
        XCTAssertEqual(setup.apple.allEvents().map(\.calendarID), ["work"])
        XCTAssertTrue(setup.local.allEvents().isEmpty)
    }

    func testTimyCueOnlyAndUndecidedTargetsNeedNoConfirmationWhenTheLinkIsLost() throws {
        let setup = makeSetup(linked: rules(.timyCueOnly))
        let store = setup.store
        store.startNew(on: day)
        fill(store)
        unlink(setup, status: .off)
        XCTAssertNil(store.lostAppleTargetName)
        XCTAssertNil(store.linkLossPrompt, "TimyCue のみと出していたので、確かめずにこの iPhone の中へ保存する")
        XCTAssertTrue(store.showsCalendarRow)
        XCTAssertEqual(store.calendarRowValue, "TimyCue のみ（このiPhone）")
        XCTAssertTrue(store.isLocked(.calendar), "連携していないので選べない（閲覧専用）")
        try store.save()
        XCTAssertEqual(setup.local.allEvents().count, 1)
        XCTAssertTrue(setup.apple.allEvents().isEmpty)

        let undecided = makeSetup(linked: rules(.askBeforeSaving))
        undecided.store.startNew(on: day)
        fill(undecided.store)
        XCTAssertTrue(undecided.store.needsFirstSaveTargetChoice)
        unlink(undecided, status: .off)
        XCTAssertNil(undecided.store.linkLossPrompt, "Apple の保存先を出していなかった（未選択）")
        XCTAssertFalse(undecided.store.needsFirstSaveTargetChoice, "連携していないときは聞かない")
        XCTAssertEqual(undecided.store.calendarRowValue, "TimyCue のみ（このiPhone）")
        try undecided.store.save()
        XCTAssertEqual(undecided.local.allEvents().count, 1)
        XCTAssertTrue(undecided.apple.allEvents().isEmpty)
    }

    func testAnUnavailableAppleTargetAlsoAsksWhenTheLinkIsLost() throws {
        let setup = makeSetup(linked: rules(.appleCalendar, hidden: ["default"], systemDefault: "default"))
        let store = setup.store
        store.startNew(on: day)
        fill(store)
        XCTAssertNotNil(store.saveTargetPrompt, "連携中は、使えない保存先の選び直し（spec §89.4）")
        unlink(setup, status: .off)
        XCTAssertNil(store.saveTargetPrompt, "連携していないときは選び直しを出さない")
        XCTAssertEqual(store.lostAppleTargetName, "iPhoneの既定（Default）")
        XCTAssertNotNil(store.linkLossPrompt, "Apple の保存先を出していたので、黙って TimyCue のみにしない")
        XCTAssertThrowsError(try store.save())
        XCTAssertTrue(setup.local.allEvents().isEmpty)
    }

    // MARK: - つながった（新規）

    func testTimyCueOnlyIsNotSwitchedToAppleWhenTheLinkTurnsOn() throws {
        let setup = makeSetup(linked: nil)
        let store = setup.store
        store.startNew(on: day)
        XCTAssertFalse(store.showsCalendarRow, "連携していないときは TimyCue のみしかないので出さない")

        link(setup, rules(.appleCalendar))
        XCTAssertEqual(store.content.saveChoice, .timyCueOnly, "黙って Apple へ変えない")
        XCTAssertFalse(store.hasUnsavedChanges, "利用者が変えたのではないので、閉じるときに確かめない")
        XCTAssertTrue(store.showsCalendarRow, "実際の保存先が見えるように行を出す")
        XCTAssertEqual(store.calendarRowValue, "TimyCue のみ（このiPhone）")
        XCTAssertEqual(store.selectedSaveChoice, .timyCueOnly)
        XCTAssertFalse(store.isLocked(.calendar), "行で Apple カレンダーを選び直せる")
        fill(store)
        try store.save()
        XCTAssertTrue(setup.apple.allEvents().isEmpty, "Apple へは書かない")
        XCTAssertEqual(setup.local.allEvents().first?.savedOnDeviceWhileLinked, true, "連携中に TimyCue のみで保存した印（Q104）")
    }

    func testSettingsChangesWhileStillLinkedDoNotPinTheTarget() {
        let setup = makeSetup(linked: rules(.appleCalendar))
        let store = setup.store
        store.startNew(on: day)
        store.receiveLink(rules(.timyCueOnly), status: .linked)
        XCTAssertNil(store.content.saveChoice, "連携のまま設定が変わっただけなら、予定ごとの選びは作らない（既定に従う）")
        XCTAssertFalse(store.linkChangedWhileEditing)
        XCTAssertEqual(store.calendarRowValue, "TimyCue のみ（このiPhone）")
    }

    func testANewSessionForgetsTheLinkChange() {
        let setup = makeSetup(linked: rules(.appleCalendar))
        let store = setup.store
        store.startNew(on: day)
        fill(store)
        unlink(setup, status: .off)
        XCTAssertNotNil(store.lostAppleTargetName)

        store.startNew(on: day)
        XCTAssertNil(store.lostAppleTargetName, "開き直したら、連携していないときのふつうの新規（TimyCue のみ）")
        XCTAssertFalse(store.linkChangedWhileEditing)
        XCTAssertFalse(store.showsCalendarRow)
        fill(store)
        XCTAssertNil(store.linkLossPrompt)
    }

    // MARK: - Apple の予定の編集・コピー

    func testEditingAnAppleEventSavesNothingAfterTheLinkIsLost() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let setup = makeSetup(apple: [event], linked: rules(.appleCalendar))
        let store = setup.store
        try store.startEditing(eventID: event.id)
        store.content.title = "A社（変更）"

        unlink(setup, status: .off)
        XCTAssertEqual(store.calendarRowValues, ["家（保存できません）", "保存できません"], "所属を出したまま。TimyCue のみとは出さない")
        XCTAssertTrue(store.isLocked(.calendar))
        XCTAssertThrowsError(try store.save()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .appleUnavailable)
        }
        XCTAssertTrue(store.failure?.message.contains("連携が OFF です") ?? false, "保存していない理由を出す")
        XCTAssertTrue(setup.local.allEvents().isEmpty, "この iPhone の中に複製を作らない")
        XCTAssertEqual(setup.apple.allEvents().map(\.title), ["A社"], "Apple の予定は変えない")

        // 連携が戻れば、ふつうに保存できる
        store.dismissFailure()
        link(setup, rules(.appleCalendar))
        XCTAssertEqual(store.calendarRowValue, "家")
        try store.save()
        XCTAssertEqual(setup.apple.allEvents().map(\.title), ["A社（変更）"])
        XCTAssertTrue(setup.local.allEvents().isEmpty)
    }

    func testDeletingOrCancellingACopyAfterTheLinkIsLostStillChangesNothing() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let setup = makeSetup(apple: [event], linked: rules(.appleCalendar))
        let store = setup.store
        try store.startEditing(eventID: event.id)
        unlink(setup, status: .off)

        XCTAssertThrowsError(try store.deleteEditingEvent()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .appleUnavailable)
        }
        XCTAssertTrue(store.failure?.message.contains("削除していません") ?? false, "消していない理由を出す")
        XCTAssertEqual(setup.apple.allEvents().map(\.id), [event.id], "Apple の予定は消さない")
        store.dismissFailure()

        try store.startCopy()
        store.cancelCopy()
        XCTAssertEqual(store.calendarRowValues, ["家（保存できません）", "保存できません"],
                       "コピーをやめて編集に戻っても、TimyCue のみとは出さない")
        XCTAssertThrowsError(try store.save()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .appleUnavailable)
        }
        XCTAssertTrue(setup.local.allEvents().isEmpty, "この iPhone の中に複製を作らない")
    }

    func testACopyOfAnAppleEventAfterTheLinkIsLostAsksBeforeSaving() throws {
        let event = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "work")
        let setup = makeSetup(apple: [event], linked: rules(.appleCalendar))
        let store = setup.store
        try store.startEditing(eventID: event.id)
        unlink(setup, status: .off)
        try store.startCopy()
        let target = day.adding(days: 7)
        store.toggleCopyDestination(target)
        store.setStartMinute(600, on: target)
        XCTAssertEqual(store.lostAppleTargetName, "仕事", "コピーは元の予定の保存先から始まる（Q97）。保存できないので確かめる")
        XCTAssertEqual(store.calendarRowValue, "仕事（保存できません）")
        XCTAssertNotNil(store.linkLossPrompt)
        XCTAssertThrowsError(try store.save())
        XCTAssertTrue(setup.local.allEvents().isEmpty)

        store.chooseSaveTarget(.timyCueOnly)
        try store.save()
        XCTAssertEqual(setup.local.allEvents().map(\.day), [target])
        XCTAssertEqual(setup.apple.allEvents().count, 1, "元の Apple の予定はそのまま")
    }

    func testMovingToAppleAfterTheLinkIsLostTellsWhy() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let setup = makeSetup(linked: rules(.appleCalendar))
        try setup.local.insert([localEvent])
        let store = setup.store
        store.refresh()
        try store.startEditing(eventID: localEvent.id)
        XCTAssertTrue(store.canMoveToAppleCalendar)

        unlink(setup, status: .off)
        XCTAssertFalse(store.canMoveToAppleCalendar, "連携していないときは「Apple Calendarに保存」を出さない")
        XCTAssertThrowsError(try store.moveToAppleCalendar()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .appleUnavailable)
        }
        XCTAssertTrue(store.failure?.message.contains("Apple Calendarには作っていません") ?? false)
        XCTAssertEqual(setup.local.allEvents().map(\.id), [localEvent.id], "元の予定はそのまま")
        XCTAssertTrue(setup.apple.allEvents().isEmpty)
    }

    // MARK: - 理由の言い方（文言は仮）

    func testTheReasonsTellOffFromMissingPermission() {
        XCTAssertEqual(AppleLinkStatus.off.saveUnavailableReason, "連携が OFF です")
        XCTAssertEqual(AppleLinkStatus.needsPermission.saveUnavailableReason, "カレンダーの許可がありません")
        XCTAssertEqual(AppleLinkStatus.notLinked.saveUnavailableReason, "カレンダーの許可がありません")
        XCTAssertEqual(AppleLinkStatus.unavailable.saveUnavailableReason, "この端末では Apple カレンダーを使えません")
    }
}
