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
    /// 左上の日付（大きな見出しにはしない：§88.2）。2026-10-19 の見やすさの調整で約 2pt 大きくした（title3 20pt → title2 22pt）
    static let dateFont = Font.title2.weight(.semibold)
    /// 日付の行の並べ方の高さを決める文字（前の日付の大きさ。title3 20pt）。日付を大きくしても行の高さはこれのままにして、
    /// 下の時計・タイムラインの縦の位置と、タイムラインに使える高さ（出せる予定の数）を変えない。大きくした分は上下へ少しはみ出して描く
    static let dateLayoutFont = Font.title3.weight(.semibold)
    /// 日付の下の終日の予定（と、「終わった予定 ○件」の並べ方の高さ）
    static let headerLineFont = Font.footnote
    static let headerLineSpacing: CGFloat = 4
    /// 「終わった予定 ○件」の文字の大きさ（pt。標準の文字の大きさのとき。footnote と同じ割合で文字の大きさの設定に合わせる）。
    /// 2026-10-19 の見やすさの調整で 13pt から約 1pt 大きくし、色も操作の文字（#C8601A）より少し濃くした（仮）。
    /// 並べ方の高さは前の footnote のまま（時計がないときも、下のタイムラインに使える高さを変えない）
    static let finishedTextSize: CGFloat = 14
    static let finishedTextColor = Color(hex: 0xB45617)
    /// 右上の電池の残量（%）とマーク（画面見本：マーク 22×11pt＋「80%」。形は H2 の実機で決める：§88.2）
    static let batteryFont = Font.caption.weight(.semibold).monospacedDigit()
    static let batteryIconFont = Font.footnote
    /// これ以下（充電していないとき）は残りが少ない色にする（％。仮）
    static let batteryLowPercent = 20
    /// 電池を、日付の行の中（縦の中央）から上へずらす量（pt）。Home はステータスバーを出さないので、ふだんのステータスバーの
    /// 電池に近い高さへ寄せる（2026-10-19 の見やすさの調整。約 25〜30pt の目安の中ほど。仮）。日付・時計の位置は動かさない。
    /// Safe Area の上が小さい機種（SE など）では、画面の上の端から batteryMinimumScreenTop を残すよう、ずらす量を抑える（HomeBatteryPlacement）
    static let batteryLift: CGFloat = 28
    /// 電池の上の端と画面の上の端のあいだの最小（pt）
    static let batteryMinimumScreenTop: CGFloat = 6
    /// 標準の文字の大きさで「100%」とマークを並べた幅の見込み（pt。少し多めに見る）。電池の左の端が、画面の中央の
    /// Dynamic Island・ノッチより右にあることを確かめるのに使う
    static let batteryEstimatedWidth: CGFloat = 62
    /// 電池の文字はこの大きさの設定までにする（iOS のステータスバーと同じく、大きくしすぎてノッチ・Dynamic Island の方へ広がらないように。仮）
    static let batteryMaxTypeSize: DynamicTypeSize = .xLarge

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
    /// 時計の下の「8:30 → 9:15 出発予定」の文字の色。補助の説明のまま、前の textSecondary（#8A8178）より少し濃くして読みやすくする
    /// （2026-10-19 の見やすさの調整。背景 #FAF5EC で約 5:1。仮）。文字の大きさは変えない（15pt。Q85「時計の下の出発予定の時刻の文字の大きさは変えない」）
    static let flowTextColor = Color(hex: 0x706860)
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
    /// 「いま 8:52」と、過ぎた出発の点の行の高さ（文字の大きさの設定に合わせて広げる）。
    /// 2026-10-19 の見やすさの調整でも変えない（タイムラインに使える高さ・出せる予定の数を変えないため）
    static let nowRowHeight: CGFloat = 30
    static let pastDepartureRowHeight: CGFloat = 26
    /// 「いま 8:52」の文字（pt。標準の文字の大きさのとき。文字の大きさの設定に合わせた倍率をかける）。今の位置として少し目立つよう、
    /// 前の headline（17pt・semibold）から 18pt・bold にした（2026-10-19 の見やすさの調整。仮）。色は今のまま（操作の文字の色）
    static let nowFontSize: CGFloat = 18
    static let nowFontWeight: Font.Weight = .bold

    static func nowFont(scale: CGFloat) -> Font {
        Font.system(size: nowFontSize * scale, weight: nowFontWeight).monospacedDigit()
    }
    /// 過ぎた出発の点は控えめに（Q83）
    static let pastDepartureOpacity: Double = 0.7
    /// 時刻の欄の幅（「18:00」が入る幅）
    static let timeColumnWidth: CGFloat = 46
    /// 主状態の予定の札（予定名と場所の 2 行。画面見本の淡いオレンジ）
    static let mainCardFill = Color(hex: Theme.BrandPalette.lightOrange, opacity: 0.45)
    static let mainCardRadius: CGFloat = Theme.Radius.medium
    static let mainCardHorizontalPadding: CGFloat = Theme.Spacing.m
    /// 札の上下を行の高さより少し内側に（となりの行とくっつかないように）。2026-10-19 の見やすさの調整で 3 → 2pt：予定名を大きくした分、
    /// 行の高さ（出せる予定の数）を変えずに札の内側の上下の余白を前と同じくらいに保つ
    static let mainCardInset: CGFloat = 2
    /// 札の予定名と 2 行目（場所）のあいだ
    static let mainCardLineSpacing: CGFloat = 1
    /// 行の間を広げるときの重み：時刻の間（分）をこの範囲に収めて使う（30 分以下は同じ、2 時間以上は同じ）。
    /// 2026-10-19 の見やすさの調整で下を 15 → 30 分に：予定が少ない日に、出発の点と開始の点のような短い間も少し広がるように
    static let gapWeightMinutes: ClosedRange<Int> = 30...120
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

    /// 密度ごとの行の高さ（画面見本：ふだん 44pt・予定が多いとき 34pt・主状態の予定の札 56pt。仮）。
    /// 2026-10-19 の見やすさの調整：予定が多いときの段（ふつう・詰める・さらに詰める）の行の高さは変えない（予定名を大きくしても、
    /// 出せる予定の数と密度の選び方を前と同じにする）。広め（予定 0〜2 件）だけ札を 66 → 70pt に。
    /// 予定が少ない日は、余った高さで行の間を広げる上限を上げた（広め 28 → 40pt、ふつう 16 → 24pt。詰める段は前のまま）
    static func rows(_ density: HomeDensity) -> HomeRowMetrics {
        switch density {
        case .spacious:
            HomeRowMetrics(eventRow: 52, mainRow: 70, departureRow: 40, separatorRow: 30, messageRow: 44, moreRow: 34, maxExtraGap: 40)
        case .regular:
            HomeRowMetrics(eventRow: 44, mainRow: 58, departureRow: 34, separatorRow: 28, messageRow: 40, moreRow: 32, maxExtraGap: 24)
        case .compact:
            HomeRowMetrics(eventRow: 36, mainRow: 52, departureRow: 28, separatorRow: 26, messageRow: 36, moreRow: 30, maxExtraGap: 8)
        case .tight:
            HomeRowMetrics(eventRow: 30, mainRow: 46, departureRow: 24, separatorRow: 22, messageRow: 32, moreRow: 26, maxExtraGap: 0)
        }
    }

    /// 密度ごとの予定名の大きさ（pt。標準の文字の大きさのとき。文字の大きさの設定に合わせた倍率をかける）。
    /// 2026-10-19 の見やすさの調整：予定名を主役にする。主状態の予定名（札）は約 2pt、ほかの予定名は約 1〜2pt 大きくした
    /// （前は ほかの予定名 17・15・15・13pt、主状態の予定名 17・17・15・13pt の太字。どれも text style）。
    /// 時刻・場所名・出発の点・小さな文字は前の大きさのまま（fonts）
    static func titleSizes(_ density: HomeDensity) -> HomeTitleSizes {
        switch density {
        case .spacious: HomeTitleSizes(title: 18, mainTitle: 19)
        case .regular: HomeTitleSizes(title: 17, mainTitle: 19)
        case .compact: HomeTitleSizes(title: 16, mainTitle: 17)
        case .tight: HomeTitleSizes(title: 14, mainTitle: 15)
        }
    }

    /// 主状態の予定名の太さ（前の headline と同じ）
    static let mainTitleWeight: Font.Weight = .semibold

    /// 密度ごとの文字（少ない日は大きめ、詰めるほど小さく。どれも文字の大きさの設定に合わせて大きくなる）。
    /// 予定名は titleSizes に、文字の大きさの設定に合わせた倍率（scale。行の高さと同じもの）をかける。ほかは前のまま text style
    static func fonts(_ density: HomeDensity, scale: CGFloat = 1) -> HomeRowFonts {
        let sizes = titleSizes(density)
        let title = Font.system(size: sizes.title * scale)
        let mainTitle = Font.system(size: sizes.mainTitle * scale, weight: mainTitleWeight)
        switch density {
        case .spacious:
            return HomeRowFonts(time: .subheadline.monospacedDigit(), title: title, mainTitle: mainTitle, mainDetail: .subheadline,
                                departure: .subheadline, detail: .footnote)
        case .regular:
            return HomeRowFonts(time: .subheadline.monospacedDigit(), title: title, mainTitle: mainTitle, mainDetail: .footnote,
                                departure: .footnote, detail: .caption)
        case .compact:
            return HomeRowFonts(time: .footnote.monospacedDigit(), title: title, mainTitle: mainTitle,
                                mainDetail: .footnote, departure: .footnote, detail: .caption)
        case .tight:
            return HomeRowFonts(time: .footnote.monospacedDigit(), title: title, mainTitle: mainTitle,
                                mainDetail: .caption, departure: .caption, detail: .caption2)
        }
    }
}

/// 予定名の大きさ（pt。標準の文字の大きさのとき）
struct HomeTitleSizes: Equatable {
    /// ほかの予定名（1 行）
    var title: CGFloat
    /// 主状態の予定名（札の 1 行目）
    var mainTitle: CGFloat
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
