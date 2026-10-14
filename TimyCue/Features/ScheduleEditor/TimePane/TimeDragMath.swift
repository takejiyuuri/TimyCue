import Foundation

/// 時間画面で、仮予定を動かしたり伸ばしたりするときの計算（仕様 §38・§40・§41）。画面に依らない計算だけを置く。
enum TimeDragMath {
    /// 動かしたとき・終了を伸ばしたときに合わせる刻み（分）。どちらも時計の 5 分おき（14:00・14:05…）。
    /// 前は §40 の例「14:37」のとおり開始は 1 分単位だったが、5 分おきにした（2026-10-14 ユーザー決定）
    static let step = 5
    /// 終了のハンドルで縮められる、いちばん短い所要時間（分。仮）
    static let minimumDuration = 5

    /// 指を dy だけ動かしたときの、新しい開始時刻（§40）。5 分おきにそろえ、0:00〜23:55 に収める
    static func startMinute(afterDragging dy: Double, from start: MinuteOfDay, hourHeight: Double) -> MinuteOfDay {
        let moved = snap(Double(start) + minutes(for: dy, hourHeight: hourHeight))
        return min(max(moved, 0), MinuteOfDay.minutesPerDay - step)
    }

    /// 下端のハンドルを dy だけ動かしたときの、新しい終了時刻（§41）。時計の 5 分おきに合わせ、開始より minimumDuration 分は後にする
    static func endMinute(afterDragging dy: Double, from end: MinuteOfDay, start: MinuteOfDay, hourHeight: Double) -> MinuteOfDay {
        let moved = snap(Double(end) + minutes(for: dy, hourHeight: hourHeight))
        return min(max(moved, start + minimumDuration), MinuteOfDay.minutesPerDay)
    }

    /// 分ホイールの刻み（分）と、並べる値（0:00〜23:55 を通しで並べるので、0 分をまたぐと時も変わる。2026-10-13 実機の指摘）
    static let wheelStep = 5
    static let wheelMinutes: [MinuteOfDay] = Array(stride(from: 0, to: MinuteOfDay.minutesPerDay, by: wheelStep))

    /// 「時」を押して分ホイールで分を選んだときの開始時刻（§38）
    static func startMinute(hour: Int, minute: Int) -> MinuteOfDay {
        clampToDay(min(max(hour, 0), 23) * 60 + min(max(minute, 0), 59))
    }

    private static func minutes(for dy: Double, hourHeight: Double) -> Double {
        hourHeight > 0 ? dy / hourHeight * 60 : 0
    }

    private static func snap(_ minute: Double) -> MinuteOfDay {
        Int((minute / Double(step)).rounded()) * step
    }

    private static func clampToDay(_ minute: MinuteOfDay) -> MinuteOfDay {
        min(max(minute, 0), MinuteOfDay.minutesPerDay - 1)
    }
}
