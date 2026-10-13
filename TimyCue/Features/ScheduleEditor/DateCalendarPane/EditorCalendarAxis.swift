import Foundation

/// 3 分割画面の下カレンダーの縦の位置（2026-10-13 ユーザー決定「3 分割画面のカレンダー」）。
/// 画面に依らない計算だけを置く。
///
/// 月ごとに区切って縦に並べる。月の初めには 1 行空けて月を出し、月をまたぐ週は 2 行に分ける
/// （例：10/26〜10/31 の行 → 「11月」の行 → 11/1 の行）。ほかの月の日は出さない。
/// 位置は「いちばん上に見えている所」を、日付の行の高さを 1 とした単位で表す。月の行の高さは monthRowRatio。
/// 0 は基準の月（作ったときの月）の月の行の上端。カレンダー本体は指でスクロールせず、左右のバーでだけ動かす
struct EditorCalendarAxis: Equatable {
    /// 基準の月
    let origin: CalendarMonth
    /// 月の行の高さ（日付の行を 1 として）
    let monthRowRatio: Double
    /// 基準の月の 1 日の曜日（月曜 0）。月をたどるときに、次の月の 1 日の曜日を足し算で求める（遠くまで動かしても軽いように）
    private let originFirstWeekday: Int
    /// 内部の安全上限（基準の月から前後それぞれ約 100 年ぶんの高さ）
    static let maxOffset = 12.0 * 100 * 6

    /// 1 行ぶん
    enum Line: Equatable {
        /// 月の初めの、月を出す行
        case month(CalendarMonth)
        /// その月の日だけを並べた週の行（ほかの月の日は空ける）
        case week(CalendarMonth, CalendarWeek)
    }

    struct PlacedLine: Equatable {
        let line: Line
        /// 上端の位置
        let top: Double
        let height: Double
    }

    init(around month: CalendarMonth, monthRowRatio: Double) {
        origin = month
        self.monthRowRatio = monthRowRatio
        originFirstWeekday = month.firstDay.weekdayIndexFromMonday()
    }

    // MARK: - 月の大きさと位置

    /// その月の日数
    static func dayCount(of month: CalendarMonth) -> Int {
        switch month.month {
        case 2:
            let leap = (month.year % 4 == 0 && month.year % 100 != 0) || month.year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// その月の週の行の数（4〜6）。firstWeekday はその月の 1 日の曜日（月曜 0）
    static func weekCount(of month: CalendarMonth, firstWeekday: Int) -> Int {
        (firstWeekday + dayCount(of: month) + 6) / 7
    }

    static func weekCount(of month: CalendarMonth) -> Int {
        weekCount(of: month, firstWeekday: month.firstDay.weekdayIndexFromMonday())
    }

    /// 基準の月からたどった、ある月とその上端・1 日の曜日
    private struct Cursor {
        var month: CalendarMonth
        var top: Double
        var firstWeekday: Int
    }

    private func height(of cursor: Cursor) -> Double {
        monthRowRatio + Double(Self.weekCount(of: cursor.month, firstWeekday: cursor.firstWeekday))
    }

    private func next(_ cursor: Cursor) -> Cursor {
        Cursor(month: cursor.month.adding(months: 1),
               top: cursor.top + height(of: cursor),
               firstWeekday: (cursor.firstWeekday + Self.dayCount(of: cursor.month)) % 7)
    }

    private func previous(_ cursor: Cursor) -> Cursor {
        let month = cursor.month.adding(months: -1)
        let firstWeekday = ((cursor.firstWeekday - Self.dayCount(of: month)) % 7 + 7) % 7
        var result = Cursor(month: month, top: 0, firstWeekday: firstWeekday)
        result.top = cursor.top - height(of: result)
        return result
    }

    /// その月までたどる
    private func cursor(for month: CalendarMonth) -> Cursor {
        var cursor = Cursor(month: origin, top: 0, firstWeekday: originFirstWeekday)
        while cursor.month < month { cursor = next(cursor) }
        while cursor.month > month { cursor = previous(cursor) }
        return cursor
    }

    /// その位置を含む月までたどる
    private func cursor(at position: Double) -> Cursor {
        var cursor = Cursor(month: origin, top: 0, firstWeekday: originFirstWeekday)
        while position >= cursor.top + height(of: cursor) { cursor = next(cursor) }
        while position < cursor.top { cursor = previous(cursor) }
        return cursor
    }

    /// 1 か月ぶんの高さ（月の行＋週の行）
    func height(of month: CalendarMonth) -> Double {
        monthRowRatio + Double(Self.weekCount(of: month))
    }

    /// その月の月の行の上端の位置
    func top(of month: CalendarMonth) -> Double {
        cursor(for: month).top
    }

    /// その位置を含む月
    func month(at position: Double) -> CalendarMonth {
        cursor(at: position).month
    }

    func clamp(_ offset: Double) -> Double {
        min(max(offset, -Self.maxOffset), Self.maxOffset)
    }

    /// いちばん上の固定の年月に出す月。下から上がってきた月帯がいちばん上（固定の年月の位置）に重なったら次の月へ、
    /// 上へ戻して月帯がいちばん上を下へ抜けたら前の月へ戻る（2026-10-13 ユーザー決定）
    func topMonth(at offset: Double) -> CalendarMonth {
        month(at: offset)
    }

    /// いちばん上に固定して出す年月（例：2026年　10月）
    static func headerText(for month: CalendarMonth) -> String {
        "\(month.year)年　\(month.month)月"
    }

    /// 月の境目に入れる月帯の文字。1 月だけは年も出す（例：11月、2027年 1月）
    static func bandText(for month: CalendarMonth) -> String {
        month.month == 1 ? "\(month.year)年 1月" : month.monthLabel
    }

    // MARK: - 行

    /// 1 か月ぶんの行（月の行 → 週の行）
    func lines(of month: CalendarMonth) -> [PlacedLine] {
        lines(of: cursor(for: month))
    }

    private func lines(of cursor: Cursor) -> [PlacedLine] {
        var top = cursor.top
        var result = [PlacedLine(line: .month(cursor.month), top: top, height: monthRowRatio)]
        top += monthRowRatio
        let firstWeek = CalendarWeek(containing: cursor.month.firstDay)
        for index in 0..<Self.weekCount(of: cursor.month, firstWeekday: cursor.firstWeekday) {
            result.append(PlacedLine(line: .week(cursor.month, firstWeek.adding(weeks: index)), top: top, height: 1))
            top += 1
        }
        return result
    }

    /// 見えている行（一部だけ見えている行も含む）。visibleRows は日付の行で数えた見える高さ
    func visibleLines(offset: Double, visibleRows: Double) -> [PlacedLine] {
        var result: [PlacedLine] = []
        var cursor = self.cursor(at: offset)
        let bottom = offset + visibleRows
        while cursor.top < bottom {
            result.append(contentsOf: lines(of: cursor).filter { $0.top + $0.height > offset && $0.top < bottom })
            cursor = next(cursor)
        }
        return result
    }

    /// カレンダーの枠の中の点が、どの日か。月の行・ほかの月の空いた所は nil
    func day(atX x: Double, y: Double, offset: Double, rowHeight: Double, columnWidth: Double) -> CalendarDay? {
        guard rowHeight > 0, columnWidth > 0, y >= 0 else { return nil }
        let position = offset + y / rowHeight
        guard let placed = lines(of: cursor(at: position)).first(where: { position >= $0.top && position < $0.top + $0.height }),
              case .week(let lineMonth, let week) = placed.line else { return nil }
        let column = min(max(Int((x / columnWidth).rounded(.down)), 0), 6)
        let day = week.days[column]
        return CalendarMonth(day) == lineMonth ? day : nil
    }

    /// 日付の行の高さ。ふだんは見える高さの 1/visibleWeeks（6 行ぶん）。
    /// キーボードが出て下カレンダーが縮んだとき（§67）は minimum より低くせず、見える週を減らす
    static func rowHeight(gridHeight: Double, visibleWeeks: Double, minimum: Double) -> Double {
        guard visibleWeeks > 0 else { return minimum }
        return max(gridHeight / visibleWeeks, minimum)
    }

    // MARK: - 左右のバーでなぞって動かす（2026-10-13 ユーザー決定）

    /// なぞっている間は、指と同じ向き・同じだけ動く（上へなぞると先の月が下から出てくる）
    static func offset(afterDragging translation: Double, from start: Double, rowHeight: Double) -> Double {
        guard rowHeight > 0 else { return start }
        return start - translation / rowHeight
    }

    /// 指を離したときの速さ（行／秒。指と同じ向き）
    static func velocity(fromDragVelocity velocity: Double, rowHeight: Double) -> Double {
        rowHeight > 0 ? -velocity / rowHeight : 0
    }

    /// 指を離したあとは、iPhone のふつうのスクロールと同じ減り方で滑る（1 ミリ秒ごとに 0.998 倍）
    static let decelerationRate = 0.998
    /// これより遅くなったら止める（行／秒）
    static let inertiaStopVelocity = 0.05

    /// 滑っている間の 1 こま：seconds の間に動く量と、そのあとの速さ
    static func inertiaStep(velocity: Double, seconds: Double) -> (moved: Double, velocity: Double) {
        let factor = pow(decelerationRate, max(0, seconds) * 1000)
        let moved = velocity * (factor - 1) / (1000 * log(decelerationRate))
        return (moved, velocity * factor)
    }

    /// 滑りきるまでに動く量
    static func inertiaDistance(velocity: Double) -> Double {
        velocity / (-1000 * log(decelerationRate))
    }
}
