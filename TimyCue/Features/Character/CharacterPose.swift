import CoreGraphics

/// 人型キャラクター（spec §88.4）の姿勢。基準の絵は A'（docs/design-reference/）。
/// 部品（頭・胴・腕・脚・目・ほっぺ）の位置・大きさ・角度を、立った姿の全身の高さを 100 とした単位で持つ（横も同じ単位。立った姿の真ん中は x = 50）。
/// 腕と脚は付け根（肩・股）・長さ・角度で持ち、あとで付け根のまわりに回して動かせるようにする（H3 の動作）。小物は別の層で足す
struct CharacterPose: Equatable {
    /// 楕円や角の丸い四角の部品
    struct Part: Equatable {
        var center: CGPoint
        var size: CGSize
        /// 中心のまわりの角度（度。正は画面で時計回り）
        var rotation: Double = 0
    }

    /// 腕・脚：付け根から伸びる、先の丸い棒
    struct Limb: Equatable {
        /// 付け根（肩・股）
        var joint: CGPoint
        var length: CGFloat
        var width: CGFloat
        /// 度。0 で真下。正は画面で時計回り（左の腕・脚を外へ開く向き）、負は反時計回り（-90 で右へまっすぐ）
        var angle: Double
        /// true なら胴とひと続きの形にして、外側の輪郭だけを出す（立った姿の脚）。false なら手前に自分の輪郭で描く
        var mergesWithBody = false

        /// 棒の真ん中（付け根から、角度の向きへ長さの半分）
        var center: CGPoint {
            let radians = angle * .pi / 180
            return CGPoint(x: joint.x - CGFloat(sin(radians)) * length / 2,
                           y: joint.y + CGFloat(cos(radians)) * length / 2)
        }

        /// 棒を、角の丸みが太さの半分の四角として見たもの
        var part: Part {
            Part(center: center, size: CGSize(width: width, height: length), rotation: angle)
        }
    }

    var head: Part
    var body: Part
    /// 胴の角の丸み（胴の幅に対する割合。幅・高さの短い方の半分までにする）
    var bodyCornerRatio: CGFloat
    /// 描く順（後ろの腕・脚から）
    var legs: [Limb]
    var arms: [Limb]
    var eyes: [Part]
    var cheeks: [Part]

    var bodyCornerRadius: CGFloat {
        min(body.size.width * bodyCornerRatio, min(body.size.width, body.size.height) / 2)
    }

    /// 体（小物を除く）の外形の枠（100 の単位。輪郭の線の太さは含めない）。目とほっぺは頭の中なので見ない
    var bounds: CGRect {
        var rect = Self.ellipseBounds(head).union(Self.roundedRectBounds(body, cornerRadius: bodyCornerRadius))
        for limb in legs + arms {
            rect = rect.union(Self.roundedRectBounds(limb.part, cornerRadius: limb.width / 2))
        }
        return rect
    }

    /// 回した楕円の外の枠
    static func ellipseBounds(_ part: Part) -> CGRect {
        let a = part.size.width / 2
        let b = part.size.height / 2
        let radians = part.rotation * .pi / 180
        let c = CGFloat(cos(radians))
        let s = CGFloat(sin(radians))
        let halfWidth = (a * a * c * c + b * b * s * s).squareRoot()
        let halfHeight = (a * a * s * s + b * b * c * c).squareRoot()
        return CGRect(x: part.center.x - halfWidth, y: part.center.y - halfHeight, width: halfWidth * 2, height: halfHeight * 2)
    }

    /// 回した角の丸い四角の外の枠（丸みの分を除いた内側の四角を回し、丸みを足す）
    static func roundedRectBounds(_ part: Part, cornerRadius: CGFloat) -> CGRect {
        let radians = part.rotation * .pi / 180
        let c = abs(CGFloat(cos(radians)))
        let s = abs(CGFloat(sin(radians)))
        let innerHalfWidth = part.size.width / 2 - cornerRadius
        let innerHalfHeight = part.size.height / 2 - cornerRadius
        let halfWidth = innerHalfWidth * c + innerHalfHeight * s + cornerRadius
        let halfHeight = innerHalfWidth * s + innerHalfHeight * c + cornerRadius
        return CGRect(x: part.center.x - halfWidth, y: part.center.y - halfHeight, width: halfWidth * 2, height: halfHeight * 2)
    }
}

extension CharacterPose {
    /// 立った姿：正面を向いて、腕を少し開いた姿（A' の比較画像の「通常」に近い形）。頭のてっぺん 0 から足の先 100 まで。
    /// 大きめの丸い頭（全身の約 64％）、短い腕、短い脚（2 本のあいだに小さな切れ込み）。値は仮（2026-10-15 H1）
    static let standing = CharacterPose(
        head: Part(center: CGPoint(x: 50, y: 32), size: CGSize(width: 74, height: 64)),
        body: Part(center: CGPoint(x: 50, y: 75), size: CGSize(width: 38, height: 34)),
        bodyCornerRatio: 0.42,
        legs: [
            Limb(joint: CGPoint(x: 43, y: 84), length: 16, width: 14, angle: 0, mergesWithBody: true),
            Limb(joint: CGPoint(x: 57, y: 84), length: 16, width: 14, angle: 0, mergesWithBody: true),
        ],
        arms: [
            Limb(joint: CGPoint(x: 33.5, y: 64), length: 15, width: 9.5, angle: 18),
            Limb(joint: CGPoint(x: 66.5, y: 64), length: 15, width: 9.5, angle: -18),
        ],
        eyes: [
            Part(center: CGPoint(x: 40.5, y: 42), size: CGSize(width: 5.6, height: 7.2)),
            Part(center: CGPoint(x: 59.5, y: 42), size: CGSize(width: 5.6, height: 7.2)),
        ],
        cheeks: [
            Part(center: CGPoint(x: 32, y: 49), size: CGSize(width: 11, height: 6.5)),
            Part(center: CGPoint(x: 68, y: 49), size: CGSize(width: 11, height: 6.5)),
        ])

    /// 座った姿：脚を前（画面の右）へ伸ばして座り、顔を少し右へ向けた姿（比較画像の「休む」に近い形）。
    /// 立った姿と同じ縮尺で、足の先は 100（地面）のまま、頭のてっぺんが下がる。値は仮（2026-10-15 H1）
    static let sitting = CharacterPose(
        head: Part(center: CGPoint(x: 44, y: 45), size: CGSize(width: 74, height: 64)),
        body: Part(center: CGPoint(x: 45, y: 83), size: CGSize(width: 36, height: 30)),
        bodyCornerRatio: 0.42,
        legs: [
            Limb(joint: CGPoint(x: 52, y: 87.5), length: 22, width: 11.5, angle: -96, mergesWithBody: true),
            Limb(joint: CGPoint(x: 54, y: 94.2), length: 22, width: 12, angle: -92),
        ],
        arms: [
            Limb(joint: CGPoint(x: 34, y: 74), length: 13, width: 9, angle: 22),
            Limb(joint: CGPoint(x: 52, y: 74), length: 15, width: 9.5, angle: -45),
        ],
        eyes: [
            Part(center: CGPoint(x: 40, y: 55), size: CGSize(width: 5.6, height: 7.2)),
            Part(center: CGPoint(x: 58, y: 55), size: CGSize(width: 5.6, height: 7.2)),
        ],
        cheeks: [
            Part(center: CGPoint(x: 31.5, y: 62), size: CGSize(width: 11, height: 6.5)),
            Part(center: CGPoint(x: 65.5, y: 62), size: CGSize(width: 11, height: 6.5)),
        ])
}
