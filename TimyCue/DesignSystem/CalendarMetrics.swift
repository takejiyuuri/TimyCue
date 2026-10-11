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
    static let monthTitleFont = Font.system(size: 17, weight: .semibold)
    static let monthSpacing: CGFloat = 20
    static let horizontalPadding: CGFloat = 4

    /// 日付吹き出し（仕様 §22）
    static let popoverMaxWidth: CGFloat = 280
    static let popoverWidthRatio: CGFloat = 0.66
    /// これより多いと吹き出しの中を縦スクロールにする
    static let popoverMaxVisibleRows = 5
    static let popoverListHeight: CGFloat = 190
    static let popoverRowSpacing: CGFloat = 8
    /// 吹き出しの高さのいちばん大きいところ（上下どちらに出すかの判断に使う）
    static let popoverMaxHeight: CGFloat = 250
    static let popoverGap: CGFloat = 4
    static let popoverMargin: CGFloat = 8
    static let popoverTitleFont = Font.system(size: 15, weight: .semibold)
    static let popoverPrimaryFont = Font.system(size: 14, weight: .medium)
    static let popoverSecondaryFont = Font.system(size: 12)
    static let popoverTimeFont = Font.system(size: 12, weight: .medium).monospacedDigit()
}
