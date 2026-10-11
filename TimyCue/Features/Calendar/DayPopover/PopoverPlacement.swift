import CoreGraphics

/// 日付吹き出しの置き場所の決まり（仕様 §22・§23・Q11）。画面に依らない計算だけを置く。
///
/// 基本は押したセルの近く。下に入れば下、入らなければ上、それでも入らなければ左右。2 つが重なるときは左右・上下をずらす。
/// 優先するのは「画面内に収まること」「吹き出し同士が重ならないこと」「元の日付セルや予定ブロックを隠さないこと」（Q11・Q28(b)・追加）。
enum PopoverPlacement {
    /// 吹き出しの枠を、開いた順（古い順）に決める
    static func frames(container: CGSize,
                       anchors: [CGRect],
                       sizes: [CGSize],
                       gap: CGFloat,
                       margin: CGFloat) -> [CGRect] {
        var placed: [CGRect] = []
        for (anchor, size) in zip(anchors, sizes) {
            let options = candidates(anchor: anchor, size: size, placed: placed, container: container, gap: gap, margin: margin)
            let fitting = options.first {
                fits($0, in: container, margin: margin) && !overlapsAny($0, placed + anchors, gap: gap)
            }
            let chosen = fitting ?? options.min {
                penalty($0, placed + anchors, container, margin, gap) < penalty($1, placed + anchors, container, margin, gap)
            }
                ?? CGRect(origin: .zero, size: size)
            placed.append(chosen)
        }
        return placed
    }

    /// 試す順の候補：セルの下・上（真ん中寄せ → 左寄せ → 右寄せ）、セルの右・左、すでに置いた吹き出しの下・上
    private static func candidates(anchor: CGRect, size: CGSize, placed: [CGRect],
                                   container: CGSize, gap: CGFloat, margin: CGFloat) -> [CGRect] {
        let centeredX = clamp(anchor.midX - size.width / 2, margin, container.width - size.width - margin)
        let leftX = margin
        let rightX = max(margin, container.width - size.width - margin)
        let below = anchor.maxY + gap
        let above = anchor.minY - gap - size.height

        var result: [CGRect] = []
        for y in [below, above] {
            for x in [centeredX, leftX, rightX] {
                result.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            }
        }
        let sideY = clamp(anchor.midY - size.height / 2, margin, container.height - size.height - margin)
        result.append(CGRect(x: anchor.maxX + gap, y: sideY, width: size.width, height: size.height))
        result.append(CGRect(x: anchor.minX - gap - size.width, y: sideY, width: size.width, height: size.height))
        for other in placed {
            for y in [other.maxY + gap, other.minY - gap - size.height] {
                result.append(CGRect(x: centeredX, y: y, width: size.width, height: size.height))
            }
        }
        return result
    }

    private static func fits(_ rect: CGRect, in container: CGSize, margin: CGFloat) -> Bool {
        rect.minX >= margin - 0.5 && rect.maxX <= container.width - margin + 0.5
            && rect.minY >= margin - 0.5 && rect.maxY <= container.height - margin + 0.5
    }

    private static func overlapsAny(_ rect: CGRect, _ others: [CGRect], gap: CGFloat) -> Bool {
        // 間を gap だけ空ける。ちょうど gap 離れて並ぶ候補は通したいので、少しだけ緩める
        let half = max(gap / 2 - 0.5, 0)
        return others.contains { $0.insetBy(dx: -half, dy: -half).intersects(rect.insetBy(dx: -half, dy: -half)) }
    }

    /// どの候補も入らないときに選ぶための悪さ（重なる面積＋はみ出す面積）
    private static func penalty(_ rect: CGRect, _ others: [CGRect], _ container: CGSize,
                                _ margin: CGFloat, _ gap: CGFloat) -> CGFloat {
        let overlap = others.reduce(CGFloat(0)) { total, other in
            let shared = rect.intersection(other)
            return total + (shared.isNull ? 0 : shared.width * shared.height)
        }
        let bounds = CGRect(x: margin, y: margin, width: container.width - margin * 2, height: container.height - margin * 2)
        let inside = rect.intersection(bounds)
        let insideArea = inside.isNull ? 0 : inside.width * inside.height
        return overlap + (rect.width * rect.height - insideArea)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}
