import EventKit
import SwiftUI
import UIKit
import XCTest
@testable import TimyCue

/// 2026-10-19 TestFlight 1.0 (30) のクラッシュ（設定で Default の表示を OFF にして、新しい予定を開くと落ちた）の回帰テスト。
/// 保存先の形を変えて、Home の［予定を登録］・月カレンダーの「＋」・1 日タイムラインの「＋」と同じ呼び方で作成画面を開き、
/// 画面を実際に組み立てて並べ（落ちればここでテストが止まる）、保存先の出し方（spec §89.3・§89.4）と、
/// 開いただけで設定（表示・既定の保存先）を変えず、どこにも書かないことを確かめる
@MainActor
final class NewEventOpeningTests: XCTestCase {
    private let today = CalendarDay(Date())

    /// 見本の連携と同じ形のカレンダー（iPhone の既定は Default）
    private static let calendars = [
        CalendarChoice(id: "default", title: "Default", sourceTitle: "iCloud", isWritable: true, color: .orange),
        CalendarChoice(id: "home", title: "家", sourceTitle: "iCloud", isWritable: true, color: .green),
        CalendarChoice(id: "work", title: "仕事", sourceTitle: "Google", isWritable: true, color: .saxeBlue),
        // 書き込めない共有のカレンダー（保存先の候補には出ない）
        CalendarChoice(id: "shared", title: "チーム", sourceTitle: "Google", isWritable: false, color: .mint),
    ]

    private struct Setup {
        let editor: ScheduleEditorStore
        let calendar: CalendarStore
        let connection: CalendarConnection
        let repository: InMemoryEventRepository
    }

    /// 作成画面の 3 つの入口（それぞれの画面のボタンと同じ呼び方）
    private enum Entry: CaseIterable {
        /// Home の［予定を登録］：今日を選んだ新規
        case home
        /// 月カレンダーの「＋」：選んでいる日があればその日、なければ今日
        case calendarPlus
        /// 1 日タイムラインの「＋」：表示中の日
        case timelinePlus
    }

    /// 作成画面・カレンダー・連携を、アプリと同じつなぎ方で作る（連携の知らせで、作成画面へ保存先の決まりを渡す）。
    /// 連携は見本の連携（メモリの中だけ。Apple カレンダーにはつながない）
    private func makeSetup(_ preferences: CalendarPreferences, authorization: EKAuthorizationStatus = .fullAccess,
                           systemDefaultID: String? = "default") throws -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = InMemoryEventRepository()
        let metadata = InMemoryEventMetadataRepository()
        let editor = ScheduleEditorStore(repository: repository, metadataRepository: metadata)
        let calendar = CalendarStore(repository: repository, metadataRepository: metadata, today: today)
        let connection = CalendarConnection(
            eventStore: EKEventStore(),
            switchable: SwitchableEventRepository(repository),
            localEvents: nil,
            metadata: metadata,
            preferencesFile: JSONFile(url: directory.appendingPathComponent("prefs.json"), empty: CalendarPreferences()),
            authorizationStatus: { .notDetermined },
            onChange: { calendars, saveTargets, status in
                calendar.setCalendars(calendars)
                editor.refresh()
                editor.receiveLink(saveTargets, status: status)
            })
        connection.useSampleLink(CalendarConnection.SampleLink(calendars: Self.calendars, systemDefaultID: systemDefaultID,
                                                               preferences: preferences, authorization: authorization))
        return Setup(editor: editor, calendar: calendar, connection: connection, repository: repository)
    }

    /// 入口と同じ呼び方で新規を始め、選んだ日を返す
    @discardableResult
    private func open(_ setup: Setup, from entry: Entry) -> CalendarDay {
        let day: CalendarDay
        switch entry {
        case .home: day = today
        case .calendarPlus: day = setup.calendar.dayForNewEvent
        case .timelinePlus: day = today.adding(days: 1)
        }
        setup.editor.refresh()
        setup.editor.startNew(on: day)
        return day
    }

    /// 作成画面を実際に組み立てて並べる（6.9 インチ相当の大きさ）。行の値・チップ・保存の前の確かめの部品まで作る
    private func render(_ setup: Setup, day: CalendarDay) {
        let view = ScheduleEditorView(initialMonth: CalendarMonth(day))
            .environment(setup.editor)
            .environment(setup.calendar)
            .environment(setup.connection)
        let controller = UIHostingController(rootView: view)
        let frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        controller.view.layoutIfNeeded()
        window.isHidden = true
        window.rootViewController = nil
    }

    /// 3 つの入口で開いて並べ、行の値の候補に同じ文字が重ならないことも確かめる（重なると、行の値の並びが壊れる）
    private func openEverywhere(_ setup: Setup, file: StaticString = #filePath, line: UInt = #line,
                                check: (ScheduleEditorStore) -> Void = { _ in }) {
        for entry in Entry.allCases {
            let day = open(setup, from: entry)
            let values = setup.editor.calendarRowValues
            XCTAssertEqual(values.count, Set(values).count, "\(entry)：行の値の候補に同じ文字が重なっている \(values)", file: file, line: line)
            for row in setup.editor.visibleRows {
                let texts = setup.editor.valueTexts(for: row)
                XCTAssertEqual(texts.count, Set(texts).count, "\(entry)：\(row) の値の候補に同じ文字が重なっている \(texts)", file: file, line: line)
            }
            check(setup.editor)
            render(setup, day: day)
            // 開いて並べただけでは、どこにも書かない
            XCTAssertTrue(setup.repository.allEvents().isEmpty, "\(entry)：開いただけで予定を書いた", file: file, line: line)
        }
    }

    private func preferences(kind: SaveTargetKind = .appleCalendar, defaultCalendarID: String? = nil,
                             hidden: Set<String> = [], linkEnabled: Bool? = nil) -> CalendarPreferences {
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = kind
        preferences.defaultCalendarID = defaultCalendarID
        preferences.hiddenCalendarIDs = hidden
        preferences.appleLinkEnabled = linkEnabled
        return preferences
    }

    // MARK: - 1. Default の表示 ON

    func testOpensWithDefaultShown() throws {
        let setup = try makeSetup(preferences())
        openEverywhere(setup) { editor in
            XCTAssertEqual(editor.pendingSaveTarget, .usable(Self.calendars[0], source: .systemDefault))
            XCTAssertEqual(editor.calendarRowValue, "iPhoneの既定（Default）")
        }
    }

    // MARK: - 2. Default の表示 OFF

    /// 保存先が iPhone の既定（Default）で、その表示を OFF
    func testOpensWithDefaultHidden() throws {
        let setup = try makeSetup(preferences(hidden: ["default"]))
        openEverywhere(setup) { editor in
            XCTAssertEqual(editor.pendingSaveTarget, .unavailable(.hidden(calendarTitle: "Default"), source: .systemDefault))
            XCTAssertTrue(editor.showsCalendarRow, "使えない保存先を出し、選び直せる（spec §89.3）")
            XCTAssertEqual(editor.calendarRowChoices, [.timyCueOnly, .calendar("home"), .calendar("work")],
                           "選べるのは「TimyCue のみ」と使えるカレンダーだけ（表示 OFF の Default は出さない）")
        }
        // 予定名と開始時刻を入れて保存しようとすると、保存の前に選び直してもらう
        // （足りない項目があるあいだは、先に行で知らせるので、開いた直後には出さない。§46）
        let day = open(setup, from: .calendarPlus)
        XCTAssertNil(setup.editor.saveTargetPrompt)
        setup.editor.content.title = "見本の打合せ"
        setup.editor.setStartMinute(14 * 60, on: day)
        XCTAssertNotNil(setup.editor.saveTargetPrompt, "保存の前に選び直してもらう")
        XCTAssertEqual(setup.editor.saveTargetPromptChoices, [.timyCueOnly, .calendar("home"), .calendar("work")])
        assertSettingsKept(setup, hidden: ["default"], defaultCalendarID: nil)
    }

    /// 設定の既定の保存先に Default をはっきり選んでいて、その表示を OFF（行の値が「Default（使えません）」になる形）
    func testOpensWithExplicitDefaultHidden() throws {
        let setup = try makeSetup(preferences(defaultCalendarID: "default", hidden: ["default"]))
        openEverywhere(setup) { editor in
            XCTAssertEqual(editor.pendingSaveTarget, .unavailable(.hidden(calendarTitle: "Default"), source: .settingsDefault))
            // 1.0 (30) では「Default（使えません）」が 2 回並び、行の値を選ぶ部品が止まって落ちた
            XCTAssertEqual(editor.calendarRowValues, ["Default（使えません）", "使えません"])
            XCTAssertEqual(editor.calendarRowChoices, [.timyCueOnly, .calendar("home"), .calendar("work")])
        }
        assertSettingsKept(setup, hidden: ["default"], defaultCalendarID: "default")
    }

    /// 使えない保存先のまま保存を押しても、Default を ON に戻さず、別の Apple カレンダーへも書かない（spec §89.4）。
    /// 「TimyCue のみ」を選べば、この iPhone の中へ保存できる
    func testHiddenDefaultIsNotWrittenSilentlyAndTimyCueOnlyCanBeSaved() throws {
        let setup = try makeSetup(preferences(defaultCalendarID: "default", hidden: ["default"]))
        let day = open(setup, from: .calendarPlus)
        setup.editor.content.title = "見本の打合せ"
        setup.editor.setStartMinute(14 * 60, on: day)
        XCTAssertThrowsError(try setup.editor.save())
        XCTAssertTrue(setup.repository.allEvents().isEmpty, "使えない保存先へも、別のカレンダーへも書かない")
        assertSettingsKept(setup, hidden: ["default"], defaultCalendarID: "default")

        setup.editor.dismissFailure()
        setup.editor.chooseSaveTarget(.timyCueOnly)
        let saved = try setup.editor.save()
        XCTAssertEqual(saved.count, 1)
        XCTAssertNil(saved.first?.calendarID, "TimyCue のみ（この iPhone の中）に保存した")
        assertSettingsKept(setup, hidden: ["default"], defaultCalendarID: "default")
    }

    // MARK: - 3. Apple カレンダーを全部表示 OFF（使える Apple カレンダーが 0 件）

    func testOpensWithAllCalendarsHidden() throws {
        for defaultCalendarID in [nil, "default"] as [String?] {
            let setup = try makeSetup(preferences(defaultCalendarID: defaultCalendarID, hidden: ["default", "home", "work"]))
            openEverywhere(setup) { editor in
                XCTAssertTrue(editor.saveTargetCandidates.isEmpty)
                XCTAssertTrue(editor.showsCalendarRow, "使えない保存先を出し、「TimyCue のみ」を選べる")
                XCTAssertEqual(editor.calendarRowChoices, [.timyCueOnly])
                XCTAssertEqual(editor.saveTargetPromptChoices, [.timyCueOnly])
                XCTAssertNotNil(editor.saveTargetProblem)
            }

            // TimyCue のみの予定は作れる
            let day = open(setup, from: .home)
            setup.editor.content.title = "見本の打合せ"
            setup.editor.setStartMinute(9 * 60, on: day)
            setup.editor.chooseSaveTarget(.timyCueOnly)
            XCTAssertEqual(try setup.editor.save().count, 1)
            assertSettingsKept(setup, hidden: ["default", "home", "work"], defaultCalendarID: defaultCalendarID)
        }
    }

    // MARK: - 4. Apple カレンダー連携の全体が OFF

    func testOpensWithLinkOff() throws {
        for authorization in [EKAuthorizationStatus.fullAccess, .denied] {
            let setup = try makeSetup(preferences(defaultCalendarID: "default", hidden: ["default"], linkEnabled: false),
                                      authorization: authorization)
            openEverywhere(setup) { editor in
                XCTAssertFalse(editor.isConnectedToApple)
                XCTAssertNil(editor.pendingSaveTarget, "連携していなければ、この iPhone の中へ保存する")
                XCTAssertEqual(editor.calendarRowValue, SaveTargetRules.timyCueOnlyLabel)
            }
            let day = open(setup, from: .timelinePlus)
            setup.editor.content.title = "見本の打合せ"
            setup.editor.setStartMinute(10 * 60, on: day)
            XCTAssertEqual(try setup.editor.save().count, 1, "連携 OFF でも TimyCue のみの予定は作れる")
        }
    }

    // MARK: - 5. 保存先が使えない・未選択

    func testOpensWithUnavailableOrUnchosenTarget() throws {
        // 設定の既定のカレンダーが見つからない
        let missing = try makeSetup(preferences(defaultCalendarID: "missing"))
        openEverywhere(missing) { editor in
            XCTAssertEqual(editor.pendingSaveTarget, .unavailable(.notFound, source: .settingsDefault))
            XCTAssertTrue(editor.showsCalendarRow)
        }
        // iPhone の既定が取れない
        let noSystemDefault = try makeSetup(preferences(), systemDefaultID: nil)
        openEverywhere(noSystemDefault) { editor in
            XCTAssertEqual(editor.pendingSaveTarget, .unavailable(.noSystemDefault, source: .systemDefault))
        }
        // 保存先がまだ決まっていない（未選択）。Default の表示 OFF でも同じ
        for hidden in [[], ["default"]] as [Set<String>] {
            let unchosen = try makeSetup(preferences(kind: .askBeforeSaving, hidden: hidden))
            openEverywhere(unchosen) { editor in
                XCTAssertEqual(editor.pendingSaveTarget, .notChosen)
                XCTAssertEqual(editor.calendarRowValue, SaveTargetRules.notChosenLabel)
                XCTAssertTrue(editor.showsCalendarRow)
            }
        }
        // 書き込めないカレンダーを既定にしていた
        let readOnly = try makeSetup(preferences(defaultCalendarID: "shared"))
        openEverywhere(readOnly) { editor in
            XCTAssertEqual(editor.pendingSaveTarget, .unavailable(.readOnly(calendarTitle: "チーム"), source: .settingsDefault))
        }
    }

    // MARK: - 6. 入口ごと（上のどのテストも、3 つの入口で開いて並べている）

    /// 開いているあいだに Default の表示を OFF にしても（設定の画面から戻ってきたとき）、開き直した作成画面は落ちない
    func testReopeningAfterHidingDefaultInSettings() throws {
        let setup = try makeSetup(preferences(defaultCalendarID: "default"))
        openEverywhere(setup)
        XCTAssertTrue(setup.connection.setShown(false, calendarID: "default"))
        openEverywhere(setup) { editor in
            XCTAssertEqual(editor.pendingSaveTarget, .unavailable(.hidden(calendarTitle: "Default"), source: .settingsDefault))
        }
    }

    private func assertSettingsKept(_ setup: Setup, hidden: Set<String>, defaultCalendarID: String?,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(setup.connection.preferences.hiddenCalendarIDs, hidden, "表示の設定を勝手に変えない（Default を ON に戻さない）",
                       file: file, line: line)
        XCTAssertEqual(setup.connection.preferences.defaultCalendarID, defaultCalendarID, "既定の保存先を勝手に変えない",
                       file: file, line: line)
    }
}
