import Foundation

/// ホームの時計（spec §6・追加仕様書 §44。2026-10-14 の修正指示）の計算。画面に依らない計算だけを置く。
/// 時計そのものは、現在時刻を指す普通のアナログ時計。外周のリング 1 周が 60 分で、
/// いまの分の位置から出発の分の位置まで、時計回りに残り時間の弧を描く
/// （例：16:52 → 17:15 なら、52 分の位置から 15 分の位置まで 23 分ぶん＝138°）
enum HomeClockMath {
    /// 時計を出すのは、出発（今は暫定で予定開始）まで 60 分以内のとき（spec §6「出発 60 分前から」）。リング 1 周が 60 分
    static let windowMinutes = 60
    static let degreesPerMinute = 6.0
    /// 「いま」と「出発」がこの分数より近いときは、「いま」の文字を出さない（重ならないように。仮）
    static let labelGapMinutes = 5

    /// 残り時間の弧の色の段階（spec §6：60〜31 分・30〜16 分・15〜0 分）
    enum Band: Equatable {
        case plenty
        case half
        case last
    }

    /// 時計に描くもの。角度は 12 時の位置から時計回り。
    /// 0 分や 0 時をまたいでも針や弧が逆回りしないよう、日をまたいで続く角度で持つ（画面では 360° で割った余りの位置に出る）
    struct Face: Equatable {
        /// いま（分の頭にそろえる。iPhone の時計の表示と合わせる）と、数える先
        let now: Date
        let target: Date
        let remainingMinutes: Int
        let hourHandDegrees: Double
        let minuteHandDegrees: Double

        /// 弧の始まり（いま）は分針の位置
        var ringStartDegrees: Double { minuteHandDegrees }
        var ringSweepDegrees: Double { Double(remainingMinutes) * HomeClockMath.degreesPerMinute }
        var band: Band { HomeClockMath.band(remainingMinutes: remainingMinutes) }
        /// 「いま」の文字を出すか（弧の両端が近いとき＝残りがごく少ない・ほぼ 1 周のときは出さない）
        var showsNowLabel: Bool {
            remainingMinutes >= HomeClockMath.labelGapMinutes
                && remainingMinutes <= HomeClockMath.windowMinutes - HomeClockMath.labelGapMinutes
        }
    }

    /// いまから target までが 60 分以内（0 分より多い）なら、時計に描くものを返す
    static func face(now: Date, target: Date, calendar: Calendar = .timyCue) -> Face? {
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let remaining = Int((target.timeIntervalSince(minuteStart) / 60).rounded(.down))
        guard remaining > 0, remaining <= windowMinutes else { return nil }
        let minutes = continuousMinutes(minuteStart, calendar: calendar)
        return Face(now: minuteStart,
                    target: target,
                    remainingMinutes: remaining,
                    hourHandDegrees: Double(minutes) * 0.5,
                    minuteHandDegrees: Double(minutes) * degreesPerMinute)
    }

    static func band(remainingMinutes: Int) -> Band {
        switch remainingMinutes {
        case 31...: .plenty
        case 16...30: .half
        default: .last
        }
    }

    /// 時計の下に出す「16:52 → 17:15」
    static func flowText(now: Date, target: Date, calendar: Calendar = .timyCue) -> String {
        "\(TimeText.hourMinute(Clock.minuteOfDay(now, calendar: calendar))) → \(TimeText.hourMinute(Clock.minuteOfDay(target, calendar: calendar)))"
    }

    /// 2001 年 1 月 1 日 0:00（その土地の時刻）からの通しの分。60 で割った余りがその時刻の分、720 で割った余りが 12 時間制の分
    private static func continuousMinutes(_ date: Date, calendar: Calendar) -> Int {
        let offset = TimeInterval(calendar.timeZone.secondsFromGMT(for: date))
        return Int(((date.timeIntervalSinceReferenceDate + offset) / 60).rounded(.down))
    }
}
