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
    /// 画面の上で、その予定ブロックが下に伸びている所（分）。
    /// 終了時刻のない予定やとても短い予定は、描く最低の高さ（minimumVisualMinutes 分ぶん）まで伸びて見える。
    /// これは見た目の並べ方だけに使い、終了時刻としては扱わない（Q15）
    static func visualEnd(of event: CalendarEvent, minimumVisualMinutes: Double) -> Double {
        Double(event.startMinute) + max(Double(event.durationMinutes ?? 0), minimumVisualMinutes)
    }

    /// 同じ時間帯の予定は上下に重ねず、横に分ける（仕様 §29：2 件なら 2 列、3 件なら 3 列）。
    /// 画面の上で重なって見えるひとかたまりごとに列の数を決め、空いている左の列から順に入れる。終日の予定は含めない（仕様 §30）
    static func placements(for events: [CalendarEvent], minimumVisualMinutes: Double) -> [UUID: TimelinePlacement] {
        let end = { (event: CalendarEvent) in visualEnd(of: event, minimumVisualMinutes: minimumVisualMinutes) }
        let timed = events
            .filter { !$0.isAllDay }
            .sorted { ($0.startMinute, -end($0), $0.id.uuidString) < ($1.startMinute, -end($1), $1.id.uuidString) }

        var result: [UUID: TimelinePlacement] = [:]
        var cluster: [(id: UUID, column: Int)] = []
        var columnEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func closeCluster() {
            for item in cluster {
                result[item.id] = TimelinePlacement(column: item.column, columnCount: columnEnds.count)
            }
            cluster = []
            columnEnds = []
        }

        for event in timed {
            let start = Double(event.startMinute)
            let eventEnd = end(event)
            if !cluster.isEmpty && start >= clusterEnd {
                closeCluster()
            }
            if let free = columnEnds.firstIndex(where: { $0 <= start }) {
                columnEnds[free] = eventEnd
                cluster.append((event.id, free))
            } else {
                columnEnds.append(eventEnd)
                cluster.append((event.id, columnEnds.count - 1))
            }
            clusterEnd = cluster.count == 1 ? eventEnd : max(clusterEnd, eventEnd)
        }
        closeCluster()
        return result
    }

    /// 描く最低の高さが、その倍率で何分ぶんにあたるか
    static func minimumVisualMinutes(blockHeight: Double, hourHeight: Double) -> Double {
        hourHeight > 0 ? blockHeight / hourHeight * 60 : 0
    }

    /// タイムラインの中身の上から y の位置が何時何分か（分。小数あり）。ピンチの中心の時刻を求めるのに使う（Q16）
    static func minute(atContentY y: Double, hourHeight: Double, topInset: Double) -> Double {
        guard hourHeight > 0 else { return 0 }
        return min(max((y - topInset) / hourHeight * 60, 0), Double(MinuteOfDay.minutesPerDay))
    }

    /// 開いたときに最初に見せる時刻（Q14）。今日なら現在時刻の約 1 時間前、ほかの日は最初の予定の約 1 時間前、予定がなければ 8:00
    static func initialMinute(events: [CalendarEvent], isToday: Bool, now: MinuteOfDay, leadMinutes: Int = 60) -> MinuteOfDay {
        if isToday { return max(0, now - leadMinutes) }
        if let first = events.filter({ !$0.isAllDay }).map(\.startMinute).min() {
            return max(0, first - leadMinutes)
        }
        return 8 * 60
    }
}
