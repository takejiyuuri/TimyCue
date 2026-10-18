import Foundation

/// TimyCue のローカル予定と Apple カレンダーの予定の重複候補 1 組（Q42-8・Q50）
struct DuplicateCandidate: Identifiable, Equatable {
    let local: CalendarEvent
    let apple: CalendarEvent

    /// 組み合わせの鍵。「両方残す」を選んだ組や、ホームで知らせた組を覚えておくのに使う
    var id: String { Self.key(localID: local.id, appleID: apple.id) }

    static func key(localID: UUID, appleID: UUID) -> String {
        "\(localID.uuidString)|\(appleID.uuidString)"
    }
}

/// 重複候補の見つけ方と、TimyCue の情報（到着目標など）の引き継ぎ方（Q42-8・Q50）。画面に依らない決まりだけを置く
enum DuplicateCandidates {
    /// 同じ日付＋開始時刻が完全に一致する組を候補にする（Q42-8）。開始時刻が違えば、名前や場所が同じでも候補にしない。
    /// 終日の予定どうしは、同じ日なら候補にする。「両方残す」を選んだ組はもう聞かない（Q50）。
    /// 連携中に「TimyCue のみ」を選んで保存したローカルの予定は候補にしない（spec §89.7・Q104）。
    /// ただし「Apple Calendarに保存」が途中で止まって両方に残った元の予定（pendingMoveLocalIDs）は、片方を選べるよう候補にする
    static func find(local: [CalendarEvent], apple: [CalendarEvent], keptBoth: Set<String>,
                     pendingMoveLocalIDs: Set<UUID> = []) -> [DuplicateCandidate] {
        struct Slot: Hashable {
            let day: CalendarDay
            let isAllDay: Bool
            let startMinute: MinuteOfDay
        }
        func slot(_ event: CalendarEvent) -> Slot {
            Slot(day: event.day, isAllDay: event.isAllDay, startMinute: event.isAllDay ? 0 : event.startMinute)
        }
        let appleBySlot = Dictionary(grouping: apple, by: slot)
        var result: [DuplicateCandidate] = []
        let targets = local.filter { $0.savedOnDeviceWhileLinked != true || pendingMoveLocalIDs.contains($0.id) }
        for localEvent in targets.sorted(by: { ($0.day, $0.startMinute) < ($1.day, $1.startMinute) }) {
            for appleEvent in appleBySlot[slot(localEvent)] ?? [] {
                let candidate = DuplicateCandidate(local: localEvent, apple: appleEvent)
                if !keptBoth.contains(candidate.id) { result.append(candidate) }
            }
        }
        return result
    }

    /// ユーザーが付けた TimyCue の設定があるか。色は Apple カレンダーの色から自動で付くので見ない
    static func hasUserSettings(_ metadata: TimyCueEventMetadata?) -> Bool {
        guard let metadata else { return false }
        return withoutColor(metadata) != withoutColor(TimyCueEventMetadata())
    }

    /// 両方にユーザーが付けた設定があって、中身が違う。勝手に上書きせず、どちらを使うか確かめる（Q50）
    static func settingsConflict(local: TimyCueEventMetadata?, apple: TimyCueEventMetadata?) -> Bool {
        guard hasUserSettings(local), hasUserSettings(apple), let local, let apple else { return false }
        return withoutColor(local) != withoutColor(apple)
    }

    /// 「Apple Calendarの予定を使う」で、Apple の予定に結び付ける TimyCue の情報。
    /// ぶつからなければ、ローカル予定の設定をできるだけ引き継ぐ。ぶつかるときは preferLocal で選んでもらった方
    static func mergedMetadata(local: TimyCueEventMetadata?, apple: TimyCueEventMetadata?, preferLocal: Bool?) -> TimyCueEventMetadata {
        if settingsConflict(local: local, apple: apple) {
            return (preferLocal ?? false) ? local! : apple!
        }
        if hasUserSettings(local), let local { return local }
        return apple ?? local ?? TimyCueEventMetadata()
    }

    private static func withoutColor(_ metadata: TimyCueEventMetadata) -> TimyCueEventMetadata {
        var copy = metadata
        copy.color = TimyCueEventMetadata().color
        return copy
    }
}
