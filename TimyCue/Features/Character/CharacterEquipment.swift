import CoreGraphics

/// 正式キャラクターの見た目のモード（2026-10-16。spec §88.4・Q89）。同じキャラクターが装備を替える
enum CharacterMode: String, CaseIterable {
    /// 亀モード：甲羅を背負う
    case turtle
    /// 人型モード：装備なし
    case human
    /// うさぎモード：うさぎの耳のフードをかぶる（モードの間は耳をいつも付ける）
    case rabbit
}

/// 着けたり外したりする装備（2026-10-16 正式原画の 3 モード。spec §88.4）。本体（CharacterPose）とは別の部品で、単位は本体と同じ。
/// コーヒーのカップ・スマートフォン・バッグなどの日常の小物は入れない（H3 で正式な素材を決めてから、別の素材として足す）
struct CharacterEquipment: Equatable {
    /// 本体の後ろに、順に描く形（甲羅）
    var behind: [Piece] = []
    /// 本体とひと続きにする形（フードの外形と耳）。重なった所に線を出さず、外側の輪郭だけを残す
    var mergedWithBody: [CharacterPose.Shape] = []
    /// 本体の手前に、順に塗る形（耳の内側）
    var front: [Piece] = []
    /// 本体の手前に描く弧（フードの顔まわりの縁取り・右の耳の付け根の帯）
    var arcs: [Arc] = []

    /// 色を塗る形
    struct Piece: Equatable {
        var shape: CharacterPose.Shape
        var paint: Paint
        /// 輪郭も描くか（耳の内側は塗るだけ）
        var outlined = true
        /// 形の中だけに描く模様の線（甲羅の板の境目）
        var pattern: [Segment] = []
    }

    /// 模様の線（直線）
    struct Segment: Equatable {
        var start: CGPoint
        var end: CGPoint
    }

    /// 楕円の弧。角度は度で、0 が右、画面で時計回りに増える（270 が真上）。start から end へ角度が増える向きに描く
    struct Arc: Equatable {
        var center: CGPoint
        var size: CGSize
        var startDegrees: Double
        var endDegrees: Double
        var paint: Paint
        /// 線の太さ（輪郭の線の見える太さに対する割合）
        var widthRatio: CGFloat
    }

    /// 装備の色（値は CharacterPalette）
    enum Paint: Equatable {
        case body
        case shellPlate
        case earInner
        case hoodRing
        case hoodBand
    }

    static let none = CharacterEquipment()

    var isEmpty: Bool { behind.isEmpty && mergedWithBody.isEmpty && front.isEmpty && arcs.isEmpty }

    /// 装備の形の外の枠（輪郭の線は含めない）。弧は形の中か縁にあるので見ない。装備がなければ nil
    var bounds: CGRect? {
        let shapes = behind.map(\.shape) + mergedWithBody + front.map(\.shape)
        guard let first = shapes.first else { return nil }
        return shapes.dropFirst().reduce(CharacterPose.bounds(of: first)) { $0.union(CharacterPose.bounds(of: $1)) }
    }
}

// 正式原画（docs/design-reference/characters/official-3modes/）の主な絵から測った装備。主な絵は「立つ」と縮尺が違うので、
// 頭（フード）の大きさと位置をそろえて本体の単位に直した
extension CharacterEquipment {
    /// モードごとの装備（正式）
    static func official3(_ mode: CharacterMode) -> CharacterEquipment {
        switch mode {
        case .turtle: turtleShell
        case .human: .none
        case .rabbit: rabbitHood
        }
    }

    /// 亀モードの甲羅：体の後ろにあり、見る人から見て左のわきに出る（原画の主な絵・切り替えの絵・Home の絵と同じ側）。
    /// 明るい黄緑の板と、少し暗い板の境目の線
    static let turtleShell = CharacterEquipment(behind: [
        Piece(shape: .ellipse(CharacterPose.Part(center: CGPoint(x: 29.3, y: 130.6), size: CGSize(width: 34.2, height: 64.7), rotation: -8.6)),
              paint: .shellPlate,
              pattern: [
                  Segment(start: CGPoint(x: 23, y: 96.7), end: CGPoint(x: 28.3, y: 113.8)),
                  Segment(start: CGPoint(x: 28.3, y: 113.8), end: CGPoint(x: 13.3, y: 120.2)),
                  Segment(start: CGPoint(x: 28.3, y: 113.8), end: CGPoint(x: 42.2, y: 114.8)),
                  Segment(start: CGPoint(x: 28.3, y: 113.8), end: CGPoint(x: 28.3, y: 144.7)),
                  Segment(start: CGPoint(x: 15.5, y: 145.8), end: CGPoint(x: 41.1, y: 142.6)),
                  Segment(start: CGPoint(x: 28.3, y: 144.7), end: CGPoint(x: 32.6, y: 161.8)),
              ]),
    ])

    /// うさぎモードのフード：外形は頭とほぼ同じ大きさで、長い耳とひと続き（耳の付け根に線はない）。耳の内側はピンク。
    /// 顔のまわりに薄い茶色の縁取り（上から両わきを下りて、肩のあたりで終わる）。右の耳の付け根に赤い帯（原画どおり）
    static let rabbitHood = CharacterEquipment(
        mergedWithBody: [
            .ellipse(CharacterPose.Part(center: CGPoint(x: 91, y: 76.9), size: CGSize(width: 129.2, height: 123.6))),
            .ellipse(CharacterPose.Part(center: CGPoint(x: 58, y: 2), size: CGSize(width: 27.3, height: 59.1), rotation: -12)),
            .ellipse(CharacterPose.Part(center: CGPoint(x: 131.9, y: 4.2), size: CGSize(width: 29.6, height: 59.1), rotation: 18)),
        ],
        front: [
            Piece(shape: .ellipse(CharacterPose.Part(center: CGPoint(x: 62, y: 6.5), size: CGSize(width: 11.4, height: 34.1), rotation: -12)),
                  paint: .earInner, outlined: false),
            Piece(shape: .ellipse(CharacterPose.Part(center: CGPoint(x: 127.4, y: 8.2), size: CGSize(width: 13.6, height: 33), rotation: 18)),
                  paint: .earInner, outlined: false),
        ],
        arcs: [
            Arc(center: CGPoint(x: 92.1, y: 92.9), size: CGSize(width: 109.2, height: 106.9), startDegrees: 160, endDegrees: 380,
                paint: .hoodRing, widthRatio: 0.5),
            // フードの輪郭の線の真ん中（外形より線の太さの半分だけ外）に沿って、右の耳の付け根をまたぐ
            Arc(center: CGPoint(x: 91, y: 76.9), size: CGSize(width: 134.2, height: 128.6), startDegrees: 290, endDegrees: 308,
                paint: .hoodBand, widthRatio: 1),
        ])
}
