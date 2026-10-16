import CoreGraphics

// 正式のデザイン「キャラクター 3 モード（うさぎは被り物バージョン）」（2026-10-16。spec §88.4）の本体。
// 原画（docs/design-reference/characters/official-3modes/）の人型モードの「立つ」（主なポーズの段）を 2 倍にした画素を単位にし、
// アプリと同じ描き方で描いた線を原画に重ねて、ずれが小さくなるように部品の値を当てはめた。輪郭の線の内側を部品の形にする（原画の線の太さは約 5 画素）。
// 亀・人型・うさぎで本体は同じ。甲羅とうさぎの耳のフードは装備として別に持つ（CharacterEquipment）
extension CharacterPose {
    /// 立った姿（人型モードの「立つ」）：大きな丸い頭と胴はひと続き（あごの線なし）。腕は胴の輪郭から小さくふくらみ、内側に短い線。
    /// 胴は下へ少しすぼまり、短い脚のあいだに切れ込み。左右の腕・脚は原画どおり少し形が違う
    static let official3Standing = CharacterPose(
        head: Part(center: CGPoint(x: 91, y: 76.9), size: CGSize(width: 127.2, height: 121.6)),
        body: Part(center: CGPoint(x: 95.4, y: 147.8), size: CGSize(width: 83.5, height: 49.4)),
        bodyCornerRatio: 0.35,
        legs: [
            Limb(joint: CGPoint(x: 66.7, y: 160.4), length: 23.6, width: 24.6, angle: -14.2, mergesWithBody: true, cornerRadius: 10.1),
            Limb(joint: CGPoint(x: 113, y: 160), length: 25.2, width: 20.8, angle: 15.4, mergesWithBody: true, cornerRadius: 10),
        ],
        arms: [
            Limb(joint: CGPoint(x: 53.4, y: 131), length: 31.9, width: 19.9, angle: 2.9, mergesWithBody: true),
            Limb(joint: CGPoint(x: 120.3, y: 131.5), length: 23.1, width: 13.6, angle: -11.5, mergesWithBody: true),
        ],
        eyes: [
            Part(center: CGPoint(x: 70.3, y: 88.5), size: CGSize(width: 8.2, height: 9.5)),
            Part(center: CGPoint(x: 113.7, y: 88.5), size: CGSize(width: 8.2, height: 9.5)),
        ],
        cheeks: [],
        headMergesWithBody: true,
        details: [
            // 腕の内側の短い線（上は丸く止まり、下は腕の先の輪郭につながる）
            Curve(start: CGPoint(x: 48.5, y: 153), control: CGPoint(x: 47.2, y: 156.6), end: CGPoint(x: 47, y: 160.5)),
            Curve(start: CGPoint(x: 133, y: 152.5), control: CGPoint(x: 134.1, y: 155.9), end: CGPoint(x: 134, y: 159.5)),
        ])
}
