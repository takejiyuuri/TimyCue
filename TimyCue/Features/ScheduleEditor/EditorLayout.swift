import CoreGraphics

/// 3 分割画面の比率と寸法。細かな比率・目盛りの間隔は未決（仕様 §53）なので、すべてここに集めて仮の値にしておく。
enum EditorLayout {
    /// 画面の高さのうち、上の 2 領域（時間画面・入力画面）が使う割合
    static let topHeightFraction: CGFloat = 0.56
    /// キーボード表示中は入力画面を優先して上を広げ、下のカレンダーを縮める（仕様 §28）
    static let topHeightFractionWithKeyboard: CGFloat = 0.82
    /// 上の段のうち、左の時間画面が使う幅の割合
    static let timePaneWidthFraction: CGFloat = 0.42
    /// キーボード表示中は右の入力画面を広げる。左の時間軸は残す（仕様 §28）
    static let timePaneWidthFractionWithKeyboard: CGFloat = 0.34
    /// 時間軸の 1 時間の高さ
    static let hourHeight: CGFloat = 44
    /// 終了時刻のない予定ブロックの高さ（仕様 §20：短い固定サイズ）
    static let untimedBlockHeight: CGFloat = 22
    /// 時刻の文字の幅
    static let hourLabelWidth: CGFloat = 26
    /// 領域どうしの間隔
    static let paneSpacing: CGFloat = 6
}
