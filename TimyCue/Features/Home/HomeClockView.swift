import SwiftUI

/// ホームの時計（spec §6・追加仕様書 §44。2026-10-14 の修正指示）。
/// 時計そのものは現在時刻を指す普通のアナログ時計（時針・分針はいまの時刻。カウントダウンの針にはしない）。
/// 外周に 60 分を表す淡いリングを置き、その上に、いまの分の位置から出発（今は暫定で予定開始）の分の位置まで、
/// 時計回りに残り時間の弧を描く。弧の両端に「いま」「出発」、15 分ごとに少し長い目盛り。
/// 中央は小さな円形プレートに「出発まで」と残りの分。針はプレートの下を通る（針 → プレート → 文字の重なり。2026-10-14 決定）。
/// 1 分たつごとに、弧と針を穏やかに動かす（秒では動かさない）
struct HomeClockView: View {
    let face: HomeClockMath.Face
    /// 数える先の呼び名（「出発」。出発時刻の計算ができるまでは暫定で「開始」）
    let targetWord: String
    /// 時計の大きさに合わせて、中央の文字・針の太さ・目盛りを縮めるか（2026-10-16 Q85）。今の Home（外径 74％）は false のまま
    var scalesWithSize = false

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let style = scalesWithSize ? HomeClockStyle.scaled(diameter: size) : .standard
            let ringWidth = size * HomeMetrics.ringWidthRatio
            let ringRadius = size / 2 - ringWidth / 2
            let faceRadius = size / 2 - ringWidth - style.ringFaceGap
            ZStack {
                // 60 分を表す淡い背景のリング（もともとどれだけ時間があったかを残す）
                Circle()
                    .stroke(Theme.Colors.clockTrack, lineWidth: ringWidth)
                    .frame(width: ringRadius * 2, height: ringRadius * 2)
                // 残り時間の弧：いまの分の位置から、時計回りに出発の分の位置まで
                Circle()
                    .trim(from: 0, to: face.ringSweepDegrees / 360)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt))
                    .frame(width: ringRadius * 2, height: ringRadius * 2)
                    .rotationEffect(.degrees(face.ringStartDegrees - 90))
                // 15 分ごとの目盛り（時計の 0・15・30・45 分の位置。あと 1/4・半分を見て分かるように）
                ForEach(0..<4, id: \.self) { quarter in
                    Capsule()
                        .fill(Theme.Colors.textSecondary.opacity(0.55))
                        .frame(width: style.quarterTickWidth,
                               height: ringWidth + style.quarterTickOverhang * 2)
                        .offset(y: -ringRadius)
                        .rotationEffect(.degrees(Double(quarter) * 90))
                }
                // 文字盤と時の目盛り
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: faceRadius * 2, height: faceRadius * 2)
                ForEach(0..<12, id: \.self) { hour in
                    Capsule()
                        .fill(Theme.Colors.textSecondary.opacity(0.6))
                        .frame(width: style.hourTickWidth, height: style.hourTickLength)
                        .offset(y: -(faceRadius - style.hourTickInset - style.hourTickLength / 2))
                        .rotationEffect(.degrees(Double(hour) * 30))
                }
                // 針（いまの時刻。時針は分に合わせて少しずつ進む）。長さ・大きさの割合は、どれも時計の外径（size）に対する割合
                hand(length: size * HomeMetrics.hourHandLengthRatio,
                     width: style.hourHandWidth,
                     degrees: face.hourHandDegrees)
                hand(length: size * HomeMetrics.minuteHandLengthRatio,
                     width: style.minuteHandWidth,
                     degrees: face.minuteHandDegrees)
                // 針の根元を隠す中央のプレートと、その上の「出発まで／23分」（文字に縁取りはしない）
                Circle()
                    .fill(Theme.Colors.clockPlate)
                    .overlay { Circle().strokeBorder(Theme.Colors.separator, lineWidth: HomeMetrics.centerPlateBorderWidth) }
                    .frame(width: size * HomeMetrics.centerPlateRatio, height: size * HomeMetrics.centerPlateRatio)
                centerText(style)
                markers(size: size, ringRadius: ringRadius, labelRadius: size / 2 + HomeMetrics.markerLabelGap)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        // 1 分たつごとに、弧が少し短くなり針が進む。ガクッと切り替えず、穏やかにつなぐ
        .animation(.easeInOut(duration: HomeMetrics.minuteAnimation), value: face)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(targetWord)まであと\(face.remainingMinutes)分。\(HomeClockMath.flowText(now: face.now, target: face.target))")
    }

    private var ringColor: Color {
        switch face.band {
        case .plenty: Theme.Colors.clockPlenty
        case .half: Theme.Colors.clockHalf
        case .last: Theme.Colors.clockLast
        }
    }

    /// 真ん中から伸びる針。degrees は 12 時の位置から時計回り
    private func hand(length: CGFloat, width: CGFloat, degrees: Double) -> some View {
        Capsule()
            .fill(Theme.Colors.textPrimary)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }

    /// 中央の「出発まで」と「23分」（プレートの上に載せる）
    private func centerText(_ style: HomeClockStyle) -> some View {
        VStack(spacing: -4) {
            Text("\(targetWord)まで")
                .font(style.centerCaptionFont)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(face.remainingMinutes)")
                    .font(style.centerNumberFont)
                Text("分")
                    .font(style.centerUnitFont)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    /// 弧の両端の印。始まりは「いま」（小さな丸）、終わりは「出発」（少し大きく濃い丸）。文字はリングの外に小さく。
    /// 2 つの丸がちょうど重なるとき（60 分前）は、いまの丸を少し内側、出発の丸を少し外側へずらして見分けられるようにする
    @ViewBuilder
    private func markers(size: CGFloat, ringRadius: CGFloat, labelRadius: CGFloat) -> some View {
        let start = face.ringStartDegrees
        let end = face.ringStartDegrees + face.ringSweepDegrees
        let shift = face.markersCoincide ? size * HomeMetrics.coincideShiftRatio : 0
        Circle()
            .fill(Theme.Colors.surface)
            .overlay { Circle().strokeBorder(Theme.Colors.textPrimary, lineWidth: 1.5) }
            .frame(width: size * HomeMetrics.nowDotRatio, height: size * HomeMetrics.nowDotRatio)
            .offset(Self.offset(start, radius: ringRadius - shift))
        Circle()
            .fill(Theme.Colors.textPrimary)
            .frame(width: size * HomeMetrics.targetDotRatio, height: size * HomeMetrics.targetDotRatio)
            .offset(Self.offset(end, radius: ringRadius + shift))
        if face.showsNowLabel {
            Text("いま")
                .font(HomeMetrics.nowLabelFont)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize()
                .offset(Self.offset(start, radius: labelRadius))
        }
        Text(targetWord)
            .font(HomeMetrics.targetLabelFont)
            .foregroundStyle(Theme.Colors.textPrimary)
            .fixedSize()
            .offset(Self.offset(end, radius: labelRadius))
    }

    /// 12 時の位置から時計回りに degrees の向きへ radius だけ離れた所（真ん中からのずれ）
    private static func offset(_ degrees: Double, radius: CGFloat) -> CGSize {
        let radians = degrees.truncatingRemainder(dividingBy: 360) * .pi / 180
        return CGSize(width: radius * CGFloat(sin(radians)), height: -radius * CGFloat(cos(radians)))
    }
}
