import SwiftUI

/// 色・角丸・余白の仮の値（仕様 §4）。正確な HEX・フォントサイズ・比率は実機で確かめて決める（仕様 §86）ので、
/// 値はすべてここに集め、決まったらここだけ差し替える。
enum Theme {
    enum Colors {
        /// 暖かいベージュ／アイボリーの背景（仮）
        static let background = Color(hex: 0xFAF5EC)
        /// 背景より一段明るい面（仮）
        static let surface = Color(hex: 0xFFFDF8)
        /// 基調アクセントの淡いオレンジ（仮）
        static let accent = Color(hex: 0xF4A96A)
        static let textPrimary = Color(hex: 0x3D3730)
        static let textSecondary = Color(hex: 0x8A8178)
        static let separator = Color(hex: 0xE9E1D4)
        /// 今日の日付の後ろの淡いオレンジの丸（仕様 §20。仮）
        static let todayCircle = Color(hex: 0xF4A96A, opacity: 0.35)
        /// 警告の黄色・赤は予定色とは別の意味（仕様 §4）
        static let warning = Color(hex: 0xE8B931)
        static let danger = Color(hex: 0xE0645A)
        /// 土曜の曜日と日付は淡い青、日曜は淡い赤（2026-10-12 デザインの指摘。警告の赤と見間違えない淡さ。仮）
        static let saturday = Color(hex: 0x6F9CCB)
        static let sunday = Color(hex: 0xD48A82)
        /// 月カレンダーで、見ている月（画面の真ん中の月）以外の日を見た目だけ薄くする度合い（2026-10-12 ユーザー決定。仮）
        static let outsideMonthOpacity: Double = 0.38

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
