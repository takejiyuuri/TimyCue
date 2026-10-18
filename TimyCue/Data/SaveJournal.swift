import Foundation

/// 保存の途中の記録 1 件（spec §89.9・2026-10-18 S1b 指示 5・6）
struct SaveJournalEntry: Codable, Equatable, Identifiable {
    /// TimyCue の予定の id（書く前に決めた id。押し直しでも同じ）
    let id: UUID
    /// 確かめてもらうときに見せる、予定名と日時
    let title: String
    let day: CalendarDay
    let startMinute: Int
    /// 終了未設定で、仮の長さで保存した予定（結び付け直すときに印を戻す。§69）
    let endUnset: Bool
    /// 書けたら当てる TimyCue の設定（到着目標など）
    var metadata: TimyCueEventMetadata?
    /// Apple カレンダーへ書く（false は、この iPhone の中へ書く）
    let isApple: Bool
    /// Apple カレンダーに書けた直後に記録する、Apple の予定の鍵
    var appleKey: String?
    /// 「Apple Calendarに保存」のときの、元のローカルの予定の id
    var movedFromLocalID: UUID?
    /// 書けたと確かめた（「Apple Calendarに保存」の続きから行うとき、作り直さない）
    var created: Bool?
    /// 設定（metadata）を保存できた。次に開いたとき、記録した設定で上書きしない
    var metadataSaved: Bool?
    /// Apple へ書き始めた（書く直前に付ける。付いていない記録は、何も書いていない）
    var writeStarted: Bool?
    /// 利用者に知らせた（同じことを起動のたびに知らせない）
    var noticed: Bool?
    let createdAt: Date

    /// 確かめてもらうときの言い方（例「A社」10月19日（月）10:00）
    var label: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "予定名なし" : title
        return "「\(name)」\(day.month)月\(day.day)日（\(day.weekdaySymbol())）\(TimeText.hourMinute(startMinute))"
    }
}

/// 保存の途中の記録（spec §89.9・2026-10-18 S1b 指示 5・6）。
/// Apple カレンダーへ書く前に、TimyCue の予定の id・予定名と日時・設定を書いておき、書けた直後に Apple の予定の鍵を足し、
/// 結び付けと設定を保存し終えたら消す。アプリが途中で終わっても、次に開いたとき、記録した鍵で結び付け直して設定を当てる。
/// 名前や日時が似ているだけでは結び付けない。鍵のない記録（書けたか分からない）は、自動では書き直さず、確かめてもらう。
/// 端末の中だけに置き、バックアップには入れない（別の iPhone に戻したとき、その iPhone の予定と取り違えないように）
final class SaveJournal {
    private let file: JSONFile<[SaveJournalEntry]>?
    private(set) var entries: [SaveJournalEntry]
    /// 予定は保存できたのに、まだ保存できていない TimyCue の設定（予定の id → 設定）。アプリが終わっても、次に開いたときに保存し直す
    private let pendingFile: JSONFile<[UUID: TimyCueEventMetadata]>?
    private(set) var pendingMetadata: [UUID: TimyCueEventMetadata]

    init(file: JSONFile<[SaveJournalEntry]>?, pendingFile: JSONFile<[UUID: TimyCueEventMetadata]>? = nil) {
        self.file = file
        self.pendingFile = pendingFile
        entries = file?.load() ?? []
        pendingMetadata = pendingFile?.load() ?? [:]
    }

    /// メモリの中だけ（見本の予定・テスト）
    static func inMemory() -> SaveJournal {
        SaveJournal(file: nil)
    }

    /// この iPhone の中（記録のフォルダごとバックアップに入れない）
    static func onDevice() -> SaveJournal {
        var folder = JSONFile<[SaveJournalEntry]>.appSupportURL(named: "Journal")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return SaveJournal(file: JSONFile(url: folder.appendingPathComponent("save-journal.json"), empty: []),
                           pendingFile: JSONFile(url: folder.appendingPathComponent("pending-metadata.json"), empty: [:]))
    }

    /// まだ保存できていない設定を置き換える（変わったときだけ書く）
    func setPendingMetadata(_ value: [UUID: TimyCueEventMetadata]) {
        guard value != pendingMetadata else { return }
        pendingMetadata = value
        try? pendingFile?.save(value)
    }

    /// 設定を保存できた（ids のうち記録にあるもの）
    func markMetadataSaved(_ ids: Set<UUID>) {
        var changed = false
        for index in entries.indices where ids.contains(entries[index].id) && entries[index].metadataSaved != true {
            entries[index].metadataSaved = true
            changed = true
        }
        if changed { persist() }
    }

    /// Apple へ書き始めた（書く直前に付ける）
    func markWriteStarted(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].writeStarted != true else { return }
        entries[index].writeStarted = true
        persist()
    }

    /// 利用者に知らせた
    func markNoticed(_ ids: Set<UUID>) {
        var changed = false
        for index in entries.indices where ids.contains(entries[index].id) && entries[index].noticed != true {
            entries[index].noticed = true
            changed = true
        }
        if changed { persist() }
    }

    /// 書けたと確かめた（ids のうち記録にあるもの。「Apple Calendarに保存」の続きから行うとき、作り直さない）
    func markCreated(_ ids: Set<UUID>) {
        var changed = false
        for index in entries.indices where ids.contains(entries[index].id) && entries[index].created != true {
            entries[index].created = true
            changed = true
        }
        if changed { persist() }
    }

    /// 書く前に記録する（同じ id の記録があれば置き換える）
    func begin(_ new: [SaveJournalEntry]) {
        let ids = Set(new.map(\.id))
        entries = entries.filter { !ids.contains($0.id) } + new
        persist()
    }

    /// Apple カレンダーに書けた直後に、その予定の鍵を記録する
    func recordKey(_ key: String, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].appleKey = key
        persist()
    }

    /// 済んだ（または書いていないと確かめた）記録を消す
    func finish(_ ids: Set<UUID>) {
        guard entries.contains(where: { ids.contains($0.id) }) else { return }
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    func entry(id: UUID) -> SaveJournalEntry? {
        entries.first { $0.id == id }
    }

    /// 「Apple Calendarに保存」の途中の記録（元のローカルの予定から引く）
    func move(from localID: UUID) -> SaveJournalEntry? {
        entries.first { $0.movedFromLocalID == localID }
    }

    /// 記録に書けなくても、保存そのものは止めない（記録は途中で終わったときの手がかり）
    private func persist() {
        try? file?.save(entries)
    }
}

/// 次に開いたときの、記録 1 件の扱い（spec §89.9）
enum JournalRecovery {
    enum Action: Equatable {
        /// 結び付いている：設定を当てて記録を消す
        case linked
        /// 記録した鍵の予定がある：その鍵で結び付け直し、設定を当てて記録を消す
        case adopt(key: String)
        /// 何も書いていない（書き始めていない）・記録した鍵の予定がないと確かめた新しい予定でない：記録を消す
        case drop
        /// 書けたか分からない：自動では書き直さず、確かめてもらう
        case askUser
        /// まだ確かめられない（権限がないなど）：残す
        case keep
    }

    /// isLinked：結び付けにその id がある。itemExists：結び付けか記録の鍵の予定を引けたか（鍵がない・確かめられないときは nil）。
    /// canTrustAbsence：引けないことを信じてよいか
    static func action(for entry: SaveJournalEntry, isLinked: Bool, itemExists: Bool?, canTrustAbsence: Bool) -> Action {
        if isLinked {
            // 「Apple Calendarに保存」で作った予定が Apple 側で消えていたら、作ってあるとは言わず、確かめてもらう
            if entry.movedFromLocalID != nil, itemExists == false, canTrustAbsence { return .askUser }
            return .linked
        }
        guard let key = entry.appleKey else {
            // 書き始めていなければ、何も書いていない（複数日の、まだ書いていない日など）
            return entry.writeStarted == true ? .askUser : .drop
        }
        switch itemExists {
        case true?: return .adopt(key: key)
        // 鍵は書けたあとにしか記録しないので、書けたのは確か。いま引けないのは、消されたのか識別子が変わったのか区別できないので、確かめてもらう
        case false?: return canTrustAbsence ? .askUser : .keep
        case nil: return .keep
        }
    }
}
