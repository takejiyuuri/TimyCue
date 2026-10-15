import SwiftUI

/// 人型キャラクター（spec §88.4）の色と線の太さ。実機で確かめて決めるので、値はここに集める（2026-10-15 H1。どれも仮の値）。
/// 形（部品の位置・大きさ）は CharacterPose が 100 の単位で持つ
enum CharacterMetrics {
    /// 体：温かみのあるオフホワイト。Home の背景（アイボリー）とは輪郭で見分ける
    static let bodyFill = Color(hex: 0xFFFCF5)
    /// 輪郭：見やすいダークブラウン
    static let outline = Color(hex: 0x4A3326)
    /// 目：小さな点。輪郭より少しだけ濃いブラウン
    static let eye = Color(hex: 0x3A281D)
    /// ほっぺ：ブランドの淡いオレンジ。濃さは案ごとに CharacterStyle.cheekOpacity で決める（現行案は 85％）
    static let cheek = Color(hex: Theme.BrandPalette.lightOrange)
    /// 輪郭の太さ：立った姿の全身の高さに対する割合（現行案）。小さくても見えるよう 1pt より細くせず、大きくても 2pt まで
    static let outlineRatio: CGFloat = 0.045
    static let outlineMin: CGFloat = 1
    static let outlineMax: CGFloat = 2

    static func outlineWidth(forHeight height: CGFloat, ratio: CGFloat = outlineRatio) -> CGFloat {
        min(max(height * ratio, outlineMin), outlineMax)
    }
}
