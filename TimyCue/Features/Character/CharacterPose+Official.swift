import CoreGraphics

// 正式キャラクター「キャラクター 3 モード（うさぎは被り物バージョン）」（2026-10-16 正式採用。spec §88.4）の立ち姿。
// 原画（docs/design-reference/characters/official-3modes/timycue-character-3modes.webp）の「主なポーズ・動作例」の
// 人型「立つ」を切り出し、内側の白い形（輪郭の線の内側）に、アプリと同じ部品（頭・胴・腕・脚）を当てはめた値
// （作り方は tools/character_3modes/。重なりの割合は約 97％）。単位は、その切り出しの画素（原画の画素）。
// 亀・人型・うさぎは同じ本体で、甲羅・うさぎの耳の被り物は CharacterGearSet.official（本体とは別の部品）。
// 旧「2 シンプル」の値は使っていない（新しい原画から測り直した）
extension CharacterPose {
    /// 立った姿：大きな丸い頭と胴はひと続き（あごの線なし）。腕は胴の両わきから短くふくらみ、内側に短い線。
    /// 胴は足の付け根の高さまで下り、その下に短い脚 2 本（足の裏は平ら。2 本のあいだに浅い四角い切れ込み）
    static let officialStanding = CharacterPose(
        head: Part(center: CGPoint(x: 45.25, y: 40.03), size: CGSize(width: 63.74, height: 59.55)),
        body: Part(center: CGPoint(x: 45.25, y: 71.36), size: CGSize(width: 34.94, height: 34.5)),
        bodyCornerRatio: 0.1,
        legs: [
            Limb(joint: CGPoint(x: 35.22, y: 81.61), length: 11.81, width: 7.8, angle: 0, mergesWithBody: true, cornerRadius: 2),
            Limb(joint: CGPoint(x: 55.28, y: 81.61), length: 11.81, width: 7.8, angle: 0, mergesWithBody: true, cornerRadius: 2),
        ],
        arms: [
            Limb(joint: CGPoint(x: 32.14, y: 63.41), length: 19.65, width: 7.65, angle: 27.95, mergesWithBody: true),
            Limb(joint: CGPoint(x: 58.36, y: 63.41), length: 19.65, width: 7.65, angle: -27.95, mergesWithBody: true),
        ],
        eyes: [
            Part(center: CGPoint(x: 35.0, y: 46.1), size: CGSize(width: 4.9, height: 5.1)),
            Part(center: CGPoint(x: 56.8, y: 46.1), size: CGSize(width: 4.9, height: 5.1)),
        ],
        cheeks: [],
        headMergesWithBody: true,
        details: [
            // 腕の内側の短い線（わきの下から、腕の先の輪郭の近くまで）
            Curve(start: CGPoint(x: 26.8, y: 78.0), control: CGPoint(x: 26.1, y: 81.0), end: CGPoint(x: 25.0, y: 84.0)),
            Curve(start: CGPoint(x: 63.2, y: 78.0), control: CGPoint(x: 63.9, y: 81.0), end: CGPoint(x: 65.0, y: 84.0)),
        ])
}

extension CharacterGearSet {
    /// 正式キャラクター 3 モードの装備。原画の亀「立つ」・うさぎ（3 モードの見出しの絵と「立つ」）を測り、本体の頭に合わせて置いた値。
    /// 甲羅の側は、主な絵・モード切り替えの絵・Home の絵に合わせて見る人から見て左（「立つ」は右に描かれている。2026-10-17。spec §88.4）。
    /// 大きさは「甲羅大きめ＋模様強調」（2026-10-17 正式決定。docs/design-reference/characters/official-3modes/shell-comparison-2026-10-17.webp）：
    /// 「立つ」を測った形（23.5×38・傾き 10°）の縦横比と傾きを保って約 1.18 倍にし、比較画像の「現状」→「大きめ＋模様強調」と
    /// 同じだけ、左へ（約 6 単位）・上へ（約 4 単位）・下へ（約 2.6 単位）広げた。本体の後ろにつながったまま
    static let official = CharacterGearSet(
        // 甲羅：背中に背負い、見る人から見て左の脇からはみ出す。上が少し外（左）へ傾いた楕円（右の部分は本体に隠れる）
        shell: ShellGear(
            shape: CharacterPose.Part(center: CGPoint(x: 13.0, y: 66.8), size: CGSize(width: 27.6, height: 44.7), rotation: -10),
            pattern: [
                // 真ん中の甲板（六角形）
                [CGPoint(x: -0.18, y: -0.30), CGPoint(x: 0.18, y: -0.30), CGPoint(x: 0.26, y: -0.08), CGPoint(x: 0.18, y: 0.16),
                 CGPoint(x: -0.18, y: 0.16), CGPoint(x: -0.26, y: -0.08), CGPoint(x: -0.18, y: -0.30)],
                // その下の甲板
                [CGPoint(x: -0.18, y: 0.16), CGPoint(x: -0.12, y: 0.36), CGPoint(x: 0.12, y: 0.36), CGPoint(x: 0.18, y: 0.16)],
                // ふちへ向かう境目
                [CGPoint(x: 0.26, y: -0.08), CGPoint(x: 0.47, y: -0.12)],
                [CGPoint(x: -0.26, y: -0.08), CGPoint(x: -0.47, y: -0.12)],
                [CGPoint(x: 0.18, y: -0.30), CGPoint(x: 0.28, y: -0.40)],
                [CGPoint(x: -0.18, y: -0.30), CGPoint(x: -0.28, y: -0.40)],
                [CGPoint(x: 0.18, y: 0.16), CGPoint(x: 0.40, y: 0.24)],
                [CGPoint(x: -0.18, y: 0.16), CGPoint(x: -0.40, y: 0.24)],
            ]),
        // うさぎの耳の被り物：頭の上に、外へ少し開いた細長い耳 2 つ（内側はピンク）。顔まわりの線は額から目の高さまで
        rabbitHood: RabbitHoodGear(
            ears: [
                CharacterPose.Part(center: CGPoint(x: 23.9, y: -1.5), size: CGSize(width: 15.8, height: 29.5), rotation: -30),
                CharacterPose.Part(center: CGPoint(x: 66.6, y: -1.5), size: CGSize(width: 15.8, height: 29.5), rotation: 30),
            ],
            earInners: [
                CharacterPose.Part(center: CGPoint(x: 25.9, y: 3.0), size: CGSize(width: 8.6, height: 22), rotation: -28),
                CharacterPose.Part(center: CGPoint(x: 64.6, y: 3.0), size: CGSize(width: 8.6, height: 22), rotation: 28),
            ],
            faceOpening: CharacterPose.Part(center: CGPoint(x: 45.25, y: 46.2), size: CGSize(width: 57.2, height: 51.8))),
        palette: .official)
}

/// 正式キャラクター 3 モードの本体・線・色（spec §88.4）。大きさ（○pt）は本体の立った姿の全身の高さ（甲羅・耳を含めない）
enum OfficialCharacter {
    static let standing = CharacterPose.officialStanding
    /// 輪郭の太さは原画と同じ割合（本体の全身の高さの約 3.85％。36pt で約 1.4pt）。ほっぺ・口・影はない
    static let style = CharacterStyle(outlineRatio: 0.0385, cheekOpacity: 0, palette: .official)
    static let gear = CharacterGearSet.official
    /// 本体の立った姿の全身の高さ（本体の単位）
    static var referenceHeight: CGFloat { standing.bounds.height }
}
