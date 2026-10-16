import CoreGraphics

/// 正式キャラクターの装備（spec §88.4。2026-10-16 ユーザー指示「キャラクター素材の管理」）。
/// 本体（CharacterPose）とは別の描く部品で、本体の形を変えずに着けたり外したりする。
/// 位置・大きさの単位は本体と同じ（CharacterPose+Official の、原画の人型「立つ」の切り出しの画素）
enum CharacterGear: String, CaseIterable, Hashable {
    /// 亀の甲羅（本体の後ろに描く）
    case shell
    /// うさぎの耳の被り物（耳は頭の後ろ、顔まわりの線は頭の上に描く）
    case rabbitHood
}

/// 亀の甲羅：本体の後ろの右側に背負う、少し傾いた楕円と甲板の模様
struct ShellGear: Equatable {
    var shape: CharacterPose.Part
    /// 甲板の模様の折れ線。甲羅の中の座標（横 -0.5〜0.5・縦 -0.5〜0.5）で持ち、甲羅の大きさと向きに合わせる
    var pattern: [[CGPoint]]

    /// 模様の折れ線を本体の単位へ（甲羅の中心のまわりに、甲羅と同じ角度だけ回す）
    func patternLines() -> [[CGPoint]] {
        let radians = shape.rotation * .pi / 180
        let c = CGFloat(cos(radians))
        let s = CGFloat(sin(radians))
        return pattern.map { line in
            line.map { point in
                let x = point.x * shape.size.width
                let y = point.y * shape.size.height
                return CGPoint(x: shape.center.x + x * c - y * s, y: shape.center.y + x * s + y * c)
            }
        }
    }
}

/// うさぎの耳の被り物（フード）。耳 2 つ（内側はピンク）と、顔まわりの線（楕円の上半分）。
/// 被り物の外の形は頭の輪郭そのまま（頭の形は変えない）
struct RabbitHoodGear: Equatable {
    /// 左・右の耳（頭の後ろに描く。根元は頭に隠れる）
    var ears: [CharacterPose.Part]
    /// 耳の内側のピンク（左・右）
    var earInners: [CharacterPose.Part]
    /// 顔まわりの線は、この楕円の上半分（左の端から額を通って右の端まで）
    var faceOpening: CharacterPose.Part

    /// 顔まわりの線の点（本体の単位。左の端から右の端へ）
    func faceLine(segments: Int = 24) -> [CGPoint] {
        (0...segments).map { index in
            let angle = Double.pi + Double.pi * Double(index) / Double(segments)
            return CGPoint(x: faceOpening.center.x + faceOpening.size.width / 2 * CGFloat(cos(angle)),
                           y: faceOpening.center.y + faceOpening.size.height / 2 * CGFloat(sin(angle)))
        }
    }
}

/// 装備ひとそろい（形と色）
struct CharacterGearSet: Equatable {
    var shell: ShellGear
    var rabbitHood: RabbitHoodGear
    var palette: CharacterGearPalette

    /// 着けた装備の外形の枠（本体の単位。輪郭の線は含めない）。何も着けていなければ .null
    func bounds(for gear: Set<CharacterGear>) -> CGRect {
        var rect = CGRect.null
        if gear.contains(.shell) {
            rect = rect.union(CharacterPose.ellipseBounds(shell.shape))
        }
        if gear.contains(.rabbitHood) {
            for ear in rabbitHood.ears {
                rect = rect.union(CharacterPose.ellipseBounds(ear))
            }
        }
        return rect
    }
}

/// 見た目のモード（spec §88.4・Q89）。モードは「どの装備を着けるか」だけを決める。
/// 時間帯ごとの動作（§88.7）や実際の移動の状態とは分けて持つ（Q90）。時刻からモードを選ぶのは H2
enum CharacterMode: String, CaseIterable, Hashable {
    /// 亀モード（余裕あり）：甲羅を背負う
    case turtle
    /// 人型モード（準備）：装備なし
    case human
    /// うさぎモード（そろそろ）：うさぎの耳の被り物をかぶる（うさぎモードの間は耳を必ず付ける）
    case rabbit

    var title: String {
        switch self {
        case .turtle: "亀"
        case .human: "人型"
        case .rabbit: "うさぎ"
        }
    }

    var gear: Set<CharacterGear> {
        switch self {
        case .turtle: return [.shell]
        case .human: return []
        case .rabbit: return [.rabbitHood]
        }
    }
}
