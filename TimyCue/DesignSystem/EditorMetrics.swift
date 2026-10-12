import SwiftUI

/// 3 分割の予定編集画面の寸法。3 分割の比率・ホイールの形などは実機で確かめて決める（仕様 §86）ので、
/// 値はすべてここに集め、決まったらここだけ差し替える。今の値はすべて仮。
enum EditorMetrics {
    // MARK: 3 分割の比率（仕様 §32・§67）

    /// 上の 2 つ（時間画面・予定入力）が画面の高さに占める割合
    static let topPaneRatio: CGFloat = 0.58
    /// 左上の時間画面の幅の割合
    static let timePaneWidthRatio: CGFloat = 0.42
    /// キーボードが出ている間：右の入力を広げ、下のカレンダーを縮める。左の時間軸は残す（§67）
    static let keyboardTopPaneRatio: CGFloat = 0.8
    static let keyboardTimePaneWidthRatio: CGFloat = 0.32
    static let paneSpacing: CGFloat = 1

    // MARK: ヘッダー

    static let headerHeight: CGFloat = 46
    static let headerTitleFont = Font.system(size: 15, weight: .semibold)
    static let saveButtonFont = Font.system(size: 15, weight: .semibold)

    // MARK: 時間画面（§35・§37〜§39）

    static let dateTabHeight: CGFloat = 32
    static let dateTabFont = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let hourRowHeight: CGFloat = 44
    static let hourLabelWidth: CGFloat = 34
    static let hourLabelFont = Font.system(size: 10, weight: .medium).monospacedDigit()
    static let blockFont = Font.system(size: 11, weight: .semibold)
    /// 終了時刻のない予定は短い固定の高さ（§37）
    static let noEndBlockHeight: CGFloat = 20
    static let draftOpacity: Double = 0.55
    /// 仮予定を動かしている間に出す時刻（§40）
    static let dragTimeFont = Font.system(size: 11, weight: .bold).monospacedDigit()
    /// 仮予定の下端の、終了時刻のハンドル（§41）
    static let endHandleWidth: CGFloat = 28
    static let endHandleHeight: CGFloat = 16
    /// 分ホイール（§38。形は実機で確かめて決める）
    static let wheelFont = Font.system(size: 14, weight: .medium).monospacedDigit()
    static let wheelSelectedFont = Font.system(size: 16, weight: .bold).monospacedDigit()
    static let wheelRowHeight: CGFloat = 24
    static let wheelWidth: CGFloat = 36

    // MARK: 予定入力（§44・§45）

    static let inputRowHeight: CGFloat = 40
    static let inputLabelWidth: CGFloat = 68
    static let inputLabelFont = Font.system(size: 13)
    static let inputValueFont = Font.system(size: 14, weight: .medium)
    static let chipFont = Font.system(size: 13, weight: .medium)
    static let issueFont = Font.system(size: 13, weight: .semibold)
    /// 予定の重なりの警告（§58）
    static let warningFont = Font.system(size: 10, weight: .semibold)

    // MARK: 下カレンダーと年月バー（v1.1）

    /// 日付の行の最低の高さ。枠にちょうど収まる行数を、ここから決める
    static let calendarMinRowHeight: CGFloat = 40
    static let calendarDayFont = Font.system(size: 14, weight: .medium).monospacedDigit()
    static let calendarWeekdayHeight: CGFloat = 20
    static let calendarWeekdayFont = Font.system(size: 11, weight: .medium)
    static let selectedCircleSize: CGFloat = 26
    /// 予定がある日の予定色のドット（Q23）
    static let eventDotSize: CGFloat = 4
    static let eventDotSpacing: CGFloat = 2
    static let eventMoreFont = Font.system(size: 7, weight: .semibold)
    /// なぞって選んでいるとみなす、指の動きの大きさ
    static let dragSelectThreshold: CGFloat = 8

    static let yearMonthBarWidth: CGFloat = 64
    /// バーの上での 1 週の高さ（カレンダーの行より小さくして、前後の月まで見えるようにする）
    static let barWeekHeight: CGFloat = 7
    static let barYearFont = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let barMonthFont = Font.system(size: 12, weight: .regular).monospacedDigit()
    /// 固定帯の近くに来た月は少し太く・濃く（v1.1「表示範囲帯」）
    static let barMonthFocusedFont = Font.system(size: 13, weight: .bold).monospacedDigit()
    static let barBandCornerRadius: CGFloat = 6
}
