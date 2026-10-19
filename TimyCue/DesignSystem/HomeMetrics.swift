import SwiftUI

/// ホームの時計（spec §6・追加仕様書 §44）の寸法と文字の大きさ。実機で確かめて決めるので、値はここに集める。
/// リングの太さ 6％・中央の数字 48pt（外径 74％のとき）・1 分ごとの動き 0.45 秒は 2026-10-14 に決めた本命の値。ほかの値は仮。
/// 〜Ratio の割合は、すべて時計の外径（外周のリングの外側まで）に対する割合（基準を 1 つにそろえる。2026-10-14）。
/// 下の文字・線の値（standard）は外径 74％（画面の幅 393pt で 290.8pt）のときの値で、H2 の Home（外径 40％）では
/// HomeClockStyle.scaled で外径に合わせて縮める（2026-10-16 Q85。数字は外径の 17％で約 27pt）
enum HomeMetrics {
    /// 時計の外径（外周のリングの外側まで）を、画面の幅の何割にするか。H2 の Home は 40％（spec §88.3。2026-10-16 の実機確認で
    /// 時計 40％＋人型 36pt が良好。前の Home は 74％だった）
    static let clockWidthRatio: CGFloat = 0.40
    /// 外周のリングの太さ。7％ではリングが主役になりすぎるので 6％（2026-10-14 決定）。リングと文字盤のすき間は pt
    static let ringWidthRatio: CGFloat = 0.06
    static let ringFaceGap: CGFloat = 4
    /// 15 分ごとの目盛り（リングを横切る線）の太さと、リングからはみ出す長さ
    static let quarterTickWidth: CGFloat = 2
    static let quarterTickOverhang: CGFloat = 3
    /// 文字盤の時の目盛りと、文字盤のふちからの距離
    static let hourTickLength: CGFloat = 7
    static let hourTickWidth: CGFloat = 2
    static let hourTickInset: CGFloat = 5
    /// 針の長さと太さ。針の根元は中央のプレートの下に隠れるので、そのぶん長めにする（実機確認用の仮値。
    /// 時針がプレートから見える長さ（393pt 幅で約 28pt）が短くて向きを読みづらければ、実機で見てから少し伸ばす）
    static let hourHandLengthRatio: CGFloat = 0.265
    static let minuteHandLengthRatio: CGFloat = 0.365
    static let hourHandWidth: CGFloat = 6
    static let minuteHandWidth: CGFloat = 3.5
    /// 中央の円形プレートの直径（393pt 幅で約 99pt。実機確認用の仮値。数字 48pt と「出発まで」が窮屈でなければ採用）とふちの線
    static let centerPlateRatio: CGFloat = 0.34
    static let centerPlateBorderWidth: CGFloat = 1
    /// 「いま」「出発」の丸の直径。「出発」の方を少し大きく濃くする
    static let nowDotRatio: CGFloat = 0.03
    static let targetDotRatio: CGFloat = 0.043
    static let nowLabelFont = Font.system(size: 11, weight: .medium)
    static let targetLabelFont = Font.system(size: 12, weight: .bold)
    /// 「いま」「出発」の文字を、リングの外側からどれだけ離して出すか
    static let markerLabelGap: CGFloat = 13
    /// 「いま」と「出発」の丸がちょうど重なるとき（60 分前）、内側・外側へずらす量
    static let coincideShiftRatio: CGFloat = 0.018
    /// 時計の上下にあける余白（リングの外に出す「いま」「出発」の文字の分）
    static let clockLabelRoom: CGFloat = 20
    /// 中央の「出発まで」と「23分」の文字の大きさ（pt。外径 74％のときの値。数字の 48pt は 2026-10-14 決定）
    static let centerCaptionSize: CGFloat = 13
    static let centerNumberSize: CGFloat = 48
    static let centerUnitSize: CGFloat = 18
    /// 時計を小さくするとき（2026-10-16 Q85。仮の値）：393pt 幅で外径 74％のときの外径を基準に、文字・針の太さ・目盛りを比例で縮める
    static let referenceDiameter: CGFloat = 393 * 0.74
    /// 小さい時計の中央の数字は外径の 17％（45％で約 30pt が仮の基準）
    static let scaledNumberRatio: CGFloat = 0.17
    /// 時計の中の文字の下限（「出発まで」「開始まで」は原則 11pt 未満にしない）
    static let minimumClockText: CGFloat = 11
    /// 小さい時計の針の太さの下限（向きを読めるように）
    static let minimumHourHandWidth: CGFloat = 2
    static let minimumMinuteHandWidth: CGFloat = 1.5
    /// 時計の下の「16:52 → 17:15 出発予定」
    static let flowFont = Font.system(size: 15, weight: .medium).monospacedDigit()
    /// 1 分たつごとに、弧と針を動かす時間（秒）
    static let minuteAnimation: Double = 0.45
}

/// 時計の中の文字・線の大きさ（pt）。今の Home の時計（外径 74％）は standard のまま。
/// 時計を小さくするときは scaled で、外径に合わせて縮める（2026-10-16 Q85）。リングの太さ・中央のプレート・針の長さは
/// もとから外径に対する割合なので、ここでは持たない
struct HomeClockStyle: Equatable {
    var ringFaceGap: CGFloat
    var quarterTickWidth: CGFloat
    var quarterTickOverhang: CGFloat
    var hourTickLength: CGFloat
    var hourTickWidth: CGFloat
    var hourTickInset: CGFloat
    var hourHandWidth: CGFloat
    var minuteHandWidth: CGFloat
    var centerCaptionSize: CGFloat
    var centerNumberSize: CGFloat
    var centerUnitSize: CGFloat

    /// 今の Home の時計（外径 74％。2026-10-14 決定の値）
    static let standard = HomeClockStyle(
        ringFaceGap: HomeMetrics.ringFaceGap,
        quarterTickWidth: HomeMetrics.quarterTickWidth,
        quarterTickOverhang: HomeMetrics.quarterTickOverhang,
        hourTickLength: HomeMetrics.hourTickLength,
        hourTickWidth: HomeMetrics.hourTickWidth,
        hourTickInset: HomeMetrics.hourTickInset,
        hourHandWidth: HomeMetrics.hourHandWidth,
        minuteHandWidth: HomeMetrics.minuteHandWidth,
        centerCaptionSize: HomeMetrics.centerCaptionSize,
        centerNumberSize: HomeMetrics.centerNumberSize,
        centerUnitSize: HomeMetrics.centerUnitSize)

    /// 外径に合わせて縮めた値。standard を、外径 74％（393pt 幅）からの比で縮める（大きくはしない）。
    /// 中央の数字だけは外径の 17％（45％で約 30pt）。文字は 11pt、針は読める太さより小さくしない
    static func scaled(diameter: CGFloat) -> HomeClockStyle {
        let ratio = min(1, diameter / HomeMetrics.referenceDiameter)
        let base = standard
        return HomeClockStyle(
            ringFaceGap: base.ringFaceGap * ratio,
            quarterTickWidth: max(1, base.quarterTickWidth * ratio),
            quarterTickOverhang: base.quarterTickOverhang * ratio,
            hourTickLength: base.hourTickLength * ratio,
            hourTickWidth: max(1, base.hourTickWidth * ratio),
            hourTickInset: base.hourTickInset * ratio,
            hourHandWidth: max(HomeMetrics.minimumHourHandWidth, base.hourHandWidth * ratio),
            minuteHandWidth: max(HomeMetrics.minimumMinuteHandWidth, base.minuteHandWidth * ratio),
            centerCaptionSize: max(HomeMetrics.minimumClockText, base.centerCaptionSize * ratio),
            centerNumberSize: min(base.centerNumberSize, diameter * HomeMetrics.scaledNumberRatio),
            centerUnitSize: max(HomeMetrics.minimumClockText, base.centerUnitSize * ratio))
    }

    var centerCaptionFont: Font { .system(size: centerCaptionSize, weight: .medium) }
    var centerNumberFont: Font { .system(size: centerNumberSize, weight: .bold, design: .rounded).monospacedDigit() }
    var centerUnitFont: Font { .system(size: centerUnitSize, weight: .semibold, design: .rounded) }
}
