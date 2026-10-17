import SwiftUI

/// 人型キャラクター（spec §88.4）。height は立った姿の全身の高さ（pt。小物・装備を除く。2026-10-15 決定 Q79）。
/// 部品は図形で描く（どの大きさでもにじまない）。背景は描かず、床や足元の影も置かない（2026-10-15 決定）。
/// 装備（甲羅・うさぎの耳の被り物）は本体とは別の部品で、gear に入れたものだけを描く（2026-10-16 キャラクター 3 モード）
struct CharacterFigure: View {
    let height: CGFloat
    var pose: CharacterPose = .standing
    var style: CharacterStyle = .current
    /// 立った姿の全身の高さ（100 の単位）。height をこの高さに合わせる（案ごとに違う）
    var referenceHeight: CGFloat = 100
    /// 着ける装備と、その形・色（gearSet が nil なら装備を描かない）
    var gear: Set<CharacterGear> = []
    var gearSet: CharacterGearSet?

    /// 案と姿勢で描く（2026-10-16 H1 の案の比較）
    init(height: CGFloat, design: CharacterDesign, posture: CharacterPosture) {
        self.init(height: height, pose: design.pose(posture), style: design.style, referenceHeight: design.referenceHeight)
    }

    /// 正式キャラクター 3 モードの立ち姿（2026-10-16。spec §88.4）。height は本体の高さで、甲羅・耳の分は枠を広げる
    init(height: CGFloat, mode: CharacterMode) {
        self.init(height: height, pose: OfficialCharacter.standing, style: OfficialCharacter.style,
                  referenceHeight: OfficialCharacter.referenceHeight, gear: mode.gear, gearSet: OfficialCharacter.gear)
    }

    init(height: CGFloat, pose: CharacterPose = .standing, style: CharacterStyle = .current, referenceHeight: CGFloat = 100,
         gear: Set<CharacterGear> = [], gearSet: CharacterGearSet? = nil) {
        self.height = height
        self.pose = pose
        self.style = style
        self.referenceHeight = referenceHeight
        self.gear = gear
        self.gearSet = gearSet
    }

    /// 大きさと置き方（描く枠・本体の位置）。並べる側が本体の位置をそろえるときにも使う
    var layout: CharacterLayout {
        CharacterLayout(height: height, pose: pose, style: style, referenceHeight: referenceHeight,
                        gearBounds: gearSet?.bounds(for: gear) ?? .null)
    }

    var body: some View {
        let layout = self.layout
        Canvas { context, _ in
            Self.draw(layout, gear: gear, gearSet: gearSet, in: context)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        // 飾りとして読み上げない。時計・予定・知らせは今どおり読み上げる（アニメーションだけに大事な情報を頼らない：§88.1）
        .accessibilityHidden(true)
    }

    /// 描く順：甲羅（本体の後ろ）→ うさぎの耳（頭の後ろ）→ 胴と、胴とひと続きの脚・腕 → 手前の脚・腕 → 頭 →
    /// フードの顔まわりの線 → ほっぺ・目 → 細部の線。
    /// 線の太さの倍で輪郭を描いてから中を塗ると、外側に線の太さぶんの輪郭だけが残る。いくつかをまとめて描くと、
    /// 重なった所に線が出ず、ひと続きの形になる（立った姿の胴と脚。2 本のあいだの切れ込みだけが残る）
    static func draw(_ layout: CharacterLayout, gear: Set<CharacterGear> = [], gearSet: CharacterGearSet? = nil,
                     in context: GraphicsContext) {
        let pose = layout.pose
        let palette = layout.style.palette
        let stroke = StrokeStyle(lineWidth: layout.outlineWidth * 2, lineCap: .round, lineJoin: .round)
        func outlineAndFill(_ paths: [Path], fill: Color) {
            for path in paths { context.stroke(path, with: .color(palette.outline), style: stroke) }
            for path in paths { context.fill(path, with: .color(fill)) }
        }
        if let gearSet, gear.contains(.shell) {
            let shell = layout.ellipsePath(gearSet.shell.shape)
            outlineAndFill([shell], fill: gearSet.palette.shellFill)
            var pattern = Path()
            for line in gearSet.shell.patternLines() {
                pattern.addLines(line.map { layout.point($0) })
            }
            let patternStyle = StrokeStyle(lineWidth: layout.outlineWidth * CharacterMetrics.shellPatternRatio,
                                           lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.clip(to: shell)
                layer.stroke(pattern, with: .color(gearSet.palette.shellLine), style: patternStyle)
            }
        }
        if let gearSet, gear.contains(.rabbitHood) {
            for (ear, inner) in zip(gearSet.rabbitHood.ears, gearSet.rabbitHood.earInners) {
                outlineAndFill([layout.ellipsePath(ear)], fill: palette.fill)
                context.fill(layout.ellipsePath(inner), with: .color(gearSet.palette.earInner))
            }
        }
        let limbs = pose.legs + pose.arms
        var silhouette = limbs.filter(\.mergesWithBody).map { layout.path(for: $0) } + [layout.bodyPath]
        if pose.headMergesWithBody { silhouette.append(layout.ellipsePath(pose.head)) }
        outlineAndFill(silhouette, fill: palette.fill)
        for limb in limbs where !limb.mergesWithBody {
            outlineAndFill([layout.path(for: limb)], fill: palette.fill)
        }
        if !pose.headMergesWithBody { outlineAndFill([layout.ellipsePath(pose.head)], fill: palette.fill) }
        for group in pose.frontGroups {
            outlineAndFill(group.map { layout.path(for: $0) }, fill: palette.fill)
        }
        if let gearSet, gear.contains(.rabbitHood) {
            var faceLine = Path()
            faceLine.addLines(gearSet.rabbitHood.faceLine().map { layout.point($0) })
            context.stroke(faceLine, with: .color(gearSet.palette.hoodLine),
                           style: StrokeStyle(lineWidth: layout.outlineWidth * CharacterMetrics.hoodLineRatio, lineCap: .round))
        }
        if layout.style.cheekOpacity > 0 {
            for cheek in pose.cheeks {
                context.fill(layout.ellipsePath(cheek), with: .color(CharacterMetrics.cheek.opacity(layout.style.cheekOpacity)))
            }
        }
        for eye in pose.eyes {
            context.fill(layout.ellipsePath(eye), with: .color(palette.eye))
        }
        let detail = StrokeStyle(lineWidth: layout.outlineWidth, lineCap: .round, lineJoin: .round)
        for curve in pose.details {
            context.stroke(layout.path(for: curve), with: .color(palette.outline), style: detail)
        }
    }
}

/// キャラクターの大きさと置き方。座った姿も立った姿と同じ縮尺で描くので、座ると低くなる（足の先の高さはそろう）。
/// 外の輪郭がはみ出さないよう、線の太さの分だけ周りをあける。装備（甲羅・耳）があれば、その分も枠を広げる
/// （本体の大きさ bodySize は変えない。2026-10-16「甲羅・耳の必要な領域は別に確保する」）
struct CharacterLayout: Equatable {
    let pose: CharacterPose
    let style: CharacterStyle
    /// 100 の単位 1 つあたりの pt
    let scale: CGFloat
    let outlineWidth: CGFloat
    /// 体（小物・装備を除く）の外形の大きさ（pt。輪郭の線は除く）
    let bodySize: CGSize
    /// 描く枠の大きさ（輪郭の線の分と、装備の分を含む）
    let size: CGSize
    /// 描く枠の中の、体（装備を除く）の外形の位置と大きさ（pt。輪郭の線は除く）
    let bodyFrame: CGRect
    private let origin: CGPoint

    /// height は立った姿の全身の高さ（pt）。referenceHeight（100 の単位での立った姿の高さ）を height に合わせる。
    /// gearBounds は着けた装備の外形の枠（本体と同じ単位。なければ .null）
    init(height: CGFloat, pose: CharacterPose, style: CharacterStyle = .current, referenceHeight: CGFloat = 100,
         gearBounds: CGRect = .null) {
        self.pose = pose
        self.style = style
        let scale = height / referenceHeight
        self.scale = scale
        let outlineWidth = CharacterMetrics.outlineWidth(forHeight: height, ratio: style.outlineRatio)
        self.outlineWidth = outlineWidth
        let bounds = pose.bounds
        let whole = gearBounds.isNull ? bounds : bounds.union(gearBounds)
        origin = whole.origin
        bodySize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        size = CGSize(width: whole.width * scale + outlineWidth * 2, height: whole.height * scale + outlineWidth * 2)
        bodyFrame = CGRect(x: (bounds.minX - whole.minX) * scale + outlineWidth,
                           y: (bounds.minY - whole.minY) * scale + outlineWidth,
                           width: bodySize.width, height: bodySize.height)
    }

    /// 正式キャラクター 3 モードの立ち姿（CharacterFigure(height:mode:) と同じ置き方）
    init(height: CGFloat, mode: CharacterMode) {
        self.init(height: height, pose: OfficialCharacter.standing, style: OfficialCharacter.style,
                  referenceHeight: OfficialCharacter.referenceHeight,
                  gearBounds: OfficialCharacter.gear.bounds(for: mode.gear))
    }

    init(height: CGFloat, design: CharacterDesign, posture: CharacterPosture) {
        self.init(height: height, pose: design.pose(posture), style: design.style, referenceHeight: design.referenceHeight)
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
