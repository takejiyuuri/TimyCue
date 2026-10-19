import Foundation

/// 今の利用者の保存先の移行（spec §89.8・Q98・Q111。S2）。新しい版を初めて開いたときに一度だけ、
/// 旧版の保存の設定と使った跡から、新しい予定の既定の保存先の種類を決める。起動のたびに許可の状態だけで決めない。
/// 材料は読むだけで、予定・TimyCue の設定・結び付け・保存の途中の記録には何も書かない（写しのファイルも作らない）
enum SaveTargetMigration {
    /// 移行の材料（端末の中のファイルから読む。カレンダーの許可の状態は入れない：フルアクセスの許可だけでは証拠にしない）
    struct Evidence: Equatable {
        /// 旧版ではっきり選んだ保存先（設定の defaultCalendarID）
        var explicitCalendarID: String?
        /// 旧版の自動の切り替えの「保存先のカレンダーを切り替えました」をまだ知らせていない印。読むだけで、Apple に保存していた
        /// 証拠にはしない（実際に Apple へ書いたことまでは示さない。2026-10-19 ユーザー指示）。印そのものは消さずに残す
        var oldAutoSwitchNotice = false
        /// TimyCue が Apple カレンダーへ書いたときにしか付かない印がある（結び付けの終了未設定・保存の途中の記録の Apple の書き込み）
        var appleWriteRecord = false
        /// 前に使った跡がある（設定・予定・TimyCue の設定・結び付け・出発の設定・場所・保存の途中の記録のどれかのファイルがある）
        var usedBefore = false
        /// 結び付けのファイルがあるのに開けない（端末のロック中など）
        var linksCouldNotOpen = false
        /// 保存の途中の記録のファイルがあるのに開けない
        var journalCouldNotOpen = false
    }

    /// 決めた理由（テストと記録のため）
    enum Reason: Equatable {
        /// 1 明示的に選んだ旧版の保存先
        case explicitChoice
        /// 2 旧版で Apple へ保存していた確かな記録（結び付けの終了未設定の印・保存の途中の記録の Apple の書き込み）
        case appleWriteRecord
        /// 3 新しい利用者
        case newUser
        /// 4 今の利用者で保存先を特定できない
        case unknown
    }

    enum Decision: Equatable {
        case decided(SaveTargetKind, reason: Reason)
        /// 材料のファイルを開けないので、この起動では決めない（保存の前に確かめる扱いをメモリの中だけで使う）
        case deferred
    }

    /// 優先の順（Q111）：1 明示的に選んだ旧版の保存先／2 旧版で Apple に保存していた信頼できる記録／
    /// 3 新しい利用者は「TimyCue のみ」／4 特定できない今の利用者は、初めて保存する前に確かめる。
    /// 旧版の自動の切り替えの印だけでは Apple にしない（2026-10-19 ユーザー指示。印のある今の利用者は、ほかの記録がなければ 4）
    static func decide(_ evidence: Evidence) -> Decision {
        // 1 はっきり選んだ保存先は、今そのカレンダーが使えなくても、許可がなくても引き継ぐ（Q111-1）
        if evidence.explicitCalendarID != nil { return .decided(.appleCalendar, reason: .explicitChoice) }
        // 書き込みの記録を確かめられないうちは決めない（今の利用者を TimyCue のみと誤らないため）
        if evidence.linksCouldNotOpen || evidence.journalCouldNotOpen { return .deferred }
        // 2 TimyCue が Apple へ書いたときにしか付かない記録（保存先は iPhone の既定を引き継ぐ。Q111-2）
        if evidence.appleWriteRecord { return .decided(.appleCalendar, reason: .appleWriteRecord) }
        // 3 使った跡が何もなければ新しい利用者（Q111-3）
        if !evidence.usedBefore { return .decided(.timyCueOnly, reason: .newUser) }
        // 4 使った跡はあるが、Apple の保存先を特定できない。許可がないことを TimyCue のみの理由にしない（Q111-4）
        return .decided(.askBeforeSaving, reason: .unknown)
    }

    // MARK: - ファイル（Application Support/TimyCue の中。名前は各保存先と同じ）

    static let preferencesFileName = "calendar-preferences.json"
    static let linksFileName = "eventkit-links.json"
    static let eventsFileName = "events.json"
    static let metadataFileName = "metadata.json"
    static let departureSettingsFileName = "departure-settings.json"
    static let placeBookFileName = "place-book.json"
    static let journalFolderName = "Journal"
    static let journalFileName = "save-journal.json"
    static let pendingMetadataFileName = "pending-metadata.json"

    /// 材料を集める（読むだけ。写しのファイルも作らない）。folder は設定のファイルと同じフォルダ。
    /// preferencesFileExisted：起動の時点で設定のファイルがあったか
    static func collect(folder: URL, preferences: CalendarPreferences, preferencesFileExisted: Bool) -> Evidence {
        var evidence = Evidence()
        evidence.explicitCalendarID = preferences.defaultCalendarID
        evidence.oldAutoSwitchNotice = preferences.pendingFallbackNotice == true

        let manager = FileManager.default
        let journalFolder = folder.appendingPathComponent(journalFolderName, isDirectory: true)
        let linksURL = folder.appendingPathComponent(linksFileName)
        let journalURL = journalFolder.appendingPathComponent(journalFileName)
        let usageFiles = [
            linksURL,
            folder.appendingPathComponent(eventsFileName),
            folder.appendingPathComponent(metadataFileName),
            folder.appendingPathComponent(departureSettingsFileName),
            folder.appendingPathComponent(placeBookFileName),
            journalURL,
            journalFolder.appendingPathComponent(pendingMetadataFileName),
        ]
        evidence.usedBefore = preferencesFileExisted || usageFiles.contains { manager.fileExists(atPath: $0.path) }

        // 結び付けの終了未設定の印は、TimyCue が Apple へ書いたとき（作成か変更）にしか付かない（2026-10-18 の調べ）。
        // 中身が壊れているだけなら、開けないとは扱わない（使った跡にはなるが、書き込みの証拠にはしない）
        if manager.fileExists(atPath: linksURL.path) {
            if let data = try? Data(contentsOf: linksURL) {
                if let links = try? JSONDecoder().decode(EventKitLinks.self, from: data), !links.endUnset.isEmpty {
                    evidence.appleWriteRecord = true
                }
            } else {
                evidence.linksCouldNotOpen = true
            }
        }
        // 保存の途中の記録の、Apple へ書き始めた・書けた・作れた記録
        if manager.fileExists(atPath: journalURL.path) {
            if let data = try? Data(contentsOf: journalURL) {
                if let entries = try? JSONDecoder().decode([SaveJournalEntry].self, from: data),
                   entries.contains(where: { $0.isApple && ($0.writeStarted == true || $0.appleKey != nil || $0.created == true) }) {
                    evidence.appleWriteRecord = true
                }
            } else {
                evidence.journalCouldNotOpen = true
            }
        }
        return evidence
    }

    /// 移行の済んだ記録があるのに、設定のファイルに新しい項目がない（古い版が書き直した・前回の保存に失敗した）ときの種類。
    /// 保存先の id が記録と同じなら記録の種類。記録が Apple で、ファイルに別の id がはっきりあれば、古い版で選び直したとみなして Apple。
    /// それ以外（TimyCue のみ・まだ決まっていないから Apple の id へ変わった、id がなくなった＝旧版の自動の切り替えと見分けられない）は、
    /// 保存の前に確かめる。TimyCue のみと Apple のあいだを黙って入れ替えない
    static func restoredKind(record: SaveTargetRecord, file: CalendarPreferences) -> SaveTargetKind {
        if file.defaultCalendarID == record.calendarID { return record.kind }
        if record.kind == .appleCalendar, file.defaultCalendarID != nil { return .appleCalendar }
        return .askBeforeSaving
    }
}

/// 移行の済んだ記録（spec §89.8：UserDefaults に置いてよい）。新しい版が設定を保存できるたびに写す。
/// 古い版が設定のファイルを書き直して新しい項目が消えたときに、ここから戻す
struct SaveTargetRecord: Codable, Equatable {
    var kind: SaveTargetKind
    /// そのときの設定の defaultCalendarID
    var calendarID: String?
    /// そのときの設定の appleLinkEnabled
    var linkEnabled: Bool?
}

/// 移行の済んだ記録の置き場所（UserDefaults。端末ごと。古い版はさわらない）
final class SaveTargetRecordStore {
    static let defaultKey = "TimyCue.SaveTargetRecord.v1"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = SaveTargetRecordStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// アプリの本物の置き場所
    static var live: SaveTargetRecordStore {
        SaveTargetRecordStore(defaults: .standard)
    }

    func load() -> SaveTargetRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SaveTargetRecord.self, from: data)
    }

    func save(_ record: SaveTargetRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }
}
