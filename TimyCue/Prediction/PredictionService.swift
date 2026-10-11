import Foundation

/// 「予測で一括」（仕様 §19）の入口。本当の予測アルゴリズムは未決（報告 Q13）なので、今は差し替え前提のモックだけ。
protocol PredictionService {
    /// 各日の開始時刻の候補。候補が出せない日は含めない。結果は保存せず、仮の時刻として入れるだけ
    func suggestStartMinutes(for days: [CalendarDay],
                             content: EventContent,
                             existing: [CalendarEvent]) -> [CalendarDay: MinuteOfDay]
}

/// モック：同じ予定名の過去の予定で、いちばん多い開始時刻を全部の日に入れる。
struct SameTitlePredictionService: PredictionService {
    func suggestStartMinutes(for days: [CalendarDay],
                             content: EventContent,
                             existing: [CalendarEvent]) -> [CalendarDay: MinuteOfDay] {
        guard !content.title.isEmpty else { return [:] }
        let history = existing.filter { $0.content.title == content.title && !$0.isAllDay }
        let counts = Dictionary(grouping: history, by: \.startMinute).mapValues(\.count)
        // 同じ回数なら早い時刻を選んで、結果が毎回同じになるようにする
        guard let best = counts.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) })?.key else { return [:] }
        return Dictionary(uniqueKeysWithValues: days.map { ($0, best) })
    }
}
