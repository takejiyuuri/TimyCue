import SwiftUI

/// 月カレンダーの寸法と文字の大きさ。月セルの高さ・予定の文字サイズなどは実機で確かめて決める（仕様 §86）ので、
/// 値はすべてここに集め、決まったらここだけ差し替える。今の値はすべて仮。
enum CalendarMetrics {
    /// 月セルの高さ
    static let cellHeight: CGFloat = 80
    static let dayNumberFont = Font.system(size: 13, weight: .medium)
    /// 今日の日付の後ろの丸（仕様 §20）
    static let todayCircleSize: CGFloat = 22
    /// 1〜4 件のときの予定名（仕様 §21：小さく、ただし読めるサイズ）
    static let eventTitleFont = Font.system(size: 10)
    static let eventTitleDotSize: CGFloat = 5
    static let eventLineSpacing: CGFloat = 1
    /// 5 件以上のときの色点（仕様 §21）
    static let summaryDotSize: CGFloat = 7
    static let summaryDotSpacing: CGFloat = 3
    static let moreFont = Font.system(size: 8, weight: .semibold)
    /// 選択中の日の枠（仕様 §20）
    static let selectionLineWidth: CGFloat = 1.5

    static let weekdayHeaderFont = Font.system(size: 12, weight: .medium)
    static let weekdayHeaderHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 4

    /// 画面上部の年（Q20。2026-10-12 から真ん中に置く）
    static let yearFont = Font.system(size: 17, weight: .semibold)
    static let yearHeaderHeight: CGFloat = 30
    /// その月の 1 日のセルに出す「10/」（2026-10-12 ユーザー決定。日付の数字より大きめ）
    static let monthStartFont = Font.system(size: 16, weight: .bold)

    /// 日付吹き出し（仕様 §22。2026-10-12 デザインの指摘で少し大きく）
    static let popoverMaxWidth: CGFloat = 300
    static let popoverWidthRatio: CGFloat = 0.72
    /// これより多いと吹き出しの中を縦スクロールにする
    static let popoverMaxVisibleRows = 5
    static let popoverListHeight: CGFloat = 190
    static let popoverRowSpacing: CGFloat = 8
    static let popoverGap: CGFloat = 4
    static let popoverMargin: CGFloat = 8
    static let popoverTitleFont = Font.system(size: 16, weight: .semibold)
    static let popoverPrimaryFont = Font.system(size: 15, weight: .medium)
    static let popoverSecondaryFont = Font.system(size: 13)
    static let popoverTimeFont = Font.system(size: 13, weight: .medium).monospacedDigit()
    /// 時刻の欄の幅（「10:00–11:30」が入る幅。Q12）
    static let popoverTimeWidth: CGFloat = 86
}
