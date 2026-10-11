import Foundation

extension EventColor {
    /// 予定色のおおよその色（0〜1 の RGB）。Apple カレンダーの色にいちばん近い予定色を選ぶのに使う。
    /// 画面に出す実際の色は DesignSystem の EventPalette（どちらも仮の値。仕様 §86）
    var referenceRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .orange: (0.97, 0.73, 0.51)
        case .mint: (0.62, 0.85, 0.76)
        case .lavender: (0.76, 0.71, 0.89)
        case .saxeBlue: (0.61, 0.76, 0.88)
        case .yellow: (0.95, 0.86, 0.54)
        case .green: (0.66, 0.81, 0.58)
        }
    }

    /// その色にいちばん近い予定色。Apple カレンダー由来の予定は、元のカレンダーの色を初期候補にする（仕様 §53）。
    /// 予定色はパステルなので、色の濃さではなく色合いで比べる
    static func nearest(red: Double, green: Double, blue: Double) -> EventColor {
        let target = hue(red, green, blue)
        return allCases.min { lhs, rhs in
            distance(hue(lhs.referenceRGB.red, lhs.referenceRGB.green, lhs.referenceRGB.blue), target)
                < distance(hue(rhs.referenceRGB.red, rhs.referenceRGB.green, rhs.referenceRGB.blue), target)
        } ?? .orange
    }

    /// 色合い（0〜1）
    private static func hue(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        guard delta > 0.0001 else { return 0 }
        var hue: Double
        if maxValue == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue /= 6
        return hue < 0 ? hue + 1 : hue
    }

    /// 色合いの差（色相環なので 0 と 1 はつながっている）
    private static func distance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b)
        return min(diff, 1 - diff)
    }
}
