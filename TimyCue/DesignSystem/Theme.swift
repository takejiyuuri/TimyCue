import SwiftUI

/// 色・角丸・余白の仮の値（仕様 §4）。正確な HEX・フォントサイズ・比率は実機で確かめて決める（仕様 §86）ので、
/// 値はすべてここに集め、決まったらここだけ差し替える。
enum Theme {
    /// ブランドのパレット（追加仕様書 §46.4。ブランドボードの「正式採用」）。アプリの画面では、背景・主アクセント・選択状態・
    /// ロゴ周辺を中心に使う。本文の文字色と、緑・黄・赤などの状態色には使わない（2026-10-14 ユーザー決定）
    enum BrandPalette {
        /// 背景のアイボリー
        static let ivory: UInt32 = 0xFFFBF3
        /// 淡いオレンジ（グラデーションの始まり）
        static let lightOrange: UInt32 = 0xFFD19C
        /// オレンジ（グラデーションの終わり）
        static let orange: UInt32 = 0xFB8D3C
        /// ロゴの文字のブラウン（UI の本文には使わない）
        static let brown: UInt32 = 0x8B5E3C
    }

    enum Colors {
        /// 背景：ブランドのアイボリー（2026-10-14。前は #FAF5EC）
        static let background = Color(hex: BrandPalette.ivory)
        /// ホームの画面の背景。時計の実機確認が終わるまでは前の背景のまま。確認後に、時計の色とまとめてブランドのパレットへそろえる（2026-10-14 ユーザー決定）
        static let homeBackground = Color(hex: 0xFAF5EC)
        /// 背景より一段明るい面（仮）。時計の文字盤にも使うので、時計の実機確認が終わるまで変えない
        static let surface = Color(hex: 0xFFFDF8)
        /// 主アクセント：ブランドのオレンジ。選択状態・主なボタン・タブに使う（2026-10-14。前は淡いオレンジ #F4A96A。仮）
        static let accent = Color(hex: BrandPalette.orange)
        /// 本文の文字は濃いグレーのまま（ブランドのブラウンにはしない。2026-10-14 ユーザー決定）
        static let textPrimary = Color(hex: 0x3D3730)
        static let textSecondary = Color(hex: 0x8A8178)
        /// 区切り線（仮）。時計の中央のプレートの縁にも使うので、時計の実機確認が終わるまで変えない
        static let separator = Color(hex: 0xE9E1D4)
        /// 今日の日付の後ろの淡いオレンジの丸（仕様 §20。アクセントを 35％ に薄めた色。仮）
        static let todayCircle = Color(hex: BrandPalette.orange, opacity: 0.35)
        /// 3 分割画面の下カレンダーの今日の丸は淡いグレー（2026-10-14 実機の指摘。#E4E4E4 ではグレーに見えなかったので濃くした。色は仮）
        static let editorTodayCircle = Color(hex: 0xC7C7CC)
        /// ホームの時計（追加仕様書 §44。原色ではなく淡い色。色は仮。TestFlight の実機確認が終わるまで変えない：§46.4）：60 分を表す淡い背景のリングと、
        /// 残り時間の弧（60〜31 分は淡い緑、30〜16 分は淡いクリーム、15〜0 分は淡いコーラル。spec §6）
        static let clockTrack = Color(hex: 0xEFE8DC)
        static let clockPlenty = Color(hex: 0xB5D8A4)
        static let clockHalf = Color(hex: 0xF4DE96)
        static let clockLast = Color(hex: 0xF2A797)
        /// 時計の中央の円形プレート。文字盤と同じ系統の、少しだけ濃いアイボリー（2026-10-14 決定の形。色は仮）
        static let clockPlate = Color(hex: 0xF7F1E6)
        /// 「個別」の日付の丸いボタンで、時刻を決めた日の枠（2026-10-14 ユーザー決定「時間設定してあれば枠の色を変える」。色は仮）
        static let dayButtonTimeSet = Color(hex: 0x34C759)
        /// 3 分割画面の右の入力で、開いている行の背景。緑で、濃さは前のオレンジと同じ 0.10（2026-10-14 実機の指摘。色は仮）
        static let expandedRow = Color(hex: 0x34C759, opacity: 0.10)
        /// 警告の黄色・赤は予定色とは別の意味（仕様 §4）
        static let warning = Color(hex: 0xE8B931)
        static let danger = Color(hex: 0xE0645A)
        /// 土曜の曜日と日付は淡い青、日曜は淡い赤（2026-10-12 デザインの指摘。警告の赤と見間違えない淡さ。仮）
        static let saturday = Color(hex: 0x6F9CCB)
        static let sunday = Color(hex: 0xD48A82)
        /// 月カレンダーで、見ている月（画面の真ん中の月）以外の日を見た目だけ薄くする度合い（2026-10-12 ユーザー決定。仮）
        static let outsideMonthOpacity: Double = 0.38
        /// 月カレンダーの 1 日のセルの「10/」：どの月も真っ黒（2026-10-13 実機の指摘）
        static let monthStartText = Color(hex: 0x000000)
        /// 3 分割画面の左右のスクロールバー。カレンダーと見分けやすい色（2026-10-13 ユーザー決定。アクセントを薄めた色。色は仮）
        static let scrollBarTrack = Color(hex: BrandPalette.orange, opacity: 0.22)
        static let scrollBarTrackActive = Color(hex: BrandPalette.orange, opacity: 0.38)
        static let scrollBarMark = Color(hex: 0xC2753A)

        /// 曜日（月曜を 0）ごとの文字の色。土曜・日曜だけ色を付け、ほかは normal
        static func weekdayText(_ indexFromMonday: Int, normal: Color) -> Color {
            switch indexFromMonday {
            case 5: saturday
            case 6: sunday
            default: normal
            }
        }
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

/// 予定色の実際の色（仮の HEX）
enum EventPalette {
    static func color(for key: EventColor) -> Color {
        switch key {
        case .orange: Color(hex: 0xF7B983)
        case .mint: Color(hex: 0x9FD8C3)
        case .lavender: Color(hex: 0xC3B5E3)
        case .saxeBlue: Color(hex: 0x9CC3E0)
        case .yellow: Color(hex: 0xF3DC8A)
        case .green: Color(hex: 0xA9CF94)
        }
    }
}

extension Color {
    /// 0xRRGGBB から色を作る
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
