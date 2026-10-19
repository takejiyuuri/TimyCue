import SwiftUI

/// 新しい Home（H2。spec §88.2・§88.3）の配置の寸法・文字の大きさ・タイムラインの密度。実機で確かめて決めるので、値はここに集める。
/// どれも仮の値（docs/design-notes.md の H2 の画面見本の値と、H1 の比べる画面で確かめた値をもとにした）。
/// 時計そのものの寸法は HomeMetrics（外径 40％・中の文字は HomeClockStyle.scaled）
enum HomeLayoutMetrics {
    // MARK: - 画面の上（日付・終日の予定・電池）

    /// 画面の左右の余白
    static let horizontalPadding: CGFloat = Theme.Spacing.l
    /// Safe Area の上からの余白（Home はステータスバーを出さないので、小さい iPhone では画面の上の端からの余白になる）
    static let topPadding: CGFloat = 10
    /// 左上の日付（大きな見出しにはしない：§88.2。画面見本は 20pt）
    static let dateFont = Font.title3.weight(.semibold)
    /// 日付の下の終日の予定・「終わった予定 ○件」
    static let headerLineFont = Font.footnote
    static let headerLineSpacing: CGFloat = 4
    /// 右上の電池の残量（%）とマーク（画面見本：マーク 22×11pt＋「80%」。形は H2 の実機で決める：§88.2）
    static let batteryFont = Font.caption.weight(.semibold).monospacedDigit()
    static let batteryIconFont = Font.footnote
    /// これ以下（充電していないとき）は残りが少ない色にする（％。仮）
    static let batteryLowPercent = 20

    // MARK: - 演出帯（時計と人型）

    /// 時計の外径（画面の幅に対する割合。spec §88.3：40％）
    static let clockWidthRatio: CGFloat = HomeMetrics.clockWidthRatio
    /// 時計の右の余白。画面の左右の余白と合わせて、外周の「いま」「出発」の文字が画面の外へ出ない幅にする（H1 と同じ 14pt）
    static let clockTrailingInset: CGFloat = 14
    /// 時計の外周から「いま」「出発」の文字の外側の端までの長さ（文字の中心までの間隔＋文字の幅の半分。H1 と同じ）。
    /// 時計の左の列（終日の予定など）とのあいだもこの分あけて、文字が重ならないようにする
    static let clockLabelReach: CGFloat = HomeMetrics.markerLabelGap + 14
    /// 時計と、その下の「8:30 → 9:15 出発予定」とのあいだ
    static let clockFlowSpacing: CGFloat = Theme.Spacing.xs
    /// 人型の本体の高さ（spec §88.4：36pt）
    static let figureHeight: CGFloat = 36
    /// 日付・知らせと人型のあいだの最小の間、人型の足元と「いま」（または過ぎた出発の点）のあいだ（H1 と同じ 8pt。仮）
    static let figureTopGap: CGFloat = Theme.Spacing.s
    static let figureBottomGap: CGFloat = Theme.Spacing.s
    /// 主状態の大きな知らせ（時計がないときは日付の下に横幅を使って：Q92。色は今の Home のまま）
    static let headlineFont = Font.title3.weight(.bold)
    /// 出発時刻を計算できない原因・目安の知らせ（小さく）
    static let noteFont = Font.footnote
    static let noteLineLimit = 3

    // MARK: - タイムライン

    /// 左の点と縦の線の列の幅と、文字とのあいだ
    static let railWidth: CGFloat = 20
    static let railGap: CGFloat = Theme.Spacing.s
    /// 点どうしをつなぐ細い線と、同じ予定の出発の点と開始の点を結ぶ線の太さ
    static let railLineWidth: CGFloat = 2
    static let pairLineWidth: CGFloat = 3
    /// 点の大きさ（「いま」・予定・主状態の予定・出発の点）
    static let nowDot: CGFloat = 14
    static let eventDot: CGFloat = 10
    static let mainEventDot: CGFloat = 12
    static let departureDot: CGFloat = 9
    /// 「いま 8:52」と、過ぎた出発の点の行の高さ（文字の大きさの設定に合わせて広げる）
    static let nowRowHeight: CGFloat = 30
    static let pastDepartureRowHeight: CGFloat = 26
    static let nowFont = Font.headline.monospacedDigit()
    /// 過ぎた出発の点は控えめに（Q83）
    static let pastDepartureOpacity: Double = 0.7
    /// 時刻の欄の幅（「18:00」が入る幅）
    static let timeColumnWidth: CGFloat = 46
    /// 主状態の予定の札（予定名と場所の 2 行。画面見本の淡いオレンジ）
    static let mainCardFill = Color(hex: Theme.BrandPalette.lightOrange, opacity: 0.45)
    static let mainCardRadius: CGFloat = Theme.Radius.medium
    static let mainCardHorizontalPadding: CGFloat = Theme.Spacing.m
    /// 札の上下を行の高さより少し内側に（となりの行とくっつかないように）
    static let mainCardInset: CGFloat = 3
    /// 行の間を広げるときの重み：時刻の間（分）をこの範囲に収めて使う（15 分以下は同じ、2 時間以上は同じ）
    static let gapWeightMinutes: ClosedRange<Int> = 15...120
    /// 文字の大きさの設定に合わせた行の高さの倍率の範囲（Home は文字を xxxLarge までにする。RootTabView）
    static let typeScaleRange: ClosedRange<CGFloat> = 0.85...1.45
    /// 案内する予定が替わるときに行を上へ詰める動きの時間（秒）。「視差効果を減らす」・低電力モードでは動かさない（§88.8）
    static let rowAnimation: Double = 0.35
    /// 予定がないときの［予定を登録］の分としてあけておく高さ
    static let registerReserve: CGFloat = 64
    /// 予定詳細・「終わった予定」の吹き出しの高さの見込み（測る前）
    static let estimatedBubbleHeight: CGFloat = 230
    /// 「終わった予定」の吹き出しで、これより多いと一覧を吹き出しの中でスクロールさせる（Home そのものはスクロールしない）
    static let finishedListMaxRows = 5
    static let finishedListHeight: CGFloat = 190

    /// 密度ごとの行の高さ（画面見本：ふだん 44pt・予定が多いとき 34pt・主状態の予定の札 56pt。仮）
    static func rows(_ density: HomeDensity) -> HomeRowMetrics {
        switch density {
        case .spacious:
            HomeRowMetrics(eventRow: 52, mainRow: 66, departureRow: 40, separatorRow: 30, messageRow: 44, moreRow: 34, maxExtraGap: 28)
        case .regular:
            HomeRowMetrics(eventRow: 44, mainRow: 58, departureRow: 34, separatorRow: 28, messageRow: 40, moreRow: 32, maxExtraGap: 16)
        case .compact:
            HomeRowMetrics(eventRow: 36, mainRow: 52, departureRow: 28, separatorRow: 26, messageRow: 36, moreRow: 30, maxExtraGap: 8)
        case .tight:
            HomeRowMetrics(eventRow: 30, mainRow: 46, departureRow: 24, separatorRow: 22, messageRow: 32, moreRow: 26, maxExtraGap: 0)
        }
    }

    /// 密度ごとの文字（少ない日は大きめ、詰めるほど小さく。どれも文字の大きさの設定に合わせて大きくなる文字の種類）
    static func fonts(_ density: HomeDensity) -> HomeRowFonts {
        switch density {
        case .spacious:
            HomeRowFonts(time: .subheadline.monospacedDigit(), title: .body, mainTitle: .headline, mainDetail: .subheadline,
                         departure: .subheadline, detail: .footnote)
        case .regular:
            HomeRowFonts(time: .subheadline.monospacedDigit(), title: .subheadline, mainTitle: .headline, mainDetail: .footnote,
                         departure: .footnote, detail: .caption)
        case .compact:
            HomeRowFonts(time: .footnote.monospacedDigit(), title: .subheadline, mainTitle: .subheadline.weight(.semibold),
                         mainDetail: .footnote, departure: .footnote, detail: .caption)
        case .tight:
            HomeRowFonts(time: .footnote.monospacedDigit(), title: .footnote, mainTitle: .footnote.weight(.semibold),
                         mainDetail: .caption, departure: .caption, detail: .caption2)
        }
    }
}

/// タイムラインの 1 行の高さ（pt。文字の大きさの設定に合わせて倍率をかける）
struct HomeRowMetrics: Equatable {
    var eventRow: CGFloat
    /// 主状態の予定の札（予定名と場所の 2 行）
    var mainRow: CGFloat
    var departureRow: CGFloat
    var separatorRow: CGFloat
    var messageRow: CGFloat
    /// 「ほか○件」
    var moreRow: CGFloat
    /// 高さが余ったときに、行のあとに足す間の上限
    var maxExtraGap: CGFloat
}

/// タイムラインの文字
struct HomeRowFonts {
    var time: Font
    var title: Font
    var mainTitle: Font
    var mainDetail: Font
    var departure: Font
    /// 進行中の予定の終わりの時刻・日付の区切りなどの小さな文字
    var detail: Font
}
