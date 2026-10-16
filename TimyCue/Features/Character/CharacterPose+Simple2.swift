import CoreGraphics

// 正式のデザイン「2 シンプル」（2026-10-16。spec §88.4）。ChatGPT の比較画像の 2 番目の原画
// （docs/design-reference/characters/simple-2-*.png）を測って、部品の形にしたもの。
// 単位は原画の画素（立った姿の切り出しの、絵のいちばん上を 0）。輪郭の線の内側を部品の形にする（原画の線の太さは約 7 画素）。
// 座った姿は、頭の大きさを立った姿にそろえて同じ縮尺にしている（原画の座った姿は頭が約 1 割小さく描かれている）
extension CharacterPose {
    /// 立った姿：大きな丸い頭と胴はひと続き（あごの線なし）。腕は胴の輪郭から小さくふくらみ、内側に短い線。短い脚と、脚のあいだの小さな切れ込み
    static let simple2Standing = CharacterPose(
        head: Part(center: CGPoint(x: 120, y: 99.5), size: CGSize(width: 200, height: 185)),
        body: Part(center: CGPoint(x: 116.5, y: 204.5), size: CGSize(width: 93, height: 79)),
        bodyCornerRatio: 0.35,
        legs: [
            Limb(joint: CGPoint(x: 94.5, y: 234.5), length: 26, width: 21, angle: 0, mergesWithBody: true),
            Limb(joint: CGPoint(x: 139, y: 234.5), length: 26, width: 22, angle: 0, mergesWithBody: true),
        ],
        arms: [
            Limb(joint: CGPoint(x: 63, y: 176), length: 40, width: 20, angle: 10, mergesWithBody: true),
            Limb(joint: CGPoint(x: 167.5, y: 176), length: 40, width: 20, angle: -10, mergesWithBody: true),
        ],
        eyes: [
            Part(center: CGPoint(x: 78.5, y: 117), size: CGSize(width: 13.5, height: 14)),
            Part(center: CGPoint(x: 147, y: 117), size: CGSize(width: 13.5, height: 14)),
        ],
        cheeks: [],
        headMergesWithBody: true,
        details: [
            // 腕の内側の短い線（原画の、腕と胴の境目）
            Curve(start: CGPoint(x: 69.5, y: 199), control: CGPoint(x: 69, y: 209), end: CGPoint(x: 63, y: 214)),
            Curve(start: CGPoint(x: 161, y: 199), control: CGPoint(x: 161.5, y: 209), end: CGPoint(x: 167, y: 214)),
        ])

    /// 座った姿：正面を向く。頭と胴はひと続きで、その手前に前へ出した脚（上が平らで、下に膝が 2 つ丸く出る）と、
    /// 右の膝の上の手を、それぞれの輪郭で重ねる。脚のあいだに短い境目の線
    static let simple2Sitting = CharacterPose(
        head: Part(center: CGPoint(x: 120, y: 102.2), size: CGSize(width: 200, height: 190.1)),
        body: Part(center: CGPoint(x: 131, y: 192.3), size: CGSize(width: 109.9, height: 44)),
        bodyCornerRatio: 0.4,
        legs: [],
        arms: [],
        eyes: [
            Part(center: CGPoint(x: 71.6, y: 128.6), size: CGSize(width: 13.2, height: 14.3)),
            Part(center: CGPoint(x: 136.5, y: 128.6), size: CGSize(width: 13.2, height: 14.3)),
        ],
        cheeks: [],
        headMergesWithBody: true,
        frontGroups: [
            [
                .roundedRect(Part(center: CGPoint(x: 128.2, y: 206.6), size: CGSize(width: 102.2, height: 37.4)), cornerRatio: 0.16),
                .ellipse(Part(center: CGPoint(x: 102.4, y: 220.9), size: CGSize(width: 50.6, height: 26.4))),
                .ellipse(Part(center: CGPoint(x: 150.8, y: 223.1), size: CGSize(width: 52.8, height: 26.4))),
            ],
            [
                .ellipse(Part(center: CGPoint(x: 179.3, y: 215.4), size: CGSize(width: 26.4, height: 33))),
            ],
        ],
        details: [
            Curve(start: CGPoint(x: 127.7, y: 202.2), control: CGPoint(x: 123.3, y: 219.8), end: CGPoint(x: 124.9, y: 235.2)),
        ])
}
