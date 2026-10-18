import Foundation

/// 新しい予定を Apple カレンダーへ保存するとき、その保存先が使えない理由（spec §89.4）
enum SaveTargetProblem: Error, Equatable {
    /// TimyCue で表示を OFF にしている
    case hidden(calendarTitle: String)
    /// 表示のみのカレンダー（祝日など。手で表示のみにした書き込めるカレンダーを含む）
    case displayOnly(calendarTitle: String)
    /// 予定を書き込めない（共有・購読など）
    case readOnly(calendarTitle: String)
    /// 保存先にしていたカレンダーが見つからない（削除されたなど）
    case notFound
    /// iPhone の「新規イベントのデフォルトカレンダー」が取れない
    case noSystemDefault
}

/// 保存先をどこで決めたか。予定ごとの指定 → 設定の既定 → iPhone の既定 の順に、最初に指定のある段だけを使う
enum SaveTargetSource: Equatable {
    /// その予定だけの指定（作成画面の「カレンダー」の行・コピー元・編集中の予定の所属）
    case event
    /// 設定 ＞ カレンダー連携 ＞ 新しい予定の保存先
    case settingsDefault
    /// iPhone の既定
    case systemDefault
}

/// 保存先を確かめた結果
enum SaveTargetResolution: Equatable {
    case usable(CalendarChoice, source: SaveTargetSource)
    case unavailable(SaveTargetProblem, source: SaveTargetSource)

    var problem: SaveTargetProblem? {
        if case .unavailable(let problem, _) = self { return problem }
        return nil
    }

    var source: SaveTargetSource {
        switch self {
        case .usable(_, let source), .unavailable(_, let source): source
        }
    }
}

/// Apple カレンダーへ保存するときの保存先の決まり（spec §89.2・§89.4。2026-10-17・2026-10-18 決定）。画面とは切り離して、ここだけで決める。
/// 使えるのは、今も見えていて、書き込めて、TimyCue で表示を ON にしていて、表示のみ（祝日など）でない Apple カレンダーだけ。
/// 使えない保存先へは保存しない。次の段（設定の既定・iPhone の既定）や別のカレンダーへも勝手に移らない（v1.2 の自動の切り替えは廃止）。
/// 決めるだけで、設定は書き換えない
struct SaveTargetRules: Equatable {
    /// 見えるカレンダー（書き込めないものも含む）
    var calendars: [CalendarChoice] = []
    /// 表示しないカレンダー・表示のみの手直し・設定の既定の保存先
    var preferences = CalendarPreferences()
    /// iPhone の「新規イベントのデフォルトカレンダー」
    var systemDefaultID: String?

    /// そのカレンダーへ保存できないなら、その理由。表示のみは、手で直した分を当てて判定する（Q55・Q114）
    func problem(with calendarID: String) -> SaveTargetProblem? {
        guard let calendar = calendars.first(where: { $0.id == calendarID }) else { return .notFound }
        if !calendar.isWritable { return .readOnly(calendarTitle: calendar.title) }
        if !preferences.isShown(calendar.id) { return .hidden(calendarTitle: calendar.title) }
        if preferences.isHolidayCalendar(calendar) { return .displayOnly(calendarTitle: calendar.title) }
        return nil
    }

    /// 保存先に選べるカレンダー（使えるものだけ。使えないものは候補の一覧に出さない）
    var candidates: [CalendarChoice] {
        calendars.filter { problem(with: $0.id) == nil }
    }

    /// 保存先を決める。予定ごとの指定 → 設定の既定 → iPhone の既定 の順に、最初に指定のある段だけを確かめ、
    /// その段が使えなければ、次の段へは落ちずに理由を返す
    func resolve(eventCalendarID: String?) -> SaveTargetResolution {
        if let id = eventCalendarID {
            return resolve(id, source: .event)
        }
        if let id = preferences.defaultCalendarID {
            return resolve(id, source: .settingsDefault)
        }
        guard let id = systemDefaultID else { return .unavailable(.noSystemDefault, source: .systemDefault) }
        return resolve(id, source: .systemDefault)
    }

    /// 書く前に、全部の予定の保存先を確かめる（予定ごとの指定の順に並べて返す）。
    /// 1 件でも使えなければ、その理由を投げる（何も書かないため。spec §89.4）
    func usableTargets(for eventCalendarIDs: [String?]) throws -> [CalendarChoice] {
        try eventCalendarIDs.map { id -> CalendarChoice in
            switch resolve(eventCalendarID: id) {
            case .usable(let calendar, _): return calendar
            case .unavailable(let problem, _): throw problem
            }
        }
    }

    private func resolve(_ id: String, source: SaveTargetSource) -> SaveTargetResolution {
        if let problem = problem(with: id) { return .unavailable(problem, source: source) }
        guard let calendar = calendars.first(where: { $0.id == id }) else { return .unavailable(.notFound, source: source) }
        return .usable(calendar, source: source)
    }

    // MARK: - 名前の出し方（spec §89.11・Q106・Q110）

    /// 「iPhoneの既定（Default）」。実際の名前が取れなければ「iPhoneの既定」
    var systemDefaultLabel: String {
        guard let id = systemDefaultID, let calendar = calendars.first(where: { $0.id == id }) else { return "iPhoneの既定" }
        return "iPhoneの既定（\(calendar.title)）"
    }

    /// 保存先の名前（「（使えません）」は付けない）。iPhone の既定は「iPhoneの既定（名前）」
    func name(for resolution: SaveTargetResolution) -> String {
        switch resolution {
        case .usable(let calendar, let source):
            return source == .systemDefault ? systemDefaultLabel : calendar.title
        case .unavailable(let problem, let source):
            if case .noSystemDefault = problem { return "iPhoneの既定" }
            if source == .systemDefault { return systemDefaultLabel }
            return Self.title(of: problem) ?? "保存先にしていたカレンダー"
        }
    }

    /// 行に出す保存先の名前。使えないときは「（使えません）」を付ける
    func label(for resolution: SaveTargetResolution) -> String {
        switch resolution {
        case .usable:
            return name(for: resolution)
        case .unavailable(let problem, _):
            if case .noSystemDefault = problem { return "iPhoneの既定（見つかりません）" }
            return "\(name(for: resolution))（使えません）"
        }
    }

    /// 使えない理由の短い言い方（設定の保存先の欄など）
    static func shortReason(_ problem: SaveTargetProblem) -> String {
        switch problem {
        case .hidden: "表示 OFF"
        case .displayOnly: "表示のみ"
        case .readOnly: "書き込めません"
        case .notFound: "見つかりません"
        case .noSystemDefault: "見つかりません"
        }
    }

    static func title(of problem: SaveTargetProblem) -> String? {
        switch problem {
        case .hidden(let title), .displayOnly(let title), .readOnly(let title): title
        case .notFound, .noSystemDefault: nil
        }
    }
}
