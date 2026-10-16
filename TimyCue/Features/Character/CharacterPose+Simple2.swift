import CoreGraphics

// 正式のデザイン「2 シンプル」（2026-10-16。spec §88.4）。ChatGPT の比較画像の 2 番目の原画
// （docs/design-reference/characters/simple-2-*.png）に、アプリと同じ描き方で描いた線を重ね、ずれが小さくなるように部品の値を当てはめたもの。
// 単位は原画の切り出し（simple-2-standing.png、239×293）の画素。輪郭の線の内側を部品の形にする（原画の線の太さは約 7 画素）。
// 座った姿は simple-2-sitting.png の画素を 1/0.91 倍して、頭を立った姿の頭と同じ大きさ・形にそろえている
// （原画の座った姿は頭が約 1 割小さく描かれている。同じ縮尺）
extension CharacterPose {
    /// 立った姿：大きな丸い頭と胴はひと続き（あごの線なし）。腕は胴の輪郭から小さくふくらみ、内側に短い線。
    /// 胴は下へ少しすぼまり、足の裏は平ら。2 本の脚のあいだに小さな切れ込み
    static let simple2Standing = CharacterPose(
        head: Part(center: CGPoint(x: 120.5, y: 106.5), size: CGSize(width: 200.2, height: 173.8)),
        body: Part(center: CGPoint(x: 116.5, y: 214), size: CGSize(width: 101.5, height: 86.5)),
        bodyCornerRatio: 0.32,
        legs: [
            Limb(joint: CGPoint(x: 90.2, y: 237), length: 36, width: 36, angle: -8.2, mergesWithBody: true, cornerRadius: 14.2),
            Limb(joint: CGPoint(x: 145.8, y: 236.5), length: 37, width: 34.5, angle: 12, mergesWithBody: true, cornerRadius: 12.4),
        ],
        arms: [
            Limb(joint: CGPoint(x: 68.5, y: 194.5), length: 35.8, width: 22, angle: 11.1, mergesWithBody: true),
            Limb(joint: CGPoint(x: 166, y: 196), length: 35.2, width: 20.8, angle: -11.5, mergesWithBody: true),
        ],
        eyes: [
            Part(center: CGPoint(x: 79, y: 129.5), size: CGSize(width: 15.5, height: 16)),
            Part(center: CGPoint(x: 147.5, y: 129.5), size: CGSize(width: 15.5, height: 16)),
        ],
        cheeks: [],
        headMergesWithBody: true,
        details: [
            // 腕の内側の短い線（上は丸く止まり、下は腕の先の輪郭につながる）
            Curve(start: CGPoint(x: 71.5, y: 218.5), control: CGPoint(x: 68.6, y: 224.2), end: CGPoint(x: 67.5, y: 230.5)),
            Curve(start: CGPoint(x: 160.5, y: 219), control: CGPoint(x: 163, y: 224.2), end: CGPoint(x: 163.5, y: 230)),
        ])

    /// 座った姿：正面を向く。頭は手前に自分の輪郭で描き（頭の下の線が見える）、その下から、
    /// 前に出した脚の丸いふくらみ 2 つがのぞく（胴・脚・腕はひと続き）。脚のあいだに Y の形の線、右に腕の折れ目と手の線
    static let simple2Sitting = CharacterPose(
        head: Part(center: CGPoint(x: 120.6, y: 109.6), size: CGSize(width: 200.2, height: 173.8)),
        body: Part(center: CGPoint(x: 132.4, y: 219.8), size: CGSize(width: 105.8, height: 39.6)),
        bodyCornerRatio: 0.3,
        legs: [
            Limb(joint: CGPoint(x: 103.3, y: 209.9), length: 38.5, width: 54.4, angle: 0, mergesWithBody: true, cornerRadius: 19.2),
            Limb(joint: CGPoint(x: 151.6, y: 209.9), length: 39.6, width: 57.1, angle: 0, mergesWithBody: true, cornerRadius: 19.8),
        ],
        arms: [
            Limb(joint: CGPoint(x: 86.8, y: 196.4), length: 21.2, width: 16.5, angle: 5, mergesWithBody: true),
            Limb(joint: CGPoint(x: 162.1, y: 190.9), length: 24.7, width: 14.3, angle: -30, mergesWithBody: true),
        ],
        eyes: [
            Part(center: CGPoint(x: 72.3, y: 142.9), size: CGSize(width: 15.5, height: 16)),
            Part(center: CGPoint(x: 136.5, y: 143.4), size: CGSize(width: 15.5, height: 16)),
        ],
        cheeks: [],
        headMergesWithBody: false,
        details: [
            // 脚のあいだの線と、その上の Y の形（右へ長く、左へ短く分かれる）
            Curve(start: CGPoint(x: 124.7, y: 246.2), control: CGPoint(x: 124.7, y: 223.6), end: CGPoint(x: 133, y: 216.5)),
            Curve(start: CGPoint(x: 124.2, y: 225.3), control: CGPoint(x: 122.4, y: 222.4), end: CGPoint(x: 120.7, y: 219.6)),
            // 右の腕の折れ目から、右の膝に置いた手の線へ
            Curve(start: CGPoint(x: 161.5, y: 211), control: CGPoint(x: 184.6, y: 218.7), end: CGPoint(x: 187.4, y: 227.5)),
        ])
}
