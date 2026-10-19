import CoreGraphics
import Foundation

/// タイムラインの密度（spec §88.2：予定が少ない日は行の間を広く、多い日は画面の中に収まる範囲で詰める）。
/// 行の高さ・文字の大きさの値は DesignSystem の HomeLayoutMetrics
enum HomeDensity: Int, CaseIterable, Comparable {
    /// 予定 0〜2 件：行も文字も大きめ
    case spacious
    /// 予定 3〜5 件
    case regular
    /// 予定 6 件以上
    case compact
    /// 入りきらないとき（小さい iPhone・文字を大きくしたとき・予定が多いとき）の最後の手段
    case tight

    static func < (lhs: HomeDensity, rhs: HomeDensity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 予定の数から選べる、いちばん広い密度。予定の数だけで決めず、このあと画面の高さに収まるかで詰める（HomeTimelineLayout.plan）
    static func widest(forEventCount count: Int) -> HomeDensity {
        switch count {
        case ...2: .spacious
        case 3...5: .regular
        default: .compact
        }
    }
}

/// タイムラインの行の並べ方（spec §88.2・Q84）。画面に依らない計算だけを置く。
/// Home は縦にスクロールしない（中のタイムラインも）。使える高さ・予定の数・時刻の間隔から、密度・出す行・行の間を決め、
/// 入りきらない予定は「ほか○件」にまとめる（件数は出していない予定の数。出発の点は別に数えない）
enum HomeTimelineLayout {
    struct Row: Identifiable, Equatable {
        let item: HomeTimeline.Item
        let height: CGFloat
        /// この行のあとにあける間（時刻の間が長いところほど少し広く。§88.2「予定が少ない日は行の間を広く」）
        let spacingAfter: CGFloat
        var id: String { item.id }
    }

    struct Plan: Equatable {
        let density: HomeDensity
        let rows: [Row]
        /// 出していない予定の数（「ほか○件」。出発の点は数えない）
        let hiddenEventCount: Int
        /// 「ほか○件」の行の高さ
        let moreRowHeight: CGFloat

        var showsMore: Bool { hiddenEventCount > 0 }

        /// 並べた行の高さの合計（「ほか○件」を含む）
        var height: CGFloat {
            rows.reduce(0) { $0 + $1.height + $1.spacingAfter } + (showsMore ? moreRowHeight : 0)
        }

        var shownEventIDs: Set<UUID> {
            Set(rows.compactMap { $0.item.isEventRow ? $0.item.event?.id : nil })
        }
    }

    /// 1 行の高さ（scale は文字の大きさの設定に合わせた倍率）
    static func rowHeight(_ item: HomeTimeline.Item, density: HomeDensity, scale: CGFloat = 1) -> CGFloat {
        let metrics = HomeLayoutMetrics.rows(density)
        let base: CGFloat
        switch item.kind {
        case .departure: base = metrics.departureRow
        case .start, .inProgress: base = item.isMain ? metrics.mainRow : metrics.eventRow
        case .daySeparator: base = metrics.separatorRow
        case .message: base = metrics.messageRow
        }
        return base * scale
    }

    /// 使える高さ（availableHeight）に収まる並べ方を決める。
    /// 1. 予定の数から選べるいちばん広い密度から順に、全部が収まる密度を探す。
    /// 2. どの密度でも収まらなければ、いちばん詰めた密度で、主状態の予定とその出発の点をいちばん先に出し（Q84）、
    ///    ほかは時刻の順に入るだけ出して、残りを「ほか○件」にする。
    /// 3. 全部が収まって高さが余れば、行の間を少し広げる（時刻の間が長いところほど広く。広げすぎない上限つき）
    static func plan(items: [HomeTimeline.Item], availableHeight: CGFloat, scale: CGFloat = 1) -> Plan {
        let eventIDs = orderedEventIDs(items)
        let widest = HomeDensity.widest(forEventCount: eventIDs.count)
        for density in HomeDensity.allCases where density >= widest {
            let total = items.reduce(CGFloat(0)) { $0 + rowHeight($1, density: density, scale: scale) }
            if total <= availableHeight {
                let rows = spaced(items, density: density, scale: scale, spare: availableHeight - total)
                return Plan(density: density, rows: rows, hiddenEventCount: 0,
                            moreRowHeight: HomeLayoutMetrics.rows(density).moreRow * scale)
            }
        }
        // 入りきらない：いちばん詰めた密度で、主状態の予定とその出発の点を必ず出し、ほかは時刻の順に入るだけ
        let density = HomeDensity.tight
        let moreHeight = HomeLayoutMetrics.rows(density).moreRow * scale
        let mainID = items.first(where: { $0.isMain && $0.isEventRow })?.event?.id
        var shown = Set<UUID>()
        if let mainID { shown.insert(mainID) }
        for id in eventIDs where id != mainID {
            var trial = shown
            trial.insert(id)
            let height = filtered(items, showing: trial).reduce(CGFloat(0)) { $0 + rowHeight($1, density: density, scale: scale) }
            // 間を飛ばして後の予定を出すと時刻の流れが分かりにくいので、入らなかったところで止める（残りは「ほか○件」）
            guard height + moreHeight <= availableHeight else { break }
            shown = trial
        }
        let rows = filtered(items, showing: shown).map { Row(item: $0, height: rowHeight($0, density: density, scale: scale), spacingAfter: 0) }
        return Plan(density: density, rows: rows, hiddenEventCount: eventIDs.count - shown.count, moreRowHeight: moreHeight)
    }

    /// 予定（開始の点・進行中の行）の並び順の id
    static func orderedEventIDs(_ items: [HomeTimeline.Item]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for item in items where item.isEventRow {
            if let id = item.event?.id, seen.insert(id).inserted { result.append(id) }
        }
        return result
    }

    /// 出す予定だけの行。出発の点はその予定を出すときだけ。日付の区切りは、その日の行を 1 つでも出すときだけ。文はいつも出す
    static func filtered(_ items: [HomeTimeline.Item], showing shown: Set<UUID>) -> [HomeTimeline.Item] {
        var result: [HomeTimeline.Item] = []
        var pendingSeparator: HomeTimeline.Item?
        for item in items {
            switch item.kind {
            case .daySeparator:
                pendingSeparator = item
            case .message:
                result.append(item)
            case .departure, .start, .inProgress:
                guard let id = item.event?.id, shown.contains(id) else { continue }
                if let separator = pendingSeparator {
                    result.append(separator)
                    pendingSeparator = nil
                }
                result.append(item)
            }
        }
        return result
    }

    /// 高さが余ったときに、行のあとの間を広げる。時刻の間（分）を重みにして、いちばん長い間が上限まで広がる形にする
    /// （時刻に比例させない一覧のまま、時間の流れを少しだけ感じられるように。上限は密度ごと）
    static func spaced(_ items: [HomeTimeline.Item], density: HomeDensity, scale: CGFloat, spare: CGFloat) -> [Row] {
        let heights = items.map { rowHeight($0, density: density, scale: scale) }
        guard items.count > 1, spare > 0 else {
            return zip(items, heights).map { Row(item: $0.0, height: $0.1, spacingAfter: 0) }
        }
        let maxExtra = HomeLayoutMetrics.rows(density).maxExtraGap * scale
        let range = HomeLayoutMetrics.gapWeightMinutes
        let weights: [CGFloat] = (0..<(items.count - 1)).map { index in
            let minutes = Int(items[index + 1].date.timeIntervalSince(items[index].date) / 60)
            return CGFloat(min(max(minutes, range.lowerBound), range.upperBound)) / CGFloat(range.upperBound)
        }
        let wanted = weights.reduce(0) { $0 + maxExtra * $1 }
        let factor = wanted > 0 ? min(1, spare / wanted) : 0
        return items.indices.map { index in
            let extra = index < weights.count ? maxExtra * weights[index] * factor : 0
            return Row(item: items[index], height: heights[index], spacingAfter: extra)
        }
    }
}

/// タイムラインの縦の線（spec §88.2・Q81・Q83）。画面に依らない計算だけを置く。
/// 点どうしを細い線でつなぎ、同じ予定の出発の点と予定開始の点（過ぎた出発の点は「いま」をはさんで予定開始の点まで）を、
/// その予定の色の少し太い線で結んで関係を表す
struct HomeRailDot: Hashable {
    enum Role: Hashable {
        case now
        case pastDeparture
        case departure
        case start
    }

    let rowID: String
    let role: Role
    let eventID: UUID?
    let color: EventColor?
}

enum HomeRailGeometry {
    struct Segment: Identifiable, Equatable {
        let id: String
        let top: CGPoint
        let bottom: CGPoint
        let color: EventColor?
    }

    /// すべての点をつなぐ線（いちばん上の点からいちばん下の点まで）。点が 2 つより少なければ線なし
    static func base(_ dots: [HomeRailDot: CGRect]) -> Segment? {
        guard dots.count >= 2 else { return nil }
        let centers = dots.values.map { CGPoint(x: $0.midX, y: $0.midY) }
        let x = dots.first(where: { $0.key.role == .now }).map { $0.value.midX } ?? centers[0].x
        guard let top = centers.map(\.y).min(), let bottom = centers.map(\.y).max(), bottom > top else { return nil }
        return Segment(id: "rail", top: CGPoint(x: x, y: top), bottom: CGPoint(x: x, y: bottom), color: nil)
    }

    /// 同じ予定の出発の点（過ぎた出発の点を含む）と予定開始の点を結ぶ線
    static func pairs(_ dots: [HomeRailDot: CGRect]) -> [Segment] {
        var departures: [UUID: CGRect] = [:]
        var starts: [UUID: (rect: CGRect, color: EventColor?)] = [:]
        for (dot, rect) in dots {
            guard let id = dot.eventID else { continue }
            switch dot.role {
            case .departure, .pastDeparture: departures[id] = rect
            case .start: starts[id] = (rect, dot.color)
            case .now: break
            }
        }
        var segments: [Segment] = []
        for (id, departure) in departures {
            guard let start = starts[id] else { continue }
            let from = CGPoint(x: departure.midX, y: departure.midY)
            let to = CGPoint(x: start.rect.midX, y: start.rect.midY)
            segments.append(Segment(id: "pair-\(id.uuidString)", top: from.y <= to.y ? from : to,
                                    bottom: from.y <= to.y ? to : from, color: start.color))
        }
        return segments.sorted { $0.top.y < $1.top.y }
    }
}

/// 演出帯（日付の下・時計・人型）の横の配置の計算（spec §88.3。H1 の比べる画面 DevStageLayout と同じ考え方）。
/// テストで、時計と人型が重ならないこと・外周の文字と甲羅が画面の外へ出ないことを確かめる
enum HomeStageLayout {
    /// 時計の外径（画面の幅の 40％）
    static func clockDiameter(screenWidth: CGFloat) -> CGFloat {
        (screenWidth * HomeLayoutMetrics.clockWidthRatio).rounded()
    }

    /// 時計の外周の「いま」「出発」の文字まで含めた左端（画面の左からの位置）
    static func clockLeftEdge(screenWidth: CGFloat) -> CGFloat {
        screenWidth - HomeLayoutMetrics.horizontalPadding - HomeLayoutMetrics.clockTrailingInset
            - clockDiameter(screenWidth: screenWidth) - HomeLayoutMetrics.clockLabelReach
    }

    /// 時計の外周の文字まで含めた右端
    static func clockRightEdge(screenWidth: CGFloat) -> CGFloat {
        screenWidth - HomeLayoutMetrics.horizontalPadding - HomeLayoutMetrics.clockTrailingInset + HomeLayoutMetrics.clockLabelReach
    }

    /// 人型を左へずらす量：本体の輪郭の左の端を画面の左の余白にそろえる（甲羅は左の余白へはみ出す。H1 と同じ）
    static func figureLeadingShift(_ layout: CharacterLayout) -> CGFloat {
        layout.bodyFrame.minX - layout.outlineWidth
    }

    /// 人型（甲羅・耳を含む）の左端と右端（画面の左からの位置）
    static func figureLeftEdge(_ layout: CharacterLayout) -> CGFloat {
        HomeLayoutMetrics.horizontalPadding - figureLeadingShift(layout)
    }

    static func figureRightEdge(_ layout: CharacterLayout) -> CGFloat {
        HomeLayoutMetrics.horizontalPadding + layout.size.width - figureLeadingShift(layout)
    }
}
