import SwiftUI

/// 人型キャラクター（spec §88.4）。height は立った姿の全身の高さ（pt。小物を除く。2026-10-15 決定 Q79）。
/// 部品は図形で描く（どの大きさでもにじまない）。背景は描かず、床や足元の影も置かない（2026-10-15 決定）
struct CharacterFigure: View {
    let height: CGFloat
    var pose: CharacterPose = .standing
    var style: CharacterStyle = .current
    /// 立った姿の全身の高さ（100 の単位）。height をこの高さに合わせる（案ごとに違う）
    var referenceHeight: CGFloat = 100
    /// 装備（正式の 3 モードの甲羅・うさぎの耳のフード）。本体とは別の部品
    var equipment: CharacterEquipment = .none

    /// 案と姿勢（と、正式の 3 モードならモード）で描く
    init(height: CGFloat, design: CharacterDesign, posture: CharacterPosture, mode: CharacterMode = .human) {
        self.init(height: height, pose: design.pose(posture), style: design.style, referenceHeight: design.referenceHeight,
                  equipment: design.equipment(mode))
    }

    init(height: CGFloat, pose: CharacterPose = .standing, style: CharacterStyle = .current, referenceHeight: CGFloat = 100,
         equipment: CharacterEquipment = .none) {
        self.height = height
        self.pose = pose
        self.style = style
        self.referenceHeight = referenceHeight
        self.equipment = equipment
    }

    var body: some View {
        let layout = CharacterLayout(height: height, pose: pose, style: style, referenceHeight: referenceHeight, equipment: equipment)
        Canvas { context, _ in
            Self.draw(layout, in: context)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        // 飾りとして読み上げない。時計・予定・知らせは今どおり読み上げる（アニメーションだけに大事な情報を頼らない：§88.1）
        .accessibilityHidden(true)
    }

    /// 描く順：体の後ろの装備（甲羅） → 胴と、胴とひと続きの脚・腕・頭・装備（フードと耳） → 手前の脚・腕 → 頭 → 手前の装備（耳の内側・
    /// フードの縁取り） → ほっぺ・目 → 細部の線。
    /// 線の太さの倍で輪郭を描いてから中を塗ると、外側に線の太さぶんの輪郭だけが残る。いくつかをまとめて描くと、
    /// 重なった所に線が出ず、ひと続きの形になる（立った姿の胴と脚。2 本のあいだの切れ込みだけが残る）
    static func draw(_ layout: CharacterLayout, in context: GraphicsContext) {
        let pose = layout.pose
        let outline = Color(hex: layout.style.palette.outline)
        let bodyFill = Color(hex: layout.style.palette.bodyFill)
        let stroke = StrokeStyle(lineWidth: layout.outlineWidth * 2, lineCap: .round, lineJoin: .round)
        func outlineAndFill(_ paths: [Path], fill: Color) {
            for path in paths { context.stroke(path, with: .color(outline), style: stroke) }
            for path in paths { context.fill(path, with: .color(fill)) }
        }
        // 体の後ろの装備（甲羅）。模様の線は形の中だけに描く
        for piece in layout.equipment.behind {
            let path = layout.path(for: piece.shape)
            if piece.outlined {
                outlineAndFill([path], fill: layout.color(for: piece.paint))
            } else {
                context.fill(path, with: .color(layout.color(for: piece.paint)))
            }
            if !piece.pattern.isEmpty {
                var inside = context
                inside.clip(to: path)
                let line = StrokeStyle(lineWidth: layout.outlineWidth * CharacterMetrics.patternWidthRatio, lineCap: .round)
                for segment in piece.pattern {
                    inside.stroke(layout.path(for: segment), with: .color(Color(hex: layout.style.palette.shellLine)), style: line)
                }
            }
        }
        let limbs = pose.legs + pose.arms
        var silhouette = limbs.filter(\.mergesWithBody).map { layout.path(for: $0) } + [layout.bodyPath]
        if pose.headMergesWithBody { silhouette.append(layout.ellipsePath(pose.head)) }
        silhouette += layout.equipment.mergedWithBody.map { layout.path(for: $0) }
        outlineAndFill(silhouette, fill: bodyFill)
        for limb in limbs where !limb.mergesWithBody {
            outlineAndFill([layout.path(for: limb)], fill: bodyFill)
        }
        if !pose.headMergesWithBody { outlineAndFill([layout.ellipsePath(pose.head)], fill: bodyFill) }
        for group in pose.frontGroups {
            outlineAndFill(group.map { layout.path(for: $0) }, fill: bodyFill)
        }
        // 手前の装備（耳の内側）と、フードの顔まわりの縁取り・耳の付け根の帯
        for piece in layout.equipment.front {
            let path = layout.path(for: piece.shape)
            if piece.outlined {
                outlineAndFill([path], fill: layout.color(for: piece.paint))
            } else {
                context.fill(path, with: .color(layout.color(for: piece.paint)))
            }
        }
        for arc in layout.equipment.arcs {
            context.stroke(layout.path(for: arc), with: .color(layout.color(for: arc.paint)),
                           style: StrokeStyle(lineWidth: layout.outlineWidth * arc.widthRatio, lineCap: .round, lineJoin: .round))
        }
        if layout.style.cheekOpacity > 0 {
            for cheek in pose.cheeks {
                context.fill(layout.ellipsePath(cheek), with: .color(CharacterMetrics.cheek.opacity(layout.style.cheekOpacity)))
            }
        }
        for eye in pose.eyes {
            context.fill(layout.ellipsePath(eye), with: .color(Color(hex: layout.style.palette.eye)))
        }
        let detail = StrokeStyle(lineWidth: layout.outlineWidth, lineCap: .round, lineJoin: .round)
        for curve in pose.details {
            context.stroke(layout.path(for: curve), with: .color(outline), style: detail)
        }
    }
}

/// キャラクターの大きさと置き方。座った姿も立った姿と同じ縮尺で描くので、座ると低くなる（足の先の高さはそろう）。
/// 外の輪郭がはみ出さないよう、線の太さの分だけ周りをあける
struct CharacterLayout: Equatable {
    let pose: CharacterPose
    let style: CharacterStyle
    /// 装備（甲羅・うさぎの耳のフード）。体の大きさ（bodySize）には入れず、描く枠（size）には入れる
    let equipment: CharacterEquipment
    /// 100 の単位 1 つあたりの pt
    let scale: CGFloat
    let outlineWidth: CGFloat
    /// 体（小物・装備を除く）の外形の大きさ（pt。輪郭の線は除く）
    let bodySize: CGSize
    /// 描く枠の大きさ（装備と、輪郭の線の分を含む）
    let size: CGSize
    private let origin: CGPoint

    /// height は立った姿の全身の高さ（pt。装備を除く）。referenceHeight（100 の単位での立った姿の高さ）を height に合わせる
    init(height: CGFloat, pose: CharacterPose, style: CharacterStyle = .current, referenceHeight: CGFloat = 100,
         equipment: CharacterEquipment = .none) {
        self.pose = pose
        self.style = style
        self.equipment = equipment
        scale = height / referenceHeight
        outlineWidth = CharacterMetrics.outlineWidth(forHeight: height, ratio: style.outlineRatio)
        let bounds = pose.bounds
        let frame = equipment.bounds.map { bounds.union($0) } ?? bounds
        origin = frame.origin
        bodySize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        size = CGSize(width: frame.width * scale + outlineWidth * 2, height: frame.height * scale + outlineWidth * 2)
    }

    init(height: CGFloat, design: CharacterDesign, posture: CharacterPosture, mode: CharacterMode = .human) {
        self.init(height: height, pose: design.pose(posture), style: design.style, referenceHeight: design.referenceHeight,
                  equipment: design.equipment(mode))
    }

    /// 装備の色
    func color(for paint: CharacterEquipment.Paint) -> Color {
        let palette = style.palette
        return switch paint {
        case .body: Color(hex: palette.bodyFill)
        case .shellPlate: Color(hex: palette.shellPlate)
        case .earInner: Color(hex: palette.earInner)
        case .hoodRing: Color(hex: palette.hoodRing)
        case .hoodBand: Color(hex: palette.hoodBand)
        }
    }

    /// 100 の単位の点を、描く枠の中の点（pt）へ
    func point(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: (unit.x - origin.x) * scale + outlineWidth, y: (unit.y - origin.y) * scale + outlineWidth)
    }

    func ellipsePath(_ part: CharacterPose.Part) -> Path {
        Path(ellipseIn: rect(part)).applying(rotation(part))
    }

    var bodyPath: Path {
        Path(roundedRect: rect(pose.body), cornerRadius: pose.bodyCornerRadius * scale, style: .circular)
            .applying(rotation(pose.body))
    }

    func path(for limb: CharacterPose.Limb) -> Path {
        let part = limb.part
        return Path(roundedRect: rect(part), cornerRadius: limb.resolvedCornerRadius * scale, style: .circular)
            .applying(rotation(part))
    }

    func path(for shape: CharacterPose.Shape) -> Path {
        switch shape {
        case .ellipse(let part):
            return ellipsePath(part)
        case .roundedRect(let part, let cornerRatio):
            return Path(roundedRect: rect(part), cornerRadius: CharacterPose.cornerRadius(part, ratio: cornerRatio) * scale,
                        style: .circular)
                .applying(rotation(part))
        }
    }

    func path(for curve: CharacterPose.Curve) -> Path {
        var path = Path()
        path.move(to: point(curve.start))
        path.addQuadCurve(to: point(curve.end), control: point(curve.control))
        return path
    }

    func path(for segment: CharacterEquipment.Segment) -> Path {
        var path = Path()
        path.move(to: point(segment.start))
        path.addLine(to: point(segment.end))
        return path
    }

    /// 楕円の弧を、細かい折れ線で描く（start から end へ角度が増える向き。画面では時計回り）
    func path(for arc: CharacterEquipment.Arc) -> Path {
        var path = Path()
        let steps = 48
        for step in 0...steps {
            let degrees = arc.startDegrees + (arc.endDegrees - arc.startDegrees) * Double(step) / Double(steps)
            let radians = degrees * .pi / 180
            let unit = CGPoint(x: arc.center.x + arc.size.width / 2 * CGFloat(cos(radians)),
                               y: arc.center.y + arc.size.height / 2 * CGFloat(sin(radians)))
            if step == 0 {
                path.move(to: point(unit))
            } else {
                path.addLine(to: point(unit))
            }
        }
        return path
    }

    private func rect(_ part: CharacterPose.Part) -> CGRect {
        let center = point(part.center)
        let width = part.size.width * scale
        let height = part.size.height * scale
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// 部品の中心のまわりに回す（正は画面で時計回り）
    private func rotation(_ part: CharacterPose.Part) -> CGAffineTransform {
        let center = point(part.center)
        return CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(part.rotation * .pi / 180))
            .translatedBy(x: -center.x, y: -center.y)
    }
}
