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
    /// ハンドルを押さえられる所の高さと、そのうちブロックの下端より上に重ねる分（2026-10-14。指で押さえやすい大きさ。仮）
    static let endHandleHitHeight: CGFloat = 30
    static let endHandleOverlap: CGFloat = 6
    /// これより短い動きは「触れただけ」として、終了を変えない
    static let endHandleMinimumMove: CGFloat = 3
    /// 終了を伸ばしている間の時刻を、ブロックの下端からどれだけ上に出すか（指で隠れないように。2026-10-14 実機の指摘。仮）
    static let dragEndLabelLift: CGFloat = 44
    /// 重なりの警告を出す位置（ブロックの下端から下へ）
    static let warningOffsetBelowBlock: CGFloat = 20
    /// 分ホイール（§38。形は実機で確かめて決める）
    static let wheelFont = Font.system(size: 14, weight: .medium).monospacedDigit()
    static let wheelSelectedFont = Font.system(size: 16, weight: .bold).monospacedDigit()
    static let wheelRowHeight: CGFloat = 24
    static let wheelWidth: CGFloat = 36
    /// 到着目標・移動手段・色のドラムロールの高さ（2026-10-13。値は仮）
    static let wheelPickerHeight: CGFloat = 130

    // MARK: 予定入力（§44・§45）

    static let inputRowHeight: CGFloat = 40
    static let inputLabelWidth: CGFloat = 68
    static let inputLabelFont = Font.system(size: 13)
    static let inputValueFont = Font.system(size: 14, weight: .medium)
    static let chipFont = Font.system(size: 13, weight: .medium)
    static let issueFont = Font.system(size: 13, weight: .semibold)
    /// 予定の重なりの警告（§58）
    static let warningFont = Font.system(size: 10, weight: .semibold)
    /// 書き込めない Apple カレンダーの予定のロック（追加仕様書 §1.7）
    static let lockNoticeFont = Font.system(size: 12)
    static let lockIconFont = Font.system(size: 11)

    // MARK: 下カレンダーと左右のバー（2026-10-13 ユーザー決定）

    /// 見える高さは、日付の行 6 行ぶん（月の行は別に数える）
    static let calendarVisibleWeeks: CGFloat = 6
    /// 日付の行のいちばん低い高さ。キーボードが出て下カレンダーが縮んだとき（§67）は、行をつぶさず見える週を減らす。
    /// 暫定値（仕様の値ではない。実機で見て直す）
    static let calendarMinRowHeight: CGFloat = 38
    /// 月の初めに空ける、月帯の高さ（日付の行を 1 として）。日付の行の半分くらい（2026-10-13 ユーザー決定）
    static let calendarMonthRowRatio: Double = 0.5
    static let calendarMonthFont = Font.system(size: 12, weight: .semibold)
    /// いちばん上（曜日の上）に固定して出す年月（例：2026年　10月）
    static let calendarYearHeight: CGFloat = 20
    static let calendarYearFont = Font.system(size: 12, weight: .semibold).monospacedDigit()
    static let calendarDayFont = Font.system(size: 14, weight: .medium).monospacedDigit()
    static let calendarWeekdayHeight: CGFloat = 18
    static let calendarWeekdayFont = Font.system(size: 11, weight: .medium)
    static let selectedCircleSize: CGFloat = 26
    /// 予定がある日の予定色のドット（Q23）
    static let eventDotSize: CGFloat = 4
    static let eventDotSpacing: CGFloat = 2
    static let eventMoreFont = Font.system(size: 7, weight: .semibold)
    /// なぞって選んでいるとみなす、指の動きの大きさ
    static let dragSelectThreshold: CGFloat = 8

    /// 左右のスクロールバーの幅（前の年月バー 64 の半分くらい。候補）
    static let scrollBarWidth: CGFloat = 30
    static let scrollBarCornerRadius: CGFloat = 8
    /// バーだとわかるマーク（上下の矢印とつまみの線）
    static let scrollBarMarkFont = Font.system(size: 11, weight: .bold)
    static let scrollBarGripFont = Font.system(size: 14, weight: .semibold)
}
