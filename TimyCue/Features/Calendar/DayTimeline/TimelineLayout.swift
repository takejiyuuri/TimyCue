import Foundation

/// 1 日タイムラインで、予定ブロックを横に何列に分けて、どの列に置くか（仕様 §29）
struct TimelinePlacement: Equatable {
    /// 左から何列目か（0 始まり）
    let column: Int
    /// その時間帯を何列に分けているか
    let columnCount: Int
}

/// 1 日タイムラインの並べ方の決まり（仕様 §26・§29）。画面に依らない計算だけを置く。
enum TimelineLayout {
    /// 終了時刻のない予定・とても短い予定を、重なりの判断で何分ぶんとして扱うか（仮。仕様 §86）
    static let minimumMinutes = 15

    /// 重なりの判断に使う、その予定の終わり（分）
    static func layoutEnd(of event: CalendarEvent) -> MinuteOfDay {
        event.startMinute + max(event.durationMinutes ?? 0, minimumMinutes)
    }

    /// 同じ時間帯の予定は上下に重ねず、横に分ける（仕様 §29：2 件なら 2 列、3 件なら 3 列）。
    /// 重なりがつながっているひとかたまりごとに列の数を決め、空いている左の列から順に入れる。終日の予定は含めない（仕様 §30）
    static func placements(for events: [CalendarEvent]) -> [UUID: TimelinePlacement] {
        let timed = events
            .filter { !$0.isAllDay }
            .sorted { ($0.startMinute, -layoutEnd(of: $0), $0.id.uuidString) < ($1.startMinute, -layoutEnd(of: $1), $1.id.uuidString) }

        var result: [UUID: TimelinePlacement] = [:]
        var cluster: [(id: UUID, column: Int)] = []
        var columnEnds: [MinuteOfDay] = []
        var clusterEnd = MinuteOfDay.min

        func closeCluster() {
            for item in cluster {
                result[item.id] = TimelinePlacement(column: item.column, columnCount: columnEnds.count)
            }
            cluster = []
            columnEnds = []
        }

        for event in timed {
            let start = event.startMinute
            let end = layoutEnd(of: event)
            if !cluster.isEmpty && start >= clusterEnd {
                closeCluster()
            }
            if let free = columnEnds.firstIndex(where: { $0 <= start }) {
                columnEnds[free] = end
                cluster.append((event.id, free))
            } else {
                columnEnds.append(end)
                cluster.append((event.id, columnEnds.count - 1))
            }
            clusterEnd = cluster.count == 1 ? end : max(clusterEnd, end)
        }
        closeCluster()
        return result
    }

    /// 開いたときに最初に見せる時刻。今日なら現在時刻の少し前、ほかの日は最初の予定の少し前、予定がなければ 8:00（仮）
    static func initialMinute(events: [CalendarEvent], isToday: Bool, now: MinuteOfDay, leadMinutes: Int = 60) -> MinuteOfDay {
        if isToday { return max(0, now - leadMinutes) }
        if let first = events.filter({ !$0.isAllDay }).map(\.startMinute).min() {
            return max(0, first - leadMinutes)
        }
        return 8 * 60
    }
}
