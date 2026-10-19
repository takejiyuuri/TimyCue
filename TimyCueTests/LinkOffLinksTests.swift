import EventKit
import XCTest
@testable import TimyCue

/// Apple カレンダー連携を OFF にしても、結び付け（TimyCue の予定の id と Apple の予定の対応・終了未設定の印・繰り返しの共通設定の id・
/// 「見つからない」の記録）と TimyCue の設定（到着目標など）を失わない（spec §89.6、2026-10-19 ユーザー指示「S2・S3・S6 の確認結果と
/// TestFlight 配信指示」1）。本物の EventKit の保存先と一時ファイルで確かめる（EventKit の許可は使わず、Apple の予定は読み書きしない）
final class LinkOffLinksTests: XCTestCase {
    private var directory: URL!
    private let eventID = UUID()
    private let occurrenceID = UUID()
    private let seriesID = UUID()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: linksFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var preferencesURL: URL { directory.appendingPathComponent("calendar-preferences.json") }
    private var metadataURL: URL { directory.appendingPathComponent("metadata.json") }
    /// 結び付けのファイルは別のフォルダに置く（そのフォルダをふつうのファイルに置き換えると、書けなくなる）。
    /// フォルダのときもファイルのときも同じ場所を指すよう、末尾の「/」を付けない形にする
    private var linksFolder: URL { directory.appendingPathComponent("links", isDirectory: false) }
    private var linksURL: URL { linksFolder.appendingPathComponent("eventkit-links.json") }

    /// 前から持っている結び付け：ふつうの予定（終了未設定）・繰り返しの回（シリーズ共通の設定の id）・「見つからない」の記録
    private var originalLinks: EventKitLinks {
        var links = EventKitLinks()
        links.keys[eventID] = "item-A"
        links.keys[occurrenceID] = EventKitMapping.linkKey(itemIdentifier: "item-S",
                                                           occurrenceDate: Date(timeIntervalSince1970: 1_800_000_000))
        links.endUnset = [eventID]
        links.seriesIDs = ["item-S": seriesID]
        links.missingSince = ["item-A": Date(timeIntervalSince1970: 1_790_000_000)]
        return links
    }

    /// 連携 ON・保存先は Apple の設定と、結び付け・到着目標（15 分前）のファイル
    private func writeFiles() throws {
        var preferences = CalendarPreferences()
        preferences.saveTargetKind = .appleCalendar
        preferences.formatVersion = CalendarPreferences.currentFormatVersion
        try JSONEncoder().encode(preferences).write(to: preferencesURL)
        try JSONEncoder().encode(originalLinks).write(to: linksURL)
        var settings = TimyCueEventMetadata()
        settings.arrivalTargetMinutes = 15
        let metadata: [UUID: TimyCueEventMetadata] = [eventID: settings, seriesID: settings]
        try JSONEncoder().encode(metadata).write(to: metadataURL)
    }

    private func savedPreferences() -> CalendarPreferences {
        JSONFile(url: preferencesURL, empty: CalendarPreferences()).load()
    }

    private func modificationDate(_ url: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// 作った EventKit の保存先（テストから結び付けの状態を見る）
    private final class Created {
        var count = 0
        var repository: EventKitEventRepository?
    }

    private struct Setup {
        let connection: CalendarConnection
        let switchable: SwitchableEventRepository
        let local: FileEventRepository
    }

    /// アプリと同じつなぎ方で、本物の EventKit の保存先（結び付けは一時ファイル）を使う。許可の状態はテストで決める
    @MainActor
    private func makeConnection(created: Created, metadata: EventMetadataRepository) -> Setup {
        let local = FileEventRepository(file: JSONFile(url: directory.appendingPathComponent("events.json"), empty: []))
        let switchable = SwitchableEventRepository(local)
        let linksFileURL = linksURL
        let connection = CalendarConnection(
            eventStore: EKEventStore(),
            switchable: switchable,
            localEvents: local,
            metadata: metadata,
            preferencesFile: JSONFile(url: preferencesURL, empty: CalendarPreferences()),
            authorizationStatus: { .fullAccess },
            makeAppleRepository: { preferences, journal in
                created.count += 1
                let repository = EventKitEventRepository(store: EKEventStore(), metadata: metadata, preferences: preferences,
                                                         journal: journal,
                                                         linksFile: JSONFile(url: linksFileURL, empty: EventKitLinks()))
                created.repository = repository
                return repository
            },
            onChange: { _, _, _ in })
        return Setup(connection: connection, switchable: switchable, local: local)
    }

    // MARK: - 結び付けを書けなければ OFF にしない

    @MainActor
    func testTheLinkStaysOnWhenTheLinksCannotBeSaved() throws {
        try writeFiles()
        let created = Created()
        let setup = makeConnection(created: created,
                                   metadata: FileEventMetadataRepository(file: JSONFile(url: metadataURL, empty: [:])))
        let connection = setup.connection
        XCTAssertTrue(connection.isLinked)
        let repository = try XCTUnwrap(created.repository)

        // 結び付けのフォルダをふつうのファイルに置き換えて書けなくし、結び付けの書き込みを失敗させる（書けていない結び付けが残る）
        try FileManager.default.removeItem(at: linksFolder)
        try Data("x".utf8).write(to: linksFolder)
        repository.resetMissingRecords()
        XCTAssertTrue(repository.hasUnsavedLinks)

        XCTAssertFalse(connection.setAppleLinkEnabled(false), "結び付けを保存できなければ OFF にしない")
        XCTAssertTrue(connection.isLinkEnabled, "ON のまま")
        XCTAssertTrue(connection.isLinked)
        XCTAssertFalse(setup.switchable.current === setup.local, "Apple カレンダーの保存先を使ったまま")
        XCTAssertEqual(connection.settingsFailure?.message, CalendarConnection.linkOffLinksFailureMessage, "理由を出す（文言は仮）")
        XCTAssertEqual(connection.settingsRevision, 1, "スイッチの見た目を ON に戻す")
        XCTAssertNil(savedPreferences().appleLinkEnabled, "OFF の設定を書かない")
        XCTAssertTrue(repository.hasUnsavedLinks, "書けていない結び付けは、メモリの上に残っている（捨てない）")

        // 書けるようになれば OFF にできる。結び付けは消さずに書いてから止める
        try FileManager.default.removeItem(at: linksFolder)
        try FileManager.default.createDirectory(at: linksFolder, withIntermediateDirectories: true)
        connection.dismissSettingsFailure()
        XCTAssertTrue(connection.setAppleLinkEnabled(false))
        XCTAssertFalse(repository.hasUnsavedLinks)
        XCTAssertTrue(setup.switchable.current === setup.local)
        let saved = JSONFile(url: linksURL, empty: EventKitLinks()).load()
        XCTAssertEqual(saved.keys, originalLinks.keys, "結び付けを消さない")
        XCTAssertEqual(saved.endUnset, originalLinks.endUnset)
        XCTAssertEqual(saved.seriesIDs, originalLinks.seriesIDs)
        XCTAssertEqual(savedPreferences().appleLinkEnabled, false)
    }

    // MARK: - OFF・開き直し・ON

    @MainActor
    func testOffAndARestartKeepTheLinksAndSettingsForTurningBackOn() throws {
        try writeFiles()
        let linksBytes = try Data(contentsOf: linksURL)
        let linksModified = try modificationDate(linksURL)
        let metadataBytes = try Data(contentsOf: metadataURL)

        let first = makeConnection(created: Created(),
                                   metadata: FileEventMetadataRepository(file: JSONFile(url: metadataURL, empty: [:])))
        XCTAssertTrue(first.connection.isLinked)
        XCTAssertTrue(first.connection.setAppleLinkEnabled(false))
        XCTAssertEqual(try Data(contentsOf: linksURL), linksBytes,
                       "OFF にしても結び付けを消さない・やり直さない（終了未設定の印・繰り返しの id・「見つからない」の記録も）")
        XCTAssertEqual(try Data(contentsOf: metadataURL), metadataBytes, "到着目標などの TimyCue の設定も消さない")
        XCTAssertEqual(savedPreferences().appleLinkEnabled, false)

        // アプリを終えて開き直す（同じファイルの上に作り直す）
        let created = Created()
        let metadata = FileEventMetadataRepository(file: JSONFile(url: metadataURL, empty: [:]))
        let second = makeConnection(created: created, metadata: metadata)
        XCTAssertEqual(created.count, 0, "OFF で起動したら、結び付けのファイルを読み書きする EventKit の保存先を作らない")
        XCTAssertFalse(second.connection.isLinked)
        XCTAssertTrue(second.switchable.current === second.local)
        XCTAssertEqual(try Data(contentsOf: linksURL), linksBytes, "OFF の起動は結び付けのファイルに触れない")
        XCTAssertEqual(try modificationDate(linksURL), linksModified)
        XCTAssertEqual(try Data(contentsOf: metadataURL), metadataBytes)

        // ON に戻す：同じ結び付けを読み直して、同じ TimyCue の id を使う（到着目標などが戻る）
        XCTAssertTrue(second.connection.setAppleLinkEnabled(true))
        XCTAssertEqual(created.count, 1)
        XCTAssertTrue(second.connection.isLinked)
        XCTAssertEqual(second.switchable.seriesID(of: occurrenceID), seriesID, "前の結び付けを読み直して、同じ id を使う")
        let reloaded = JSONFile(url: linksURL, empty: EventKitLinks()).load()
        XCTAssertEqual(reloaded.keys, originalLinks.keys)
        XCTAssertEqual(reloaded.endUnset, originalLinks.endUnset)
        XCTAssertEqual(reloaded.seriesIDs, originalLinks.seriesIDs)
        XCTAssertNil(reloaded.missingSince, "「見つからない」の記録だけは、ON に戻したときにやり直す（ON の直後に予定を消さない。Q103）")
        XCTAssertEqual(try Data(contentsOf: metadataURL), metadataBytes, "TimyCue の設定は書き換えない")
        XCTAssertEqual(metadata.allMetadata()[eventID]?.arrivalTargetMinutes, 15)
    }
}
