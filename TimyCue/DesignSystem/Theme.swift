import SwiftUI

/// 色・角丸・余白の仮の値（仕様 §2）。正確な HEX・フォントサイズ・比率は未決（仕様 §53）なので、
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
        /// 警告の黄色・赤は予定色とは別の意味（仕様 §2）
        static let warning = Color(hex: 0xE8B931)
        static let danger = Color(hex: 0xE0645A)
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
