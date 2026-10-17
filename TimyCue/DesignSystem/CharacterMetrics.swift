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

    /// 甲羅の模様の線・フードの顔まわりの線の太さ（輪郭の太さに対する割合。フードは原画を測った値）。
    /// 甲羅の模様は「甲羅大きめ＋模様強調」（2026-10-17 正式決定）で、原画の 0.55 から太くした（36pt で約 1.2pt。仮の値）
    static let shellPatternRatio: CGFloat = 0.85
    static let hoodLineRatio: CGFloat = 0.7
}

/// キャラクターの体の色（案ごと。2026-10-16 正式キャラクター 3 モードから、案ごとに持つ）
struct CharacterPalette: Equatable {
    var fill: Color
    var outline: Color
    var eye: Color

    /// H1 の試作と「2 シンプル」（履歴）の色
    static let h1 = CharacterPalette(fill: CharacterMetrics.bodyFill, outline: CharacterMetrics.outline, eye: CharacterMetrics.eye)
    /// 正式キャラクター 3 モード（2026-10-16 正式採用の原画。原画の切り出しの画素を測った値）：
    /// 体は温かみのある白（#FEFAF2）、輪郭と目は濃いこげ茶（#36190A）
    static let official = CharacterPalette(fill: Color(hex: 0xFEFAF2), outline: Color(hex: 0x36190A), eye: Color(hex: 0x36190A))
}

/// 装備の色（正式キャラクター 3 モードの原画を測った値。spec §88.4）
struct CharacterGearPalette: Equatable {
    /// 甲羅：やわらかい黄緑と、甲板の境目の濃い緑（境目は「模様強調」で原画の #969B60 より濃くした。2026-10-17。仮の値）
    var shellFill: Color
    var shellLine: Color
    /// うさぎの耳の内側のピンク
    var earInner: Color
    /// フードの顔まわりの線（輪郭より淡いブラウン）
    var hoodLine: Color

    static let official = CharacterGearPalette(shellFill: Color(hex: 0xBABE85), shellLine: Color(hex: 0x868C4F),
                                               earInner: Color(hex: 0xF8BCB0), hoodLine: Color(hex: 0xDCAF96))
}
