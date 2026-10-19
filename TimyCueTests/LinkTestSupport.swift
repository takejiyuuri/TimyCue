import EventKit
import Foundation
@testable import TimyCue

// 2026-10-19「TestFlight 1.0 (30) 報告への回答」の 3 つの直し（作成画面を開いているあいだの設定の変化・許可がなくても連携を OFF にできる・
// 連携の設定を読み込めないとき）と、1.0 (30) からの更新のテストで使う部品。Apple カレンダー（EventKit）にはつながない

/// iPhone のカレンダーの許可の状態と、許可を求めたときの動き（テストで決める）
final class PermissionStub {
    var status: EKAuthorizationStatus
    /// 許可を求めた回数
    private(set) var requests = 0
    /// 許可を求めたあとの状態（nil なら変えない。拒否されたときなど）
    var afterRequest: EKAuthorizationStatus?

    init(_ status: EKAuthorizationStatus, afterRequest: EKAuthorizationStatus? = nil) {
        self.status = status
        self.afterRequest = afterRequest
    }

    /// 許可を求める（CalendarConnection の requestAccess に渡す）
    func request() {
        requests += 1
        if let afterRequest { status = afterRequest }
    }
}

/// 呼ばれた回数（Apple カレンダーの保存先を作った回数など）
final class CallCount {
    var value = 0
}

/// 作成画面へ渡した知らせ（CalendarConnection の onChange が受けたもの）
final class LinkNoticeLog {
    private(set) var count = 0
    private(set) var rules: SaveTargetRules?
    private(set) var status: AppleLinkStatus?

    func record(_ rules: SaveTargetRules?, _ status: AppleLinkStatus) {
        count += 1
        self.rules = rules
        self.status = status
    }
}

/// Apple カレンダーの保存先の代わり。作られた回数（makeCount）・カレンダーを読んだ回数・書いた回数を数える
final class AppleCalendarStub: AppleCalendarRepository {
    private let base: InMemoryEventRepository
    var onLoaded: (@MainActor () -> Void)?
    var calendarList: [CalendarChoice]
    var systemDefaultCalendarID: String?
    /// CalendarConnection がこの保存先を作った回数（makeAppleRepository で数える）
    var makeCount = 0
    private(set) var calendarReads = 0
    private(set) var writes = 0
    private(set) var pauses = 0
    private(set) var resumes = 0
    private(set) var missingResets = 0
    private(set) var isPaused = false
    /// 書けていない結び付けがある（テストで決める）
    var unsavedLinks = false
    /// 結び付けをファイルに書けるか（テストで決める）
    var linksCanBeSaved = true
    /// 書けていない結び付けを書こうとした回数
    private(set) var linkSaves = 0

    init(calendars: [CalendarChoice], systemDefaultID: String?, events: [CalendarEvent] = []) {
        base = InMemoryEventRepository(events: events)
        calendarList = calendars
        systemDefaultCalendarID = systemDefaultID
    }

    /// 止めているかによらず、持っている予定
    var storedEvents: [CalendarEvent] { base.allEvents() }

    func allEvents() -> [CalendarEvent] { isPaused ? [] : base.allEvents() }

    func insert(_ events: [CalendarEvent]) throws {
        writes += events.count
        try base.insert(events)
    }

    func update(_ event: CalendarEvent) throws {
        writes += 1
        try base.update(event)
    }

    func delete(id: UUID) throws {
        writes += 1
        try base.delete(id: id)
    }

    var managesAppleLinks: Bool { true }

    var hasUnsavedLinks: Bool { unsavedLinks }

    func saveUnsavedLinks() -> Bool {
        guard unsavedLinks else { return true }
        linkSaves += 1
        guard linksCanBeSaved else { return false }
        unsavedLinks = false
        return true
    }

    func calendars() -> [CalendarChoice] {
        calendarReads += 1
        return calendarList
    }

    func reloadCache() {}

    func recover(now: Date) -> [SaveJournalEntry] { [] }

    func pause() {
        pauses += 1
        isPaused = true
    }

    func resume() {
        resumes += 1
        isPaused = false
    }

    func resetMissingRecords() { missingResets += 1 }
}

/// 一時フォルダの中のアプリのファイル（Application Support/TimyCue と同じ名前）
struct AppFiles {
    let folder: URL

    var preferences: URL { folder.appendingPathComponent("calendar-preferences.json") }
    var events: URL { folder.appendingPathComponent("events.json") }
    var metadata: URL { folder.appendingPathComponent("metadata.json") }
    var links: URL { folder.appendingPathComponent("eventkit-links.json") }
    var journal: URL { folder.appendingPathComponent("save-journal.json") }

    /// ファイルの中身（ないときは nil）
    func bytes(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    /// ファイルを書き直した時刻（ないときは nil）
    func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// 設定のファイルを「あるのに開けない」形にする（その場所にフォルダを置く。端末のロック中に開けないときの代わり）
    func makePreferencesUnopenable() throws {
        try? FileManager.default.removeItem(at: preferences)
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
    }

    /// 設定のファイルが、まだ開けない形（フォルダ）のままか
    var preferencesStillUnopenable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: preferences.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// 開けなかった設定のファイルが読めるようになった（フォルダを外して、中身を置く）
    func makePreferencesReadable(_ json: String) throws {
        try? FileManager.default.removeItem(at: preferences)
        try Data(json.utf8).write(to: preferences)
    }
}
