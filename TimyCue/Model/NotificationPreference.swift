import Foundation

/// 通知のタイミング 1 つ（仕様 §17）
enum NotificationTiming: Hashable, Codable {
    /// 出発の○分前（60・30・10 分前、またはカスタム）
    case beforeDeparture(minutes: Int)
    /// 出発時
    case atDeparture
    /// 予定開始の○分前
    case beforeStart(minutes: Int)

    /// 選択肢に並べる決まったタイミング。これ以外はカスタムで足す
    static let presets: [NotificationTiming] = [
        .beforeDeparture(minutes: 60),
        .beforeDeparture(minutes: 30),
        .beforeDeparture(minutes: 10),
        .atDeparture,
    ]

    /// 右上の通知行に並べる短い表記（仕様 §17 の例「30分・10分・出発」）。
    /// 予定開始を基準にするものは、出発基準と取り違えないよう「予定開始15分前」と書く（Q7）
    var label: String {
        switch self {
        case .beforeDeparture(let minutes): "\(minutes)分"
        case .atDeparture: "出発"
        case .beforeStart(let minutes): "予定開始\(minutes)分前"
        }
    }

    /// 並べる順：出発の○分前（早い順）→ 出発 → 開始の○分前（早い順）
    fileprivate var sortKey: (Int, Int) {
        switch self {
        case .beforeDeparture(let minutes): (0, -minutes)
        case .atDeparture: (1, 0)
        case .beforeStart(let minutes): (2, -minutes)
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

    var isOff: Bool { timings.isEmpty }

    /// 右上の通知行に出す文字（例：30分・10分・出発。何も選んでいなければ「通知なし」）
    var summary: String {
        guard !timings.isEmpty else { return "通知なし" }
        return timings
            .sorted { $0.sortKey < $1.sortKey }
            .map(\.label)
            .joined(separator: "・")
    }
}
