import SwiftUI
import UIKit

/// 演出帯の小さな知らせ（出発時刻を計算できない原因・目安。2026-10-14 決定：時計の下、時計がなければ予定の上に小さく）
enum HomeStageNote: Equatable {
    case problem(DepartureProblem)
    case note(String)
}

/// 画面のいちばん上の行：左に今日の日付（spec §88.2。Home はステータスバーを出さない。大きな見出しは置かない）。
/// 並べ方の高さは前と同じ「上の余白 10pt＋前の大きさ（20pt）の日付の行」（見えない文字で取る）。本当の日付（22pt）はその中の下に
/// そろえて置き、はみ出さない。大きくした分は、日付の上の余白が実際の文字の高さに合わせて縮んで吸収する（約 10 → 7.6pt）。
/// 下の時計・タイムラインの縦の位置と、タイムラインに出せる予定の数は前と同じ（2026-10-19 ビルド確認 #78 の直し）。
/// 右上の電池は、この行とは別の層に画面の形から置く（HomeBatteryLayer・HomeBatteryPlacement。電池の場所を変えても日付・時計・タイムラインは動かない）。
/// 電池が日付の行と同じ高さに来る機種（ノッチ・切り欠きのない機種）でも重ならないよう、右に電池の分をあけておく
struct HomeTopBar: View {
    let dateTitle: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 並べ方の高さだけを決める、見えない前の大きさの日付と上の余白
            Text(dateTitle)
                .font(HomeLayoutMetrics.dateLayoutFont)
                .lineLimit(1)
                .padding(.top, HomeLayoutMetrics.topPadding)
                .hidden()
                .accessibilityHidden(true)
            Text(dateTitle)
                .font(HomeLayoutMetrics.dateFont)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, HomeLayoutMetrics.batteryEstimatedSize.width + Theme.Spacing.s)
    }
}

/// 右上の電池の残量（％とマーク。充電中は稲妻、残りが少ないときは警告の色。形は仮：§88.2）。％とマークはひとまとめで置く
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

/// 右上の電池の層（spec §88.2。2026-10-19 ビルド確認 #77 の直し）。画面全体に広げ（Safe Area を無視する）、電池を画面の座標のまま、
/// HomeBatteryPlacement の枠の中心に置く（.position）。Safe Area の上の高さは、この層の GeometryReader の値と窓（UIKit）の値の大きいほう。
/// Home の中身（日付・時計・タイムライン）とは別の層なので、電池の場所を変えても中身は動かない。押せない（下の中身の操作を妨げない）。
/// #78 で、置いた位置が計算どおりなことを画面写真で確かめた（確かめの表示は外し、位置はテストで守る）
struct HomeBatteryLayer: View {
    /// 取れないとき（シミュレータなど）は出さない
    let reading: HomeBatteryReading?

    var body: some View {
        GeometryReader { proxy in
            if let reading {
                let safeAreaTop = HomeBatteryPlacement.topInset(swiftUI: proxy.safeAreaInsets.top, window: Self.windowSafeAreaTop)
                let frame = HomeBatteryPlacement.make(screenWidth: proxy.size.width, safeAreaTop: safeAreaTop)
                    .frame(screenWidth: proxy.size.width)
                HomeBatteryView(reading: reading)
                    .fixedSize()
                    // 「80%」も「100%」も右の端をそろえる（見込みの幅の枠の右に寄せる。はみ出しても切らない）
                    .frame(width: frame.width, height: frame.height, alignment: .trailing)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// この画面の窓（UIKit）の Safe Area の上の高さ。取れないときは nil
    @MainActor
    private static var windowSafeAreaTop: CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top
    }
}

/// 「終わった予定 ○件」（Q91。押すと吹き出しで一覧：Q84）。2026-10-19 の見やすさの調整で、文字を約 1pt 大きく、色を少し濃くした。
/// 並べ方の高さは「前の大きさ（footnote）の行＋finishedLineAllowance」（見えない文字で取る）。本当の文字（14pt）はその中の上に
/// そろえて置き、はみ出さない。足した高さの分は人型の上の最小の間を縮めて（figureTopGapWithFinished）、時計がないとき（演出帯の高さが
/// 左の列で決まるとき）も、タイムラインに出せる予定の数を前と同じにする（2026-10-19 ビルド確認 #78 の直し。日本語の文字でも見込みに頼らない）
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
        ZStack(alignment: .topLeading) {
            // 並べ方の高さだけを決める、見えない前の大きさの文字と、大きくした分のゆとり
            label
                .font(HomeLayoutMetrics.headerLineFont)
                .padding(.bottom, HomeLayoutMetrics.finishedLineAllowance)
                .hidden()
                .accessibilityHidden(true)
            label
                .font(.system(size: textSize))
                .foregroundStyle(HomeLayoutMetrics.finishedTextColor)
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
            // 「終わった予定」の行に足した高さの分は、人型の上の最小の間を縮めて吸収する（時計がないときもタイムラインの高さを保つ）
            Spacer(minLength: timeline.finishedText == nil ? HomeLayoutMetrics.figureTopGap : HomeLayoutMetrics.figureTopGapWithFinished)
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
