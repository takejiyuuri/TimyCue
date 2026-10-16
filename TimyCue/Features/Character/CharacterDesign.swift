import CoreGraphics

/// 人型キャラクターの姿勢の種類
enum CharacterPosture: String, CaseIterable {
    case standing
    case sitting
}

/// 人型キャラクターの線とほっぺの見た目（spec §88.4。2026-10-16 H1 の案の比較）
struct CharacterStyle: Equatable {
    /// 輪郭の太さ（立った姿の全身の高さに対する割合。1〜2pt に収める）
    var outlineRatio: CGFloat
    /// ほっぺの濃さ（0 なら描かない）
    var cheekOpacity: Double

    /// H1 で作った形（現行案）
    static let current = CharacterStyle(outlineRatio: CharacterMetrics.outlineRatio, cheekOpacity: 0.85)
}

/// 人型キャラクターの案：立つ・座るの姿勢と、線・ほっぺの見た目。
/// 大きさ（○pt）は、その案の立った姿の全身の高さ（小物を除く）に合わせる（2026-10-15 決定 Q79）
struct CharacterDesign: Equatable {
    var standing: CharacterPose
    var sitting: CharacterPose
    var style: CharacterStyle

    /// 立った姿の全身の高さ（100 の単位）。○pt はこの高さに合わせ、座った姿も同じ縮尺で描く
    var referenceHeight: CGFloat { standing.bounds.height }

    func pose(_ posture: CharacterPosture) -> CharacterPose {
        switch posture {
        case .standing: standing
        case .sitting: sitting
        }
    }

    /// 部品の大きさ・位置を変えた案を作る（立つ・座るに同じ変え方をする）
    func adjusted(_ adjustment: CharacterPose.Adjustment, style: CharacterStyle) -> CharacterDesign {
        CharacterDesign(standing: standing.adjusted(adjustment), sitting: sitting.adjusted(adjustment), style: style)
    }

    /// H1 で最初に作った形（A' をもとにした旧試作。2026-10-15）
    static let current = CharacterDesign(standing: .standing, sitting: .sitting, style: .current)

    /// 正式のデザイン「2 シンプル」（2026-10-16 正式採用。原画を正本に描き直したもの。spec §88.4）。
    /// ほっぺ・口・リュック・影はない。輪郭の太さは原画と同じ割合（全身の高さの約 2.8％。36pt では下限の 1pt）
    static let simple2 = CharacterDesign(standing: .simple2Standing, sitting: .simple2Sitting,
                                         style: CharacterStyle(outlineRatio: 0.0276, cheekOpacity: 0))
}

extension CharacterPose {
    /// 案を作るための部品の変え方（2026-10-16 H1 の案の比較）。1・0・nil は変えない
    struct Adjustment: Equatable {
        /// 頭の大きさ。首のところ（頭のいちばん下）を動かさずに変え、目とほっぺも一緒に動かす
        var headScale: CGFloat = 1
        /// 目の幅・高さ（頭の大きさに合わせたうえで）
        var eyeScale = CGSize(width: 1, height: 1)
        /// 目とほっぺを上げる量（頭の高さに対する割合）
        var faceLift: CGFloat = 0
        var cheekScale: CGFloat = 1
        var armLengthScale: CGFloat = 1
        var legLengthScale: CGFloat = 1
        /// 腕を胴とひと続きの形にするか（nil は変えない）
        var armsMergeWithBody: Bool?
        /// 胴の幅（腕の付け根も一緒に寄せる）
        var bodyWidthScale: CGFloat = 1
    }

    func adjusted(_ adjustment: Adjustment) -> CharacterPose {
        var pose = self
        let neck = head.center.y + head.size.height / 2
        let headSize = CGSize(width: head.size.width * adjustment.headScale, height: head.size.height * adjustment.headScale)
        let headCenter = CGPoint(x: head.center.x, y: neck - headSize.height / 2)
        pose.head = Part(center: headCenter, size: headSize, rotation: head.rotation)
        func onFace(_ part: Part, scale: CGSize) -> Part {
            Part(center: CGPoint(x: headCenter.x + (part.center.x - head.center.x) * adjustment.headScale,
                                 y: headCenter.y + (part.center.y - head.center.y) * adjustment.headScale
                                    - adjustment.faceLift * headSize.height),
                 size: CGSize(width: part.size.width * adjustment.headScale * scale.width,
                              height: part.size.height * adjustment.headScale * scale.height),
                 rotation: part.rotation)
        }
        pose.eyes = eyes.map { onFace($0, scale: adjustment.eyeScale) }
        pose.cheeks = cheeks.map { onFace($0, scale: CGSize(width: adjustment.cheekScale, height: adjustment.cheekScale)) }
        pose.body.size.width *= adjustment.bodyWidthScale
        pose.arms = arms.map { arm in
            var arm = arm
            arm.joint.x = body.center.x + (arm.joint.x - body.center.x) * adjustment.bodyWidthScale
            arm.length *= adjustment.armLengthScale
            if let merges = adjustment.armsMergeWithBody { arm.mergesWithBody = merges }
            return arm
        }
        pose.legs = legs.map { leg in
            var leg = leg
            leg.length *= adjustment.legLengthScale
            return leg
        }
        return pose
    }
}
