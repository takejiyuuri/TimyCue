#if TIMYCUE_DEV_TOOLS
import Observation
import SwiftUI

// H1 の比べる画面（spec §88.10・2026-10-15 決定 Q79・Q80）。検証用のビルド（コンパイルの条件 TIMYCUE_DEV_TOOLS を付けたもの）だけに入り、
// App Store の公開版には入らない。H1 で大きさが決まったら、この画面・設定の入口・条件の印を取り除く（キャラクターの部品は H2 以降で使うので残す）

/// 比べる画面で切り替えるもの
@Observable
final class CharacterComparisonStore {
    /// 比べる全身の高さ（pt。小物を除いた立った姿。座った姿も同じ縮尺）。約 40pt は Home レイアウト比較画像 A からの推定で、正式な寸法ではない
    static let heights: [CGFloat] = [16, 24, 36, 40]

    enum Posture: String, CaseIterable {
        case standing
        case sitting

        var title: String {
            switch self {
            case .standing: "立つ"
            case .sitting: "座る"
            }
        }

        var pose: CharacterPose {
            switch self {
            case .standing: .standing
            case .sitting: .sitting
            }
        }
    }

    var height: CGFloat
    var posture: Posture
    var showsClock: Bool

    init(height: CGFloat = 24, posture: Posture = .standing, showsClock: Bool = true) {
        self.height = height
        self.posture = posture
        self.showsClock = showsClock
    }

    static func label(for height: CGFloat) -> String {
        height == 40 ? "約40pt" : "\(Int(height))pt"
    }

    /// Codemagic の画面写真用：起動引数 `-TimyCueCharacterHeight 40 -TimyCueCharacterPosture sitting -TimyCueCharacterClock NO`
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

    static let nowMinute: MinuteOfDay = 8 * 60 + 52
    static let sampleTravelMinutes = 15

    let dateTitle: String
    let nowText: String
    let allDayTitles: [String]
    let rows: [Row]
    /// 時計に描くもの（いま → 最初の場所ありの予定の出発）
    let face: HomeClockMath.Face?

    static func make(today: CalendarDay = CalendarDay(Date()), calendar: Calendar = .timyCue) -> CharacterComparisonSample {
        let sample = SampleEvents.make(around: today)
        let todays = sample.events.filter { $0.day == today }
        let timed = todays.filter { !$0.isAllDay }.sorted { $0.startMinute < $1.startMinute }
        let emphasized = timed.first { $0.startMinute > nowMinute }
        var rows: [Row] = []
        for event in timed {
            let info = sample.metadata[event.id] ?? TimyCueEventMetadata()
            if let place = event.locationName, !place.isEmpty {
                rows.append(.departure(id: event.id, minute: event.startMinute - sampleTravelMinutes,
                                       transport: info.transport.displayName))
            }
            rows.append(.event(event, color: info.color, emphasized: event.id == emphasized?.id))
        }
        let firstDeparture = timed.first { ($0.locationName ?? "").isEmpty == false && $0.startMinute > nowMinute }
        let now = today.date(atMinute: nowMinute, calendar: calendar)
        let face = firstDeparture.flatMap {
            HomeClockMath.face(now: now, target: today.date(atMinute: $0.startMinute - sampleTravelMinutes, calendar: calendar),
                               calendar: calendar)
        }
        return CharacterComparisonSample(
            dateTitle: "\(today.month)月\(today.day)日（\(today.weekdaySymbol(calendar: calendar))）",
            nowText: TimeText.hourMinute(nowMinute),
            allDayTitles: todays.filter(\.isAllDay).map(\.displayTitle),
            rows: rows,
            face: face)
    }
}

/// 設定 ＞ 開発用：キャラクターの大きさ。Home に近い配置（日付・演出帯・いま・縦のタイムライン・見本の予定）で、
/// キャラクターの高さ・姿勢・時計のあり／なしを切り替えて、その場で比べる。今の Home の画面とは別の画面で、Home の動きは変えない
struct CharacterSizeComparisonView: View {
    @State private var store = CharacterComparisonStore.fromLaunchArguments()
    private let sample = CharacterComparisonSample.make()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                header
                stageBand
                nowRow
                timeline
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
        }
        .background(Theme.Colors.homeBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle("キャラクターの大きさ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Home に近い配置

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
        .padding(.top, Theme.Spacing.m)
    }

    /// 演出帯：時計ありなら今の時計（外径 74％）と、その左下にキャラクター。時計なしなら低い帯にキャラクターだけ（§88.3）
    @ViewBuilder
    private var stageBand: some View {
        let figure = CharacterFigure(height: store.height, pose: store.posture.pose)
        if store.showsClock, let face = sample.face {
            ZStack(alignment: .bottomLeading) {
                VStack(spacing: Theme.Spacing.s) {
                    HomeClockView(face: face, targetWord: "出発")
                        .containerRelativeFrame(.horizontal) { length, _ in length * HomeMetrics.clockWidthRatio }
                        .padding(.vertical, HomeMetrics.clockLabelRoom)
                    Text("\(HomeClockMath.flowText(now: face.now, target: face.target)) 出発予定")
                        .font(HomeMetrics.flowFont)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                figure
            }
        } else {
            figure
                .frame(maxWidth: .infinity, minHeight: Layout.bandHeightWithoutClock, alignment: .bottomLeading)
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

    /// 左の縦のタイムライン：出発の点と予定の開始を時刻の順に（§88.2・Q81）。次に行動が要る予定だけ強調する
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sample.rows) { row in
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    marker(for: row)
                        .frame(width: Layout.railWidth, height: Layout.markerRowHeight)
                    content(for: row)
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
        case .event(let event, _, let emphasized):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(TimeText.hourMinute(event.startMinute)).monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.displayTitle)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if let place = event.locationName, !place.isEmpty {
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

    // MARK: - 切り替え

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            Picker("高さ", selection: $store.height) {
                ForEach(CharacterComparisonStore.heights, id: \.self) { height in
                    Text(CharacterComparisonStore.label(for: height)).tag(height)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: Theme.Spacing.m) {
                Picker("姿勢", selection: $store.posture) {
                    ForEach(CharacterComparisonStore.Posture.allCases, id: \.self) { posture in
                        Text(posture.title).tag(posture)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("時計", isOn: $store.showsClock)
                    .fixedSize()
                    .tint(Theme.Colors.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }

    /// この画面だけの寸法（開発用なので、ここに置く）
    private enum Layout {
        static let bandHeightWithoutClock: CGFloat = 56
        static let railWidth: CGFloat = 20
        static let railLine: CGFloat = 2
        static let nowDot: CGFloat = 14
        static let eventDot: CGFloat = 10
        static let departureDot: CGFloat = 9
        static let markerRowHeight: CGFloat = 20
        static let rowSpacing: CGFloat = 14
    }
}
#endif
