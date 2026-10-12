import Foundation

/// 3 分割画面の下カレンダーの縦の位置（v1.1「3 分割予定編集画面：下部カレンダー」「独自年月スクロールバー」）。
/// 画面に依らない計算だけを置く。
///
/// カレンダーは週を途切れず縦に並べる。位置は「いちばん上に見えている週の番号（小数あり）」で表す。
/// 番号 0 は基準の週（作ったときの月の 1 日を含む週）。カレンダー本体は指でスクロールせず、年月バーでだけ動かす
struct EditorCalendarAxis: Equatable {
    /// 番号 0 の週
    let origin: CalendarWeek
    /// 内部の安全上限（基準の週から前後それぞれ約 100 年）
    static let maxWeeks = 52 * 100

    init(around month: CalendarMonth) {
        origin = CalendarWeek(containing: month.firstDay)
    }

    func week(at index: Int) -> CalendarWeek {
        origin.adding(weeks: index)
    }

    func index(of week: CalendarWeek) -> Int {
        origin.weeks(to: week)
    }

    func clamp(_ offset: Double) -> Double {
        min(max(offset, -Double(Self.maxWeeks)), Double(Self.maxWeeks))
    }

    /// その月へ飛ぶ位置。月の 1 日を含む週がいちばん上の列に来る（v1.1「年月バーのタップ」）
    func offset(jumpingTo month: CalendarMonth) -> Double {
        Double(index(of: CalendarWeek(containing: month.firstDay)))
    }

    /// いちばん上に見えている週
    func topWeek(at offset: Double) -> CalendarWeek {
        week(at: Int(offset.rounded(.down)))
    }

    // MARK: - カレンダー本体

    /// カレンダーの枠の中の点が、どの日か。row の高さ・列の幅は画面から渡す
    func day(atX x: Double, y: Double, offset: Double, rowHeight: Double, columnWidth: Double) -> CalendarDay? {
        guard rowHeight > 0, columnWidth > 0, y >= 0 else { return nil }
        let row = Int((y / rowHeight + offset).rounded(.down))
        let column = min(max(Int((x / columnWidth).rounded(.down)), 0), 6)
        return week(at: row).days[column]
    }

    /// 見えている週の番号（一部だけ見えている週も含む）
    func visibleWeekIndices(offset: Double, visibleRows: Int) -> ClosedRange<Int> {
        let first = Int(offset.rounded(.down))
        return first...(first + visibleRows)
    }

    // MARK: - 年月バー

    /// バーに並べる月。バーの見えている範囲（いちばん上の週の前後 spanWeeks 週）の月の 1 日ごとに 1 つ
    func barMonths(offset: Double, spanWeeks: Int) -> [(month: CalendarMonth, weekIndex: Int)] {
        let firstIndex = Int(offset.rounded(.down)) - spanWeeks
        let lastIndex = Int(offset.rounded(.up)) + spanWeeks
        var month = week(at: firstIndex).stickyMonth
        var result: [(month: CalendarMonth, weekIndex: Int)] = []
        while true {
            let index = self.index(of: CalendarWeek(containing: month.firstDay))
            if index > lastIndex { break }
            if index >= firstIndex { result.append((month, index)) }
            month = month.adding(months: 1)
        }
        return result
    }

    /// バーの上で、その週の番号が来る高さ。固定帯の上端に、いちばん上に見えている週が来る
    static func barY(weekIndex: Int, offset: Double, bandTop: Double, weekHeight: Double) -> Double {
        bandTop + (Double(weekIndex) - offset) * weekHeight
    }

    // MARK: - 長押しで動かす（2026-10-12 ユーザー決定。滑らせて慣性で回すのはやめた）

    /// 長押しでどちらへ動かすか。バーの真ん中（表示範囲帯の真ん中）より上を押したら上（過去）へ、下なら下（未来）へ
    static func holdDirection(pressY: Double, barHeight: Double) -> Double {
        pressY < barHeight / 2 ? -1 : 1
    }

    /// 長押ししている間の位置。一定のゆっくりした速さで動き、月にはスナップしない
    static func offset(afterHolding seconds: Double, from start: Double, direction: Double, weeksPerSecond: Double) -> Double {
        start + direction * max(0, seconds) * weeksPerSecond
    }
}
