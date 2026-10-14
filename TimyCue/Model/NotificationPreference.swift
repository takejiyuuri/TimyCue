import Foundation

/// 通知のタイミング 1 つ（仕様 §17）
enum NotificationTiming: Hashable, Codable {
    /// 出発の○分前（60・30・10 分前）
    case beforeDeparture(minutes: Int)
    /// 出発時刻
    case atDeparture
    /// 予定開始の○分前。場所なしの予定の候補（開始60・30・10分前。2026-10-14 決定 C3）。
    /// 前の版でカスタムとして足したもの（追加仕様書 vNext §11.2 で廃止）もこれで読む
    case beforeStart(minutes: Int)
    /// 予定開始（追加仕様書 vNext §11.1）
    case atStart

    /// 場所ありの予定で、予定編集画面で複数オン・オフする決まった候補（追加仕様書 vNext §11.1）。ほかに「通知なし」。カスタムの分は作らない
    static let presets: [NotificationTiming] = [
        .beforeDeparture(minutes: 60),
        .beforeDeparture(minutes: 30),
        .beforeDeparture(minutes: 10),
        .atDeparture,
        .atStart,
    ]

    /// 場所なしの予定の候補。出発の候補は出さず、開始60分前・開始30分前・開始10分前・予定開始（ほかに「通知なし」。2026-10-14 決定 C3）
    static let noPlacePresets: [NotificationTiming] = [
        .beforeStart(minutes: 60),
        .beforeStart(minutes: 30),
        .beforeStart(minutes: 10),
        .atStart,
    ]

    static func presets(hasPlace: Bool) -> [NotificationTiming] {
        hasPlace ? presets : noPlacePresets
    }

    /// 場所を消した・足したときの置き換え（2026-10-14 決定）：出発○分前 ↔ 開始○分前、出発時刻 ↔ 予定開始
    func converted(hasPlace: Bool) -> NotificationTiming {
        switch (self, hasPlace) {
        case (.beforeDeparture(let minutes), false): .beforeStart(minutes: minutes)
        case (.atDeparture, false): .atStart
        case (.beforeStart(let minutes), true): .beforeDeparture(minutes: minutes)
        case (.atStart, true): .atDeparture
        default: self
        }
    }

    /// 右上の通知行に並べる短い表記（仕様 §17 の例「30分・10分・出発」）。
    /// 予定開始を基準にするものは、出発基準と取り違えないよう「開始15分前」と書く（Q7。言い方は 2026-10-14 決定 C3 の候補にそろえた）
    var label: String {
        switch self {
        case .beforeDeparture(let minutes): "\(minutes)分"
        case .atDeparture: "出発"
        case .beforeStart(let minutes): "開始\(minutes)分前"
        case .atStart: "予定開始"
        }
    }

    /// 通知の行を開いたときの候補の表記（追加仕様書 vNext §11.1：出発60分前・出発時刻・予定開始 など。場所なしは 開始60分前 など）
    var fullLabel: String {
        switch self {
        case .beforeDeparture(let minutes): "出発\(minutes)分前"
        case .atDeparture: "出発時刻"
        case .beforeStart(let minutes): "開始\(minutes)分前"
        case .atStart: "予定開始"
        }
    }

    /// 並べる順：出発の○分前（早い順）→ 出発 → 開始の○分前（早い順）→ 予定開始
    fileprivate var sortKey: (Int, Int) {
        switch self {
        case .beforeDeparture(let minutes): (0, -minutes)
        case .atDeparture: (1, 0)
        case .beforeStart(let minutes): (2, -minutes)
        case .atStart: (2, 0)
        }
    }
}

/// 予定ごとの通知の設定（仕様 §17）。複数選べる。空なら通知なし。
struct NotificationPreference: Equatable, Codable {
    var timings: Set<NotificationTiming>

    /// 新しい予定の初期値は当面「出発30分前・出発10分前・出発時」（Q6）。
    /// 設定画面に既定の通知ができたら、そのユーザー設定を初期値にする
    init(timings: Set<NotificationTiming> = [.beforeDeparture(minutes: 30), .beforeDeparture(minutes: 10), .atDeparture]) {
        self.timings = timings
    }

    static let off = NotificationPreference(timings: [])

    /// 場所なしの新しい予定の初期値：開始30分前・開始10分前・予定開始（場所ありの初期値と対応。2026-10-14 決定）
    static let noPlaceDefault = NotificationPreference().converted(hasPlace: false)

    /// 場所を消した・足したときに、選んだタイミングの意味を置き換える。初めの値には戻さない。通知なしは通知なしのまま（2026-10-14 決定）
    func converted(hasPlace: Bool) -> NotificationPreference {
        NotificationPreference(timings: Set(timings.map { $0.converted(hasPlace: hasPlace) }))
    }

    var isOff: Bool { timings.isEmpty }

    /// 右上の通知行に出す文字の候補。長い順に並べ、1 行に入るいちばん長いものを画面が選ぶ（2026-10-14。短い書き方は仮）。
    /// 例：開始30分前・開始10分前・予定開始 → 開始30分前・10分前・予定開始（続く「開始」を略す）→ 開始30分前ほか2件
    var summaryCandidates: [String] {
        let sorted = timings.sorted { $0.sortKey < $1.sortKey }
        guard let first = sorted.first else { return ["通知なし"] }
        var compact: [String] = []
        var previous: NotificationTiming?
        for timing in sorted {
            if case .beforeStart(let minutes) = timing, case .some(.beforeStart) = previous {
                compact.append("\(minutes)分前")
            } else {
                compact.append(timing.label)
            }
            previous = timing
        }
        var candidates = [summary, compact.joined(separator: "・")]
        if sorted.count > 1 { candidates.append("\(first.label)ほか\(sorted.count - 1)件") }
        return candidates.reduce(into: []) { result, text in
            if !result.contains(text) { result.append(text) }
        }
    }

    /// 右上の通知行に出す文字（例：30分・10分・出発。何も選んでいなければ「通知なし」）
    var summary: String {
        guard !timings.isEmpty else { return "通知なし" }
        return timings
            .sorted { $0.sortKey < $1.sortKey }
            .map(\.label)
            .joined(separator: "・")
    }
}
