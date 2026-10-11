import SwiftUI

/// 1 日タイムラインの寸法。時間軸の倍率・予定ブロックの形などは実機で確かめて決める（仕様 §86）ので、
/// 値はすべてここに集め、決まったらここだけ差し替える。今の値はすべて仮。
enum TimelineMetrics {
    /// 標準の倍率での 1 時間の高さ
    static let hourHeight: CGFloat = 60
    /// ピンチで変えられる倍率の範囲（仕様 §27）
    static let zoomRange: ClosedRange<CGFloat> = 0.6...4
    /// 0:00 の文字が上で切れないための余白
    static let topInset: CGFloat = 10
    /// ピンチの中心を合わせるための目印の間隔（分）
    static let pinchMarkerMinutes = 5
    /// 左の時刻の欄の幅
    static let hourLabelWidth: CGFloat = 44
    static let hourLabelFont = Font.system(size: 11, weight: .medium).monospacedDigit()
    /// 1 時間ごとの主線と 30 分の補助線（仕様 §26）
    static let hourLineWidth: CGFloat = 1
    static let halfHourLineWidth: CGFloat = 0.5
    static let halfHourLineOpacity: Double = 0.5
    /// 予定ブロック
    static let blockCornerRadius: CGFloat = 6
    static let blockFillOpacity: Double = 0.55
    static let blockColumnGap: CGFloat = 2
    static let blockTitleFont = Font.system(size: 12, weight: .semibold)
    static let blockTimeFont = Font.system(size: 10).monospacedDigit()
    /// 終了時刻のない予定は、倍率に関わらずこの高さ
    static let noEndBlockHeight: CGFloat = 22
    /// 現在時刻の線（仕様 §28）
    static let nowLineWidth: CGFloat = 1.5
    static let nowLabelFont = Font.system(size: 10, weight: .semibold).monospacedDigit()
    /// 終日専用帯（仕様 §30）
    static let allDayChipFont = Font.system(size: 12, weight: .medium)
    static let allDayBandMaxHeight: CGFloat = 72
}
