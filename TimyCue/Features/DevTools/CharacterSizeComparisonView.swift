#if TIMYCUE_DEV_TOOLS
import Observation
import SwiftUI

// H1 の比べる画面（spec §88.10・2026-10-15 決定 Q79・Q80、2026-10-16 の変更）。検証用のビルド（コンパイルの条件 TIMYCUE_DEV_TOOLS を付けたもの）だけに入り、
// App Store の公開版には入らない。H1 で大きさが決まったら、この画面・設定の入口・条件の印を取り除く（キャラクターの部品は H2 以降で使うので残す）

/// 比べる画面で切り替えるもの
@Observable
final class CharacterComparisonStore {
    /// 比べる全身の高さ（pt。小物を除いた立った姿。座った姿も同じ縮尺）。約 40pt は Home レイアウト比較画像 A からの推定で、正式な寸法ではない
    static let heights: [CGFloat] = [16, 24, 36, 40]
    /// 比べる時計の外径（画面の幅に対する割合。2026-10-16 の実機確認：74％は大きすぎた。45％が第一の候補）
    static let clockWidths: [CGFloat] = [0.40, 0.45, 0.50]

    typealias Posture = CharacterPosture

    var height: CGFloat
    var posture: Posture
    var showsClock: Bool
    var clockWidth: CGFloat

    /// 初めは第一の候補（2026-10-16 の 2 回目の実機確認：人型 36pt・時計 45％）
    init(height: CGFloat = 36, posture: Posture = .standing, showsClock: Bool = true, clockWidth: CGFloat = 0.45) {
        self.height = height
        self.posture = posture
        self.showsClock = showsClock
        self.clockWidth = clockWidth
    }

    static func label(for height: CGFloat) -> String {
        height == 40 ? "約40pt" : "\(Int(height))pt"
    }

    static func clockLabel(for width: CGFloat) -> String {
        "\(Int((width * 100).rounded()))％"
    }

    /// Codemagic の画面写真用：起動引数
    /// `-TimyCueCharacterHeight 40 -TimyCueCharacterPosture sitting -TimyCueCharacterClock NO -TimyCueClockWidth 45`
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> CharacterComparisonStore {
        let store = CharacterComparisonStore()
        let height = CGFloat(defaults.double(forKey: "TimyCueCharacterHeight"))
        if heights.contains(height) { store.height = height }
        if let raw = defaults.string(forKey: "TimyCueCharacterPosture"), let posture = Posture(rawValue: raw) {
            store.posture = posture
        }
        if defaults.object(forKey: "TimyCueCharacterClock") != nil {
            store.showsClock = defaults.bool(forKey: "TimyCueCharacterClock")
        }
        let percent = CGFloat(defaults.double(forKey: "TimyCueClockWidth"))
        if let width = clockWidths.first(where: { abs($0 * 100 - percent) < 0.5 }) {
            store.clockWidth = width
        }
        return store
    }
}

/// 比べる画面に出す見本。見本の予定（SampleEvents）から作るだけで、カレンダー・通知・出発時刻の計算には渡さない。
/// 時刻は今日の 8:52 に決めて、最初の場所ありの予定の出発（見本では開始の 15 分前）まで 23 分の時計を出す
struct CharacterComparisonSample {
    enum Row: Identifiable {
        /// 出発の点（見本の時刻と移動手段）
        case departure(id: UUID, minute: MinuteOfDay, transport: String)
        case event(CalendarEvent, color: EventColor, emphasized: Bool)

        var id: String {
            switch self {
            case .departure(let id, _, _): "departure-\(id)"
            case .event(let event, _, _): "event-\(event.id)"
            }
        }
    }

    /// 今日の時間指定の予定 1 件と、場所ありならその出発の点
    struct Entry {
        let event: CalendarEvent
        let color: EventColor
        let departure: (minute: MinuteOfDay, transport: String)?
    }

    static let nowMinute: MinuteOfDay = 8 * 60 + 52
    static let sampleTravelMinutes = 15

    let dateTitle: String
    let nowText: String
    let allDayTitles: [String]
    /// 時刻の順
    let entries: [Entry]
    /// 主状態の予定（いちばん強調する 1 件）
    let mainEventID: UUID?
    /// 時計に描くもの（いま → 主状態の予定の出発）
    let face: HomeClockMath.Face?

    static func make(today: CalendarDay = CalendarDay(Date()), calendar: Calendar = .timyCue) -> CharacterComparisonSample {
        let sample = SampleEvents.make(around: today)
        let todays = sample.events.filter { $0.day == today }
        let timed = todays.filter { !$0.isAllDay }.sorted { $0.startMinute < $1.startMinute }
        let entries = timed.map { event -> Entry in
            let info = sample.metadata[event.id] ?? TimyCueEventMetadata()
            let hasPlace = !(event.locationName ?? "").isEmpty
            return Entry(event: event, color: info.color,
                         departure: hasPlace ? (minute: event.startMinute - sampleTravelMinutes, transport: info.transport.displayName) : nil)
        }
        let main = entries.first { $0.event.startMinute > nowMinute }
        let now = today.date(atMinute: nowMinute, calendar: calendar)
        let face = main?.departure.flatMap {
            HomeClockMath.face(now: now, target: today.date(atMinute: $0.minute, calendar: calendar), calendar: calendar)
        }
        return CharacterComparisonSample(
            dateTitle: "\(today.month)月\(today.day)日（\(today.weekdaySymbol(calendar: calendar))）",
            nowText: TimeText.hourMinute(nowMinute),
            allDayTitles: todays.filter(\.isAllDay).map(\.displayTitle),
            entries: entries,
            mainEventID: main?.event.id,
            face: face)
    }

    /// 予定を limit 件まで出すときの並び（spec §88.2・2026-10-16 Q84）。主状態の予定とその出発の点はいつも出し、
    /// ほかは時刻の順に足す。出さなかった予定の数も返す（「ほか○件」。出発の点は別に数えない）
    func timeline(showingEvents limit: Int) -> (rows: [Row], hiddenEvents: Int) {
        var shown = Set<UUID>()
        if let mainEventID { shown.insert(mainEventID) }
        for entry in entries where shown.count < max(1, limit) {
            shown.insert(entry.event.id)
        }
        var rows: [Row] = []
        for entry in entries where shown.contains(entry.event.id) {
            if let departure = entry.departure {
                rows.append(.departure(id: entry.event.id, minute: departure.minute, transport: departure.transport))
            }
            rows.append(.event(entry.event, color: entry.color, emphasized: entry.event.id == mainEventID))
        }
        return (rows, entries.count - shown.count)
    }
}

extension CharacterPosture {
    var title: String {
        switch self {
        case .standing: "立つ"
        case .sitting: "座る"
        }
    }

    /// 現行案の姿勢
    var pose: CharacterPose { CharacterDesign.current.pose(self) }
}

/// 比べる画面の Home に近い配置（日付・演出帯・いま・縦のタイムライン・見本の予定）。
/// Home の新しい決まりに合わせて、画面は縦にスクロールしない（入りきらない予定は「ほか○件」。§88.2・Q84）。今の Home の画面とは別
struct DevHomePreview: View {
    let figure: CharacterFigure
    /// 時計の外径（画面の幅に対する割合）。nil なら時計なし
    let clockWidth: CGFloat?
    let sample: CharacterComparisonSample

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                stage(screenWidth: proxy.size.width)
                nowRow
                timeline
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .background(Theme.Colors.homeBackground.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(sample.dateTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            // 終日の予定は時間軸に混ぜず、日付の下に控えめに（§88.2）
            if !sample.allDayTitles.isEmpty {
                Text("終日　\(sample.allDayTitles.joined(separator: "・"))")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    /// 上の帯（2026-10-16 の H1 の配置）：左上に今日の日付、その下に小さな人型。時計ありなら右に時計（画面の幅の 45％・右寄せ。
    /// 中の文字・針は大きさに合わせて縮める：Q85）。外周の「いま」「出発」の文字が画面の外へ出ないよう、右に余白をとる
    @ViewBuilder
    private func stage(screenWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                header
                figure
            }
            Spacer(minLength: 0)
            if let clockWidth, let face = sample.face {
                let diameter = screenWidth * clockWidth
                VStack(spacing: Theme.Spacing.xs) {
                    HomeClockView(face: face, targetWord: "出発", scalesWithSize: true)
                        .frame(width: diameter, height: diameter)
                        .padding(.vertical, HomeMetrics.clockLabelRoom)
                    // 時計の下の出発予定の時刻は、文字の大きさを変えない（Q85）
                    Text("\(HomeClockMath.flowText(now: face.now, target: face.target)) 出発予定")
                        .font(HomeMetrics.flowFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize()
                }
                .padding(.trailing, DevStageLayout.clockTrailingInset)
            }
        }
    }

    private var nowRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: Layout.nowDot, height: Layout.nowDot)
                .frame(width: Layout.railWidth)
            Text("いま")
            Text(sample.nowText).monospacedDigit()
        }
        .font(.headline)
        .foregroundStyle(Theme.Colors.actionText)
    }

    /// 左の縦のタイムライン（§88.2・Q81・Q84）：入るだけの予定を出し、入らない分は「ほか○件」。
    /// 多い件数から順に試して、画面に収まる並びを使う（中でスクロールさせない）
    private var timeline: some View {
        ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: sample.entries.count, through: 1, by: -1)), id: \.self) { limit in
                timelineRows(sample.timeline(showingEvents: limit))
            }
        }
    }

    private func timelineRows(_ timeline: (rows: [CharacterComparisonSample.Row], hiddenEvents: Int)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(timeline.rows) { row in
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    marker(for: row)
                        .frame(width: Layout.railWidth, height: Layout.markerRowHeight)
                    content(for: row)
                }
                .padding(.vertical, Layout.rowSpacing / 2)
            }
            // 入りきらない予定（Home では押すとその日のカレンダーを開く。比べる画面では表示だけ）
            if timeline.hiddenEvents > 0 {
                HStack(spacing: Theme.Spacing.s) {
                    Color.clear.frame(width: Layout.railWidth, height: 1)
                    Text("ほか\(timeline.hiddenEvents)件")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.vertical, Layout.rowSpacing / 2)
            }
        }
        .background(alignment: .leading) {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: Layout.railLine)
                .frame(width: Layout.railWidth)
        }
    }

    @ViewBuilder
    private func marker(for row: CharacterComparisonSample.Row) -> some View {
        switch row {
        case .departure:
            Circle()
                .strokeBorder(Theme.Colors.textSecondary, lineWidth: 1.5)
                .background(Circle().fill(Theme.Colors.homeBackground))
                .frame(width: Layout.departureDot, height: Layout.departureDot)
        case .event(_, let color, _):
            Circle()
                .fill(EventPalette.color(for: color))
                .overlay { Circle().strokeBorder(Theme.Colors.separator, lineWidth: 1) }
                .frame(width: Layout.eventDot, height: Layout.eventDot)
        }
    }

    /// 主状態の予定は 2 行（予定名と場所）で強調し、ほかの予定と出発の点は 1 行（Q84）
    @ViewBuilder
    private func content(for row: CharacterComparisonSample.Row) -> some View {
        switch row {
        case .departure(_, let minute, let transport):
            HStack(spacing: Theme.Spacing.s) {
                Text(TimeText.hourMinute(minute)).monospacedDigit()
                Text("出発・\(transport)")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
        case .event(let event, _, let emphasized):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(TimeText.hourMinute(event.startMinute)).monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.displayTitle)
                        .fontWeight(emphasized ? .semibold : .regular)
                        .lineLimit(1)
                    if emphasized, let place = event.locationName, !place.isEmpty {
                        Text(place)
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.vertical, emphasized ? Theme.Spacing.s : 0)
            .padding(.horizontal, emphasized ? Theme.Spacing.m : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if emphasized {
                    RoundedRectangle(cornerRadius: Theme.Radius.medium).fill(Theme.Colors.expandedRow)
                }
            }
        }
    }

    /// この画面だけの寸法（開発用なので、ここに置く）
    private enum Layout {
        static let railWidth: CGFloat = 20
        static let railLine: CGFloat = 2
        static let nowDot: CGFloat = 14
        static let eventDot: CGFloat = 10
        static let departureDot: CGFloat = 9
        static let markerRowHeight: CGFloat = 20
        static let rowSpacing: CGFloat = 10
    }
}

/// 比べる画面の上の帯の配置の計算（2026-10-16 の H1 の配置。テストで、時計と人型が重ならないことを確かめる）
enum DevStageLayout {
    /// 時計の右の余白。画面の左右の余白（16pt）と合わせて、外周の「いま」「出発」の文字が画面の外へ出ない幅にする
    static let clockTrailingInset: CGFloat = 14
    /// 時計の外周から、「いま」「出発」の文字の外側の端までの長さ（文字の中心までの間隔＋文字の幅の半分）
    static let labelReach: CGFloat = HomeMetrics.markerLabelGap + 14

    /// 時計の外周の文字まで含めた左端（画面の左からの位置）
    static func clockLeftEdge(screenWidth: CGFloat, clockWidth: CGFloat) -> CGFloat {
        screenWidth - Theme.Spacing.l - clockTrailingInset - screenWidth * clockWidth - labelReach
    }

    /// 人型（左上、日付の下）の右端
    static func figureRightEdge(figureWidth: CGFloat) -> CGFloat {
        Theme.Spacing.l + figureWidth
    }
}

/// 比べる画面の下の切り替えの見た目
private struct DevControlsPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            content
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }
}

/// 設定 ＞ 開発用：キャラクターの大きさ。キャラクターの高さ・姿勢・時計のあり／なし・時計の大きさを切り替えて、その場で比べる
struct CharacterSizeComparisonView: View {
    @State private var store = CharacterComparisonStore.fromLaunchArguments()
    private let sample = CharacterComparisonSample.make()

    var body: some View {
        DevHomePreview(figure: CharacterFigure(height: store.height, design: .simple2, posture: store.posture),
                       clockWidth: store.showsClock ? store.clockWidth : nil,
                       sample: sample)
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle("キャラクターの大きさ")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var controls: some View {
        DevControlsPanel {
            Picker("高さ", selection: $store.height) {
                ForEach(CharacterComparisonStore.heights, id: \.self) { height in
                    Text(CharacterComparisonStore.label(for: height)).tag(height)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: Theme.Spacing.m) {
                Picker("姿勢", selection: $store.posture) {
                    ForEach(CharacterPosture.allCases, id: \.self) { posture in
                        Text(posture.title).tag(posture)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("時計", isOn: $store.showsClock)
                    .fixedSize()
                    .tint(Theme.Colors.accent)
            }
            Picker("時計の大きさ", selection: $store.clockWidth) {
                ForEach(CharacterComparisonStore.clockWidths, id: \.self) { width in
                    Text("時計 \(CharacterComparisonStore.clockLabel(for: width))").tag(width)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!store.showsClock)
        }
    }
}

// MARK: - キャラクターの案（2026-10-16 H1 の続き。比べるための案で、選んだ案だけを本番の形にする）

extension CharacterDesign {
    /// 2. シンプル寄り：目を小さな丸に、ほっぺなし、輪郭を細く、腕を胴とひと続きにして線を減らす（かわいさを少し抑える）
    static let simple = current.adjusted(
        CharacterPose.Adjustment(eyeScale: CGSize(width: 0.82, height: 0.64), armLengthScale: 0.85,
                                 armsMergeWithBody: true, bodyWidthScale: 0.95),
        style: CharacterStyle(outlineRatio: 0.035, cheekOpacity: 0))
    /// 3. かわいさ控えめ：丸みは残し、頭を少し小さく・手足を少し長く、目を小さめにして少し上へ、ほっぺをごく淡く（幼く見えすぎない）
    static let calm = current.adjusted(
        CharacterPose.Adjustment(headScale: 0.88, eyeScale: CGSize(width: 0.85, height: 0.85), faceLift: 0.04,
                                 cheekScale: 0.8, armLengthScale: 1.15, legLengthScale: 1.25),
        style: CharacterStyle(outlineRatio: 0.04, cheekOpacity: 0.35))
    /// 4. 中間案：現行案とシンプル寄りの間（目を少し小さく丸く、ほっぺを淡く、輪郭を少し細く、腕を少し短く）
    static let middle = current.adjusted(
        CharacterPose.Adjustment(eyeScale: CGSize(width: 0.9, height: 0.8), cheekScale: 0.85, armLengthScale: 0.92,
                                 bodyWidthScale: 0.97),
        style: CharacterStyle(outlineRatio: 0.04, cheekOpacity: 0.45))
}

/// 案の比べる画面で切り替えるもの。大きさは第一の候補に固定（人型 36pt・時計 45％。2026-10-16）
@Observable
final class CharacterDesignComparisonStore {
    /// 正式「2 シンプル」（原画を正本に描き直した形）と、H1 の旧試作（参考。正式のデザインではない）
    enum Candidate: String, CaseIterable {
        case simple2
        case current
        case simple
        case calm
        case middle

        var title: String {
            switch self {
            case .simple2: "正式"
            case .current: "旧現行"
            case .simple: "旧シンプル"
            case .calm: "旧控えめ"
            case .middle: "旧中間"
            }
        }

        var isOfficial: Bool { self == .simple2 }

        var design: CharacterDesign {
            switch self {
            case .simple2: .simple2
            case .current: .current
            case .simple: .simple
            case .calm: .calm
            case .middle: .middle
            }
        }
    }

    static let height: CGFloat = 36
    static let clockWidth: CGFloat = 0.45

    var candidate: Candidate = .simple2
    var posture: CharacterPosture = .standing
    var showsClock = true

    /// Codemagic の画面写真用：起動引数 `-TimyCueCharacterDesign simple -TimyCueCharacterPosture sitting -TimyCueCharacterClock NO`
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> CharacterDesignComparisonStore {
        let store = CharacterDesignComparisonStore()
        if let raw = defaults.string(forKey: "TimyCueCharacterDesign"), let candidate = Candidate(rawValue: raw) {
            store.candidate = candidate
        }
        if let raw = defaults.string(forKey: "TimyCueCharacterPosture"), let posture = CharacterPosture(rawValue: raw) {
            store.posture = posture
        }
        if defaults.object(forKey: "TimyCueCharacterClock") != nil {
            store.showsClock = defaults.bool(forKey: "TimyCueCharacterClock")
        }
        return store
    }
}

/// 設定 ＞ 開発用：キャラクターの案。案（現行・シンプル寄り・かわいさ控えめ・中間）・姿勢・時計のあり／なしを切り替えて比べる。
/// 人型は 36pt、時計は 45％に固定（2026-10-16 の第一の候補）
struct CharacterDesignComparisonView: View {
    @State private var store = CharacterDesignComparisonStore.fromLaunchArguments()
    private let sample = CharacterComparisonSample.make()

    var body: some View {
        DevHomePreview(figure: CharacterFigure(height: CharacterDesignComparisonStore.height,
                                               design: store.candidate.design, posture: store.posture),
                       clockWidth: store.showsClock ? CharacterDesignComparisonStore.clockWidth : nil,
                       sample: sample)
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle(store.candidate.isOfficial ? "キャラクター（正式：2 シンプル）" : "キャラクター（旧試作）")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var controls: some View {
        DevControlsPanel {
            Picker("案", selection: $store.candidate) {
                ForEach(CharacterDesignComparisonStore.Candidate.allCases, id: \.self) { candidate in
                    Text(candidate.title).tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: Theme.Spacing.m) {
                Picker("姿勢", selection: $store.posture) {
                    ForEach(CharacterPosture.allCases, id: \.self) { posture in
                        Text(posture.title).tag(posture)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("時計", isOn: $store.showsClock)
                    .fixedSize()
                    .tint(Theme.Colors.accent)
            }
        }
    }
}
#endif
