import SwiftUI

/// 人型キャラクター（spec §88.4）の色と線の太さ。実機で確かめて決めるので、値はここに集める（2026-10-15 H1。どれも仮の値）。
/// 体・輪郭・目と装備の色は CharacterPalette（下）、形（部品の位置・大きさ）は CharacterPose と CharacterEquipment が持つ
enum CharacterMetrics {
    /// ほっぺ：ブランドの淡いオレンジ。濃さは案ごとに CharacterStyle.cheekOpacity で決める（現行案は 85％）
    static let cheek = Color(hex: Theme.BrandPalette.lightOrange)
    /// 輪郭の太さ：立った姿の全身の高さに対する割合（現行案）。小さくても見えるよう 1pt より細くせず、大きくても 2pt まで
    static let outlineRatio: CGFloat = 0.045
    static let outlineMin: CGFloat = 1
    static let outlineMax: CGFloat = 2

    /// 装備の模様の線（甲羅の板の境目）の太さ：輪郭の線の見える太さに対する割合（正式原画から測った。2026-10-16）
    static let patternWidthRatio: CGFloat = 0.55

    static func outlineWidth(forHeight height: CGFloat, ratio: CGFloat = outlineRatio) -> CGFloat {
        min(max(height * ratio, outlineMin), outlineMax)
    }
}

/// 人型キャラクターの色（16 進の RGB）。案ごとに CharacterStyle.palette で選ぶ。旧試作と 2 シンプルはアプリで決めた色（app。
/// 体は温かみのあるオフホワイト、輪郭は見やすいダークブラウン、目は輪郭より少し濃いブラウン）、正式（3 モード）は原画から測った色（2026-10-16）
struct CharacterPalette: Equatable {
    var outline: UInt32
    var bodyFill: UInt32
    var eye: UInt32
    /// 装備の色（亀の甲羅の板と境目の線、うさぎの耳の内側、フードの顔まわりの縁取りと耳の付け根の帯）
    var shellPlate: UInt32 = 0xC3C691
    var shellLine: UInt32 = 0xA8AD73
    var earInner: UInt32 = 0xFAB7AB
    var hoodRing: UInt32 = 0xB98A70
    var hoodBand: UInt32 = 0xD2644A

    /// アプリで決めた色（2026-10-15 H1。旧試作と 2 シンプル）
    static let app = CharacterPalette(outline: 0x4A3326, bodyFill: 0xFFFCF5, eye: 0x3A281D)
    /// 正式原画（3 モード）から測った色
    static let official3 = CharacterPalette(outline: 0x3E2312, bodyFill: 0xFEFAF1, eye: 0x29130A)
}
