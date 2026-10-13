import SwiftUI

/// ホームの時計（spec §6・追加仕様書 §44）の寸法と文字の大きさ。実機で確かめて決めるので、値はここに集める。
/// 時計の外径（画面の幅の 72〜76％）と、1 分ごとの動き（0.3〜0.6 秒）は 2026-10-14 の指示の範囲。ほかの値はすべて仮
enum HomeMetrics {
    /// 時計の外径（外周のリングの外側まで）を、画面の幅の何割にするか
    static let clockWidthRatio: CGFloat = 0.74
    /// 外周のリングの太さ（時計の外径に対する割合）と、リングと文字盤のすき間
    static let ringWidthRatio: CGFloat = 0.07
    static let ringFaceGap: CGFloat = 4
    /// 15 分ごとの目盛り（リングを横切る線）の太さと、リングからはみ出す長さ
    static let quarterTickWidth: CGFloat = 2
    static let quarterTickOverhang: CGFloat = 3
    /// 文字盤の時の目盛りと、文字盤のふちからの距離
    static let hourTickLength: CGFloat = 7
    static let hourTickWidth: CGFloat = 2
    static let hourTickInset: CGFloat = 5
    /// 針の長さ（文字盤の半径に対する割合）と太さ、真ん中の軸
    static let hourHandLengthRatio: CGFloat = 0.5
    static let minuteHandLengthRatio: CGFloat = 0.8
    static let hourHandWidth: CGFloat = 6
    static let minuteHandWidth: CGFloat = 3.5
    static let hubSize: CGFloat = 9
    /// 「いま」「出発」の丸の大きさ（リングの太さに対する割合）。「出発」の方を少し大きく濃くする
    static let nowDotRatio: CGFloat = 0.5
    static let targetDotRatio: CGFloat = 0.72
    static let nowLabelFont = Font.system(size: 11, weight: .medium)
    static let targetLabelFont = Font.system(size: 12, weight: .bold)
    /// 「いま」「出発」の文字を、リングの外側からどれだけ離して出すか
    static let markerLabelGap: CGFloat = 13
    /// 時計の上下にあける余白（リングの外に出す「いま」「出発」の文字の分）
    static let clockLabelRoom: CGFloat = 20
    /// 中央の「出発まで」と「23分」
    static let centerCaptionFont = Font.system(size: 13, weight: .medium)
    static let centerNumberFont = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()
    static let centerUnitFont = Font.system(size: 18, weight: .semibold, design: .rounded)
    /// 中央の文字を少し上へずらす量（文字盤の半径に対する割合。針と重なりすぎないように）
    static let centerTextLiftRatio: CGFloat = 0.06
    /// 時計の下の「16:52 → 17:15 出発予定」
    static let flowFont = Font.system(size: 15, weight: .medium).monospacedDigit()
    /// 1 分たつごとに、弧と針を動かす時間（秒）
    static let minuteAnimation: Double = 0.45
}
