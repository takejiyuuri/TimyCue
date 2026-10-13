import SwiftUI

/// ホームの時計（spec §6・追加仕様書 §44）の寸法と文字の大きさ。実機で確かめて決めるので、値はここに集める。
/// 時計の外径 74％・リングの太さ 6％・中央の数字 48pt・1 分ごとの動き 0.45 秒は 2026-10-14 に決めた本命の値（まず実機で見る）。ほかの値は仮。
/// 〜Ratio の割合は、すべて時計の外径（外周のリングの外側まで）に対する割合（基準を 1 つにそろえる。2026-10-14）。
/// 画面の幅 393pt なら外径は 290.8pt で、リング 17.4pt・中央のプレート 98.9pt・時針 77.1pt・分針 106.1pt
enum HomeMetrics {
    /// 時計の外径（外周のリングの外側まで）を、画面の幅の何割にするか
    static let clockWidthRatio: CGFloat = 0.74
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
    /// 中央の「出発まで」と「23分」
    static let centerCaptionFont = Font.system(size: 13, weight: .medium)
    static let centerNumberFont = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()
    static let centerUnitFont = Font.system(size: 18, weight: .semibold, design: .rounded)
    /// 時計の下の「16:52 → 17:15 出発予定」
    static let flowFont = Font.system(size: 15, weight: .medium).monospacedDigit()
    /// 1 分たつごとに、弧と針を動かす時間（秒）
    static let minuteAnimation: Double = 0.45
}
