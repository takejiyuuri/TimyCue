import SwiftUI

/// 演出帯の小さな知らせ（出発時刻を計算できない原因・目安。2026-10-14 決定：時計の下、時計がなければ予定の上に小さく）
enum HomeStageNote: Equatable {
    case problem(DepartureProblem)
    case note(String)
}

/// 画面のいちばん上の行：左に今日の日付、右に電池の残量（spec §88.2。Home はステータスバーを出さない。大きな見出しは置かない）。
/// 行の並べ方の高さは前の日付の大きさ（HomeLayoutMetrics.dateLayoutFont）で決め、大きくした日付は同じ中心で上下へ少しはみ出して描く
/// （下の時計・タイムラインの縦の位置と、出せる予定の数を変えない。2026-10-19 の見やすさの調整）。
/// 電池は行の中で縦の中央にそろえてから、ふだんのステータスバーの電池に近い高さへ上げる（HomeBatteryPlacement。日付は動かさない）
struct HomeTopBar: View {
    let dateTitle: String
    /// 取れないとき（シミュレータなど）は出さない
    let battery: HomeBatteryReading?
    /// 画面の Safe Area の上の高さ（電池を上げる量を決める）
    let safeAreaTop: CGFloat

    var body: some View {
        // 並べ方の高さだけを決める、見えない前の大きさの日付
        Text(dateTitle)
            .font(HomeLayoutMetrics.dateLayoutFont)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    Text(dateTitle)
                        .font(HomeLayoutMetrics.dateFont)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: Theme.Spacing.s)
                    if let battery {
                        HomeBatteryView(reading: battery)
                            .offset(y: -HomeBatteryPlacement.lift(safeAreaTop: safeAreaTop))
                    }
                }
                // 前の大きさの行より少し高くなる分は、上下へはみ出して描く（行の高さに合わせて日付を縮めない）
                .fixedSize(horizontal: false, vertical: true)
            }
    }
}

/// 右上の電池の残量（％とマーク。充電中は稲妻、残りが少ないときは警告の色。形は仮：§88.2）
struct HomeBatteryView: View {
    let reading: HomeBatteryReading

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(reading.text)
                .font(HomeLayoutMetrics.batteryFont)
            Image(systemName: reading.symbolName)
                .font(HomeLayoutMetrics.batteryIconFont)
        }
        .foregroundStyle(reading.isLow ? Theme.Colors.danger : Theme.Colors.textPrimary)
        // iOS のステータスバーと同じく、文字の大きさの設定で大きくしすぎない（画面の中央のノッチ・Dynamic Island の方へ広がらないように）
        .dynamicTypeSize(...HomeLayoutMetrics.batteryMaxTypeSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityText)
    }
}

/// 「終わった予定 ○件」（Q91。押すと吹き出しで一覧：Q84）。2026-10-19 の見やすさの調整で、文字を約 1pt 大きく、色を少し濃くした。
/// 並べ方の高さは前の大きさ（footnote）のまま：時計がないときは演出帯の高さがこの列で決まるので、タイムラインに使える高さ
/// （出せる予定の数）を変えないよう、大きくした文字は同じ中心で上下へ少しはみ出して描く
struct HomeFinishedButton: View {
    let text: String
    let onTap: () -> Void

    /// 文字の大きさ（footnote と同じ割合で、文字の大きさの設定に合わせる）
    @ScaledMetric(relativeTo: .footnote) private var textSize: CGFloat = HomeLayoutMetrics.finishedTextSize

    init(text: String, onTap: @escaping () -> Void) {
        self.text = text
        self.onTap = onTap
    }

    var body: some View {
        // 並べ方の高さと幅だけを決める、見えない前の大きさの文字
        label
            .font(HomeLayoutMetrics.headerLineFont)
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                label
                    .font(.system(size: textSize))
                    .foregroundStyle(HomeLayoutMetrics.finishedTextColor)
                    .fixedSize()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                    .homeBubbleAnchor(HomeStore.finishedAnchorID)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
            }
    }

    private var label: some View {
        HStack(spacing: 2) {
            Text(text)
            Image(systemName: "chevron.right")
                .font(.caption2)
        }
        .lineLimit(1)
    }
}

/// 演出帯（spec §88.3）：左の列に終日の予定・「終わった予定 ○件」（Q91）・知らせ（時計がないとき。Q92）、いちばん下（「いま」の直上）に人型（Q87・Q88）。
/// 時計を出すときは右に時計（画面の幅の 40％・右寄せ）と、その下の「8:30 → 9:15 出発予定」・小さな知らせ。
/// 時計がないときは帯を低くし、その分をタイムラインに使う。人型は時計が出ても定位置のまま（時計の近くへ移らない）
struct HomeStageView: View {
    let timeline: HomeTimeline
    let clock: HomeScreenModel.ClockDisplay?
    /// 主状態の大きな知らせ（時計がないときは日付の下に横幅を使って出す：Q92。時計を出す状態のときは知らせがない）
    let headline: String?
    let note: HomeStageNote?
    let mode: CharacterMode
    let screenWidth: CGFloat
    let onTapFinished: () -> Void
    let onTapProblem: (DepartureProblem) -> Void

    var body: some View {
        let diameter = HomeStageLayout.clockDiameter(screenWidth: screenWidth)
        HStack(alignment: .top, spacing: clock == nil ? 0 : HomeLayoutMetrics.clockLabelReach) {
            leftColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let clock {
                clockColumn(clock, diameter: diameter)
                    .padding(.trailing, HomeLayoutMetrics.clockTrailingInset)
            }
        }
        // 左の列を時計の列と同じ高さにのばす（人型の足元を時計の列の下の端にそろえる。H1 の比べる画面と同じ）
        .fixedSize(horizontal: false, vertical: true)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: HomeLayoutMetrics.headerLineSpacing) {
            // 終日の予定と表示のみのカレンダーの予定は、時間軸に混ぜず日付の下に控えめに（§88.2）
            if let allDay = timeline.allDayText {
                Text(allDay)
                    .font(HomeLayoutMetrics.headerLineFont)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            // 終わった予定は、日付・終日の予定の下、人型より上に畳む（Q91）。押すと吹き出しで一覧（Q84）
            if let finished = timeline.finishedText {
                HomeFinishedButton(text: finished, onTap: onTapFinished)
            }
            if clock == nil {
                if let headline {
                    Text(headline)
                        .font(HomeLayoutMetrics.headlineFont)
                        .foregroundStyle(Theme.Colors.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.xs)
                }
                if let note {
                    noteView(note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: HomeLayoutMetrics.figureTopGap)
            figure
        }
    }

    /// 人型（本体 36pt。止まった姿だけ。H3 まで動かさない）。本体の左の端を画面の左の余白にそろえ、甲羅は左の余白へはみ出す
    private var figure: some View {
        let layout = CharacterLayout(height: HomeLayoutMetrics.figureHeight, mode: mode)
        return CharacterFigure(height: HomeLayoutMetrics.figureHeight, mode: mode)
            .offset(x: -HomeStageLayout.figureLeadingShift(layout))
    }

    /// 時計（Q94 で確かめた時計をそのまま。中の文字・針は外径に合わせて縮める：Q85）と、その下の「8:30 → 9:15 出発予定」
    /// （文字の大きさは変えない：Q85）
    private func clockColumn(_ clock: HomeScreenModel.ClockDisplay, diameter: CGFloat) -> some View {
        VStack(spacing: HomeLayoutMetrics.clockFlowSpacing) {
            HomeClockView(face: clock.face, targetWord: clock.word, scalesWithSize: true)
                .frame(width: diameter, height: diameter)
                .padding(.vertical, HomeMetrics.clockLabelRoom)
            // 補助の説明：大きさは変えず（Q85）、色を少しだけ濃くして読みやすく（2026-10-19 の見やすさの調整）
            Text("\(HomeClockMath.flowText(now: clock.face.now, target: clock.face.target)) \(clock.word)予定")
                .font(HomeMetrics.flowFont)
                .foregroundStyle(HomeLayoutMetrics.flowTextColor)
                .lineLimit(1)
                .fixedSize()
            if let note {
                noteView(note)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: diameter + HomeLayoutMetrics.clockLabelReach)
            }
        }
    }

    /// 出発時刻を計算できない原因の小さな知らせ。地点が決まっていなければ押して「場所を確認」へ（Q66）。
    /// 普段よく使う移動手段をまだ選んでいなければ、押してもう一度選べる（今の Home と同じ）
    private func noteView(_ note: HomeStageNote) -> some View {
        Group {
            switch note {
            case .problem(let problem):
                switch problem {
                case .placeUnconfirmed:
                    // 押せると分かるよう、操作の文字の色にする（2026-10-14 実機の指摘「ずっと出る」）
                    Button { onTapProblem(problem) } label: {
                        Label(problem.message, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(Theme.Colors.actionText)
                    }
                case .transportNotChosen:
                    Button { onTapProblem(problem) } label: {
                        Text(problem.message)
                            .foregroundStyle(Theme.Colors.actionText)
                    }
                default:
                    Text(problem.message)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            case .note(let text):
                Text(text)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .font(HomeLayoutMetrics.noteFont)
        .lineLimit(HomeLayoutMetrics.noteLineLimit)
        .fixedSize(horizontal: false, vertical: true)
    }
}
