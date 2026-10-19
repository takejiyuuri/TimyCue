import EventKit
import XCTest
@testable import TimyCue

/// 作成画面（新規・コピー）を開いているあいだに、連携したまま設定（既定の保存先・iPhone の既定・保存先のカレンダーの表示・使えるかどうか）が
/// 変わったとき（spec §89.4・2026-10-19 決定「TestFlight 1.0 (30) 報告への回答」1）。行で選んでいない新しい予定は、実際の書く先が変わったら
/// 覚えて、確かめるまで書かない。行で選んだ・コピー元の保存先は変えない。作成画面の中の操作（初めての確かめ・「表示をONにして保存」）で
/// 変わったときは確かめない。開き直したら記録は消える
@MainActor
final class SaveTargetChangeTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 10, day: 19)
    private let defaultCalendar = CalendarChoice(id: "default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange)
    private let home = CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green)
    private let work = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue)

    private func rules(_ kind: SaveTargetKind = .appleCalendar, settingsDefault: String? = nil, systemDefault: String? = "home",
                       hidden: Set<String> = [], displayOnly: Set<String> = [], calendars: [CalendarChoice]? = nil) -> SaveTargetRules {
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = kind
        preferences.defaultCalendarID = settingsDefault
        preferences.hiddenCalendarIDs = hidden
        displayOnly.forEach { preferences.setHoliday(true, calendarID: $0) }
        return SaveTargetRules(calendars: calendars ?? [defaultCalendar, home, work], preferences: preferences, systemDefaultID: systemDefault)
    }

    private struct Setup {
        let store: ScheduleEditorStore
        let local: InMemoryEventRepository
        let apple: InMemoryEventRepository
    }

    /// アプリと同じ形：連携中は Apple とこの iPhone の両方を見て、連携の知らせ（receiveLink）で保存先の決まりを受ける
    private func makeSetup(apple appleEvents: [CalendarEvent] = [], local localEvents: [CalendarEvent] = [],
                           _ rules: SaveTargetRules) -> Setup {
        let local = InMemoryEventRepository(events: localEvents)
        let apple = InMemoryEventRepository(events: appleEvents)
        let store = ScheduleEditorStore(repository: CombinedEventRepository(primary: apple, local: local),
                                        metadataRepository: InMemoryEventMetadataRepository())
        store.receiveLink(rules, status: .linked)
        return Setup(store: store, local: local, apple: apple)
    }

    /// 新規を開いて、予定名と開始時刻を入れる（保存できる状態）
    private func fill(_ store: ScheduleEditorStore) {
        store.startNew(on: day)
        store.content.title = "A社"
        store.setStartMinute(600)
    }

    /// 連携したまま設定が変わった知らせ（アプリと同じ順：読み直してから知らせを渡す）
    private func change(_ setup: Setup, to rules: SaveTargetRules) {
        setup.store.refresh()
        setup.store.receiveLink(rules, status: .linked)
    }

    // MARK: - 書く先が変わったら覚えて、確かめるまで書かない

    func testAChangedSettingsDefaultIsConfirmedBeforeSaving() throws {
        let setup = makeSetup(rules(settingsDefault: "home"))
        let store = setup.store
        fill(store)
        XCTAssertEqual(store.calendarRowValue, "家")
        XCTAssertNil(store.saveTargetChange)

        change(setup, to: rules(settingsDefault: "work"))
        XCTAssertEqual(store.saveTargetChange, SaveTargetChange(from: .apple("home"), fromName: "家"),
                       "行で選んでいない新しい予定の書く先が変わったことを覚える")
        XCTAssertNil(store.content.saveChoice, "予定ごとの選びは作らない（新しい既定に従う）")
        XCTAssertTrue(store.showsCalendarRow, "行は出したまま")
        XCTAssertEqual(store.calendarRowValue, "仕事", "行には新しい値を出す")
        XCTAssertEqual(store.calendarRowNote, "作成画面を開いたあとに設定が変わり、保存先が「家」から「仕事」になりました。保存するときに確かめます。")
        let prompt = try XCTUnwrap(store.saveTargetChangePrompt, "保存の前に確かめる")
        XCTAssertEqual(prompt.message, "作成画面を開いたあとに設定が変わり、保存先が「家」から「仕事」になりました。「仕事」に保存しますか？")
        XCTAssertEqual(prompt.saveButtonTitle, "「仕事」に保存")
        XCTAssertNil(store.saveTargetPrompt)
        XCTAssertFalse(store.needsFirstSaveTargetChoice)
        XCTAssertNil(store.linkLossPrompt)

        XCTAssertThrowsError(try store.save(), "確かめずに保存しようとしても書かない（最後の守り）") { error in
            XCTAssertEqual(error as? ScheduleEditorError, .needsSaveTargetChangeConfirmation)
        }
        XCTAssertNil(store.failure, "アラートは出さない（保存の前の確かめで聞く）")
        XCTAssertTrue(setup.apple.allEvents().isEmpty, "どこにも書かない")
        XCTAssertTrue(setup.local.allEvents().isEmpty)

        // ［「仕事」に保存］：確かめた新しい先へ書く
        store.confirmSaveTargetChange(prompt)
        XCTAssertNil(store.saveTargetChange)
        XCTAssertNil(store.saveTargetChangePrompt)
        try store.save()
        XCTAssertEqual(setup.apple.allEvents().map(\.calendarID), ["work"])
        XCTAssertTrue(setup.local.allEvents().isEmpty)
    }

    func testAChangedIPhoneDefaultIsConfirmed() throws {
        let setup = makeSetup(rules(systemDefault: "home"))
        let store = setup.store
        fill(store)
        XCTAssertEqual(store.calendarRowValue, "iPhoneの既定（家）")

        change(setup, to: rules(systemDefault: "work"))
        let prompt = try XCTUnwrap(store.saveTargetChangePrompt, "iPhone の既定が変わって書く先が変わったときも確かめる")
        XCTAssertEqual(prompt.fromName, "iPhoneの既定（家）")
        XCTAssertEqual(prompt.toName, "iPhoneの既定（仕事）")
        XCTAssertThrowsError(try store.save())
        XCTAssertTrue(setup.apple.allEvents().isEmpty)

        store.confirmSaveTargetChange(prompt)
        try store.save()
        XCTAssertEqual(setup.apple.allEvents().map(\.calendarID), ["work"])
    }

    /// アプリと同じつなぎ方（CalendarConnection の知らせ）で、iPhone の設定で既定のカレンダーが変わったとき（Apple カレンダー側の変化）
    func testAnIPhoneDefaultChangedInIOSIsNoticedThroughTheConnection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = .appleCalendar
        preferences.formatVersion = CalendarPreferences.currentFormatVersion
        try JSONEncoder().encode(preferences).write(to: directory.appendingPathComponent("calendar-preferences.json"))
        let apple = AppleCalendarStub(calendars: [defaultCalendar, home, work], systemDefaultID: "home")
        let local = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("events.json"), empty: []))
        let switchable = SwitchableEventRepository(local)
        let editor = ScheduleEditorStore(repository: switchable, metadataRepository: InMemoryEventMetadataRepository())
        let connection = CalendarConnection(
            eventStore: EKEventStore(), switchable: switchable, localEvents: local, metadata: InMemoryEventMetadataRepository(),
            preferencesFile: JSONFile(url: directory.appendingPathComponent("calendar-preferences.json"), empty: CalendarPreferences()),
            authorizationStatus: { .fullAccess },
            makeAppleRepository: { _, _ in
                apple.makeCount += 1
                return apple
            },
            onChange: { _, rules, status in
                editor.refresh()
                editor.receiveLink(rules, status: status)
            })
        XCTAssertTrue(connection.isLinked)
        fill(editor)
        XCTAssertEqual(editor.calendarRowValue, "iPhoneの既定（家）")

        apple.systemDefaultCalendarID = "work"
        connection.calendarDidChange()
        let prompt = try XCTUnwrap(editor.saveTargetChangePrompt)
        XCTAssertEqual(prompt.message, "作成画面を開いたあとに設定が変わり、保存先が「iPhoneの既定（家）」から「iPhoneの既定（仕事）」になりました。「iPhoneの既定（仕事）」に保存しますか？")
        XCTAssertThrowsError(try editor.save())
        XCTAssertEqual(apple.writes, 0)
        XCTAssertTrue(local.allEvents().isEmpty)

        editor.confirmSaveTargetChange(prompt)
        try editor.save()
        XCTAssertEqual(apple.storedEvents.map(\.calendarID), ["work"])
        XCTAssertTrue(local.allEvents().isEmpty)
    }

    func testADefaultThatBecomesUnusableUsesTheUsualPromptAndWritesNothing() throws {
        let readOnlyWork = CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: false, color: .saxeBlue)
        let cases: [(label: String, rules: SaveTargetRules, problem: SaveTargetProblem)] = [
            ("表示 OFF", rules(settingsDefault: "work", hidden: ["work"]), .hidden(calendarTitle: "仕事")),
            ("表示のみ", rules(settingsDefault: "work", displayOnly: ["work"]), .displayOnly(calendarTitle: "仕事")),
            ("消えた", rules(settingsDefault: "work", calendars: [defaultCalendar, home]), .notFound),
            ("書き込めない", rules(settingsDefault: "work", calendars: [defaultCalendar, home, readOnlyWork]), .readOnly(calendarTitle: "仕事")),
        ]
        for item in cases {
            let setup = makeSetup(rules(settingsDefault: "work"))
            let store = setup.store
            fill(store)
            change(setup, to: item.rules)
            XCTAssertEqual(store.saveTargetChange?.from, .apple("work"), "\(item.label)：書く先が変わった（使えない）ことを覚える")
            XCTAssertEqual(store.saveTargetProblem, item.problem, item.label)
            XCTAssertTrue(store.showsCalendarRow, item.label)
            XCTAssertTrue(store.calendarRowNote?.hasPrefix("作成画面を開いたあとに設定が変わり、保存先が「仕事」から") ?? false, item.label)
            XCTAssertNil(store.saveTargetChangePrompt, "\(item.label)：使えないときは、今までの保存の前の選び直しだけを出す（重ねない）")
            XCTAssertEqual(store.saveTargetPrompt?.problem, item.problem, item.label)
            XCTAssertThrowsError(try store.save(), item.label)
            XCTAssertTrue(setup.apple.allEvents().isEmpty, "\(item.label)：使えない保存先へも、ほかのカレンダーへも書かない")
            XCTAssertTrue(setup.local.allEvents().isEmpty, item.label)

            // 選び直したら、そのまま書く（変化の確かめは出さない）
            store.dismissFailure()
            store.chooseSaveTarget(.calendar("home"))
            XCTAssertNil(store.saveTargetChange, item.label)
            XCTAssertNil(store.saveTargetChangePrompt, item.label)
            try store.save()
            XCTAssertEqual(setup.apple.allEvents().map(\.calendarID), ["home"], item.label)
        }
    }

    func testTheKindChangingToTimyCueOnlyIsConfirmed() throws {
        let setup = makeSetup(rules(settingsDefault: "work"))
        let store = setup.store
        fill(store)
        change(setup, to: rules(.timyCueOnly, settingsDefault: "work"))
        XCTAssertEqual(store.calendarRowValue, "TimyCue のみ（このiPhone）")
        let prompt = try XCTUnwrap(store.saveTargetChangePrompt)
        XCTAssertEqual(prompt.toName, "TimyCue のみ（このiPhone）")
        XCTAssertEqual(prompt.saveButtonTitle, "TimyCue のみ（このiPhone）に保存")
        XCTAssertEqual(prompt.message, "作成画面を開いたあとに設定が変わり、保存先が「仕事」から「TimyCue のみ（このiPhone）」になりました。TimyCue のみ（このiPhone）に保存しますか？")
        XCTAssertThrowsError(try store.save())
        XCTAssertTrue(setup.local.allEvents().isEmpty, "確かめるまで、この iPhone の中にも書かない")
        XCTAssertTrue(setup.apple.allEvents().isEmpty)

        store.confirmSaveTargetChange(prompt)
        try store.save()
        XCTAssertTrue(setup.apple.allEvents().isEmpty)
        XCTAssertEqual(setup.local.allEvents().first?.savedOnDeviceWhileLinked, true, "連携中に TimyCue のみで保存した印（Q104）")
    }

    func testTheKindChangingToUndecidedUsesTheFirstSaveChoice() throws {
        let setup = makeSetup(rules(settingsDefault: "work"))
        let store = setup.store
        fill(store)
        change(setup, to: rules(.askBeforeSaving))
        XCTAssertEqual(store.saveTargetChange?.from, .apple("work"))
        XCTAssertEqual(store.calendarRowValue, "未選択")
        XCTAssertNil(store.saveTargetChangePrompt, "未選択になったときは、今までの初めての確かめだけを出す（重ねない）")
        XCTAssertTrue(store.needsFirstSaveTargetChoice)
        XCTAssertThrowsError(try store.save()) { error in
            XCTAssertEqual(error as? ScheduleEditorError, .needsSaveTargetChoice)
        }
        XCTAssertTrue(setup.apple.allEvents().isEmpty)
        XCTAssertTrue(setup.local.allEvents().isEmpty)
    }

    // MARK: - 行で選んだ・コピー元の保存先は変えない

    func testRowChoicesAndCopiesAreNotChangedBySettings() throws {
        // 行で選んだ保存先
        let chosen = makeSetup(rules(settingsDefault: "home"))
        fill(chosen.store)
        chosen.store.chooseSaveTarget(.calendar("work"))
        change(chosen, to: rules(settingsDefault: "default"))
        XCTAssertNil(chosen.store.saveTargetChange, "行で選んだ保存先は、設定が変わっても変えない")
        XCTAssertEqual(chosen.store.calendarRowValue, "仕事")
        try chosen.store.save()
        XCTAssertEqual(chosen.apple.allEvents().map(\.calendarID), ["work"])

        // 行で選んだ保存先が使えなくなった：今までどおり保存の前に選び直し（ほかへは書かない）
        let hiddenLater = makeSetup(rules(settingsDefault: "home"))
        fill(hiddenLater.store)
        hiddenLater.store.chooseSaveTarget(.calendar("work"))
        change(hiddenLater, to: rules(settingsDefault: "home", hidden: ["work"]))
        XCTAssertNil(hiddenLater.store.saveTargetChange)
        XCTAssertEqual(hiddenLater.store.saveTargetPrompt?.problem, .hidden(calendarTitle: "仕事"))
        XCTAssertThrowsError(try hiddenLater.store.save())
        XCTAssertTrue(hiddenLater.apple.allEvents().isEmpty)
        XCTAssertTrue(hiddenLater.local.allEvents().isEmpty)

        // コピー元の保存先（Apple の予定）
        let target = day.adding(days: 7)
        let original = CalendarEvent(day: day, startMinute: 600, title: "A社", source: .appleCalendar, calendarID: "home")
        let appleCopy = makeSetup(apple: [original], rules(settingsDefault: "work"))
        try appleCopy.store.startEditing(eventID: original.id)
        try appleCopy.store.startCopy()
        appleCopy.store.toggleCopyDestination(target)
        appleCopy.store.setStartMinute(600, on: target)
        change(appleCopy, to: rules(.timyCueOnly))
        XCTAssertNil(appleCopy.store.saveTargetChange, "コピー元の保存先は、設定が変わっても変えない（Q97）")
        XCTAssertEqual(appleCopy.store.calendarRowValue, "家")
        try appleCopy.store.save()
        XCTAssertEqual(appleCopy.apple.allEvents().filter { $0.day == target }.map(\.calendarID), ["home"])
        XCTAssertTrue(appleCopy.local.allEvents().isEmpty)

        // コピー元の保存先（TimyCue のみの予定）
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let localCopy = makeSetup(local: [localEvent], rules(settingsDefault: "work"))
        try localCopy.store.startEditing(eventID: localEvent.id)
        try localCopy.store.startCopy()
        localCopy.store.toggleCopyDestination(target)
        localCopy.store.setStartMinute(600, on: target)
        change(localCopy, to: rules(settingsDefault: "home"))
        XCTAssertNil(localCopy.store.saveTargetChange)
        try localCopy.store.save()
        XCTAssertTrue(localCopy.apple.allEvents().isEmpty)
        XCTAssertEqual(localCopy.local.allEvents().filter { $0.day == target }.count, 1)
    }

    // MARK: - 変化に数えないもの・記録が消えるとき

    func testOnlyARenamedCalendarIsNotAChange() throws {
        let renamed = CalendarChoice(id: "home", title: "自宅", sourceTitle: "iCloud", isWritable: true, color: .green)
        let setup = makeSetup(rules(settingsDefault: "home"))
        fill(setup.store)
        change(setup, to: rules(settingsDefault: "home", calendars: [defaultCalendar, renamed, work]))
        XCTAssertNil(setup.store.saveTargetChange, "同じカレンダーの名前が変わっただけは、変化に数えない")
        XCTAssertEqual(setup.store.calendarRowValue, "自宅")
        XCTAssertNil(setup.store.saveTargetChangePrompt)
        try setup.store.save()
        XCTAssertEqual(setup.apple.allEvents().map(\.calendarID), ["home"])

        // iPhone の既定として使っていたカレンダーを、設定ではっきり選んだ形に変えただけ（書く先のカレンダーは同じ）
        let same = makeSetup(rules(systemDefault: "home"))
        fill(same.store)
        change(same, to: rules(settingsDefault: "home", systemDefault: "home"))
        XCTAssertNil(same.store.saveTargetChange, "書く先のカレンダーが同じなら確かめない")
        // 何も変わらない知らせ（読み直しのたびの知らせ）でも確かめない
        change(same, to: rules(settingsDefault: "home", systemDefault: "home"))
        XCTAssertNil(same.store.saveTargetChange)
        try same.store.save()
        XCTAssertEqual(same.apple.allEvents().map(\.calendarID), ["home"])
    }

    func testReturningToTheFirstTargetClearsTheChange() throws {
        let setup = makeSetup(rules(settingsDefault: "home"))
        let store = setup.store
        fill(store)
        change(setup, to: rules(settingsDefault: "work"))
        change(setup, to: rules(settingsDefault: "default"))
        XCTAssertEqual(store.saveTargetChange, SaveTargetChange(from: .apple("home"), fromName: "家"),
                       "変わる前は、開いたときの保存先のまま")
        XCTAssertEqual(store.saveTargetChangePrompt?.toName, "Default", "今の書く先で確かめる")

        change(setup, to: rules(settingsDefault: "home"))
        XCTAssertNil(store.saveTargetChange, "開いたときの保存先に戻ったら、確かめない")
        XCTAssertTrue(store.showsCalendarRow, "行は出したまま")
        try store.save()
        XCTAssertEqual(setup.apple.allEvents().map(\.calendarID), ["home"])
    }

    func testAConfirmationForAnOlderTargetDoesNotWriteToANewerOne() throws {
        let setup = makeSetup(rules(settingsDefault: "home"))
        let store = setup.store
        fill(store)
        change(setup, to: rules(settingsDefault: "work"))
        let prompt = try XCTUnwrap(store.saveTargetChangePrompt)

        // 確かめているあいだに、また変わった
        change(setup, to: rules(settingsDefault: "default"))
        store.confirmSaveTargetChange(prompt)
        XCTAssertNotNil(store.saveTargetChange, "確かめた「仕事」と今の書く先が違うので、確かめたことにしない")
        XCTAssertThrowsError(try store.save())
        XCTAssertTrue(setup.apple.allEvents().isEmpty, "確かめた先と違う先には書かない")
        XCTAssertEqual(store.saveTargetChangePrompt?.toName, "Default", "今の書く先で、もう一度確かめる")
    }

    func testChoosingInTheRowClearsTheChange() throws {
        let setup = makeSetup(rules(settingsDefault: "home"))
        let store = setup.store
        fill(store)
        change(setup, to: rules(settingsDefault: "work"))
        // 確かめの「ほかの保存先を選ぶ」：「カレンダー」の行を開く
        store.openCalendarRow()
        XCTAssertEqual(store.expandedRow, .calendar)
        store.chooseSaveTarget(.calendar("home"))
        XCTAssertNil(store.saveTargetChange, "行で選んだら、記録は消す")
        XCTAssertNil(store.saveTargetChangePrompt)
        try store.save()
        XCTAssertEqual(setup.apple.allEvents().map(\.calendarID), ["home"])
    }

    func testANewSessionForgetsTheChange() throws {
        let localEvent = CalendarEvent(day: day, startMinute: 600, title: "歯医者")
        let setup = makeSetup(local: [localEvent], rules(settingsDefault: "home"))
        let store = setup.store
        fill(store)
        change(setup, to: rules(settingsDefault: "work"))
        XCTAssertNotNil(store.saveTargetChange)
        XCTAssertTrue(store.targetChangedWhileEditing)

        fill(store)
        XCTAssertNil(store.saveTargetChange, "新規を開き直したら消す")
        XCTAssertFalse(store.targetChangedWhileEditing)
        XCTAssertNil(store.saveTargetChangePrompt)

        change(setup, to: rules(settingsDefault: "home"))
        XCTAssertNotNil(store.saveTargetChange)
        try store.startEditing(eventID: localEvent.id)
        XCTAssertNil(store.saveTargetChange, "編集を始めたら消す")
        change(setup, to: rules(settingsDefault: "default"))
        XCTAssertNil(store.saveTargetChange, "編集（既存の予定の所属）は今の決まりのまま。設定の変化を覚えない")
        try store.startCopy()
        XCTAssertNil(store.saveTargetChange, "コピーを始めたら消す")
        XCTAssertEqual(store.content.saveChoice, .timyCueOnly, "コピーはコピー元の保存先から（Q97）")
    }

    // MARK: - 作成画面の中の操作で変わったときは確かめない

    private struct Wired {
        let editor: ScheduleEditorStore
        let connection: CalendarConnection
        let repository: InMemoryEventRepository
    }

    /// 作成画面と見本の連携を、アプリと同じつなぎ方で作る（設定のファイルは一時フォルダ。Apple カレンダーにはつながない）
    private func makeWired(_ preferences: CalendarPreferences) throws -> Wired {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = InMemoryEventRepository()
        let metadata = InMemoryEventMetadataRepository()
        let editor = ScheduleEditorStore(repository: repository, metadataRepository: metadata)
        let connection = CalendarConnection(
            eventStore: EKEventStore(),
            switchable: SwitchableEventRepository(repository),
            localEvents: nil,
            metadata: metadata,
            preferencesFile: JSONFile(url: directory.appendingPathComponent("prefs.json"), empty: CalendarPreferences()),
            authorizationStatus: { .notDetermined },
            onChange: { _, rules, status in
                editor.refresh()
                editor.receiveLink(rules, status: status)
            })
        connection.useSampleLink(CalendarConnection.SampleLink(calendars: [defaultCalendar, home, work], systemDefaultID: "default",
                                                               preferences: preferences, authorization: .fullAccess))
        return Wired(editor: editor, connection: connection, repository: repository)
    }

    func testSettingsChangedInsideTheEditorAreNotAsked() throws {
        // 初めての確かめで既定の保存先を選んだ（設定の既定が「未選択」から「仕事」に変わる）
        var undecided = CalendarPreferences()
        undecided.saveTargetKind = .askBeforeSaving
        let first = try makeWired(undecided)
        fill(first.editor)
        XCTAssertTrue(first.editor.needsFirstSaveTargetChoice)
        XCTAssertTrue(first.editor.applyOwnSettingsChange { first.connection.setDefaultSaveTarget(.calendar("work")) })
        XCTAssertNil(first.editor.saveTargetChange, "利用者が決めたことなので、保存先の変化として確かめない")
        XCTAssertNil(first.editor.saveTargetChangePrompt)
        XCTAssertEqual(try first.editor.save().map(\.calendarID), ["work"], "そのまま保存する（今の動きのまま）")
        XCTAssertEqual(first.connection.preferences.defaultCalendarID, "work")

        // 「表示をONにして保存」（iPhone の既定の Default が、表示 OFF から ON に変わる）
        var hidden = CalendarPreferences()
        hidden.saveTargetKind = .appleCalendar
        hidden.hiddenCalendarIDs = ["default"]
        let show = try makeWired(hidden)
        fill(show.editor)
        let prompt = try XCTUnwrap(show.editor.saveTargetPrompt)
        let hiddenID = try XCTUnwrap(prompt.hiddenCalendarID)
        XCTAssertTrue(show.editor.applyOwnSettingsChange { show.connection.setShown(true, calendarID: hiddenID) })
        XCTAssertNil(show.editor.saveTargetChange)
        XCTAssertNil(show.editor.saveTargetChangePrompt)
        XCTAssertEqual(try show.editor.save().map(\.calendarID), ["default"])

        // 比べ：同じ変化でも、作成画面の外から届いたら確かめる
        let outside = try makeWired(hidden)
        fill(outside.editor)
        XCTAssertTrue(outside.connection.setShown(true, calendarID: "default"))
        XCTAssertEqual(outside.editor.saveTargetChangePrompt?.fromName, "iPhoneの既定（Default）（使えません）")
        XCTAssertEqual(outside.editor.saveTargetChangePrompt?.toName, "iPhoneの既定（Default）")
        XCTAssertThrowsError(try outside.editor.save())
        XCTAssertTrue(outside.repository.allEvents().isEmpty)
    }
}
