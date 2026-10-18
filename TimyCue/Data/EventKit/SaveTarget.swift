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

/// 新しい予定の既定の保存先の種類（spec §89.2・§89.8・Q98・Q111）。設定のファイルに文字で書く。
/// 先の版が足した知らない文字は「保存の前に確かめる」として読む（ファイル全体が読めなくなり、空から始まらないように）
enum SaveTargetKind: String, Codable, Equatable {
    /// TimyCue のみ（この iPhone の中。Apple カレンダーへは書かない）
    case timyCueOnly
    /// Apple カレンダー（設定の既定のカレンダー → iPhone の既定）
    case appleCalendar
    /// まだ決まっていない。連携中に初めて保存する前に確かめる（Q111-4）
    case askBeforeSaving

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SaveTargetKind(rawValue: raw) ?? .askBeforeSaving
    }
}

/// 予定ごとの保存先の選び（作成画面の「カレンダー」の行・コピー元。spec §89.3）。nil は設定の既定
enum SaveChoice: Hashable {
    /// TimyCue のみ（この iPhone の中）
    case timyCueOnly
    /// その Apple カレンダー（calendarIdentifier）
    case calendar(String)
}

/// 設定で決める新しい予定の既定の保存先（設定画面・初めて保存する前の確かめ。spec §89.2・§89.4）
enum DefaultSaveTarget: Hashable {
    case timyCueOnly
    /// iPhone の既定
    case systemDefault
    case calendar(String)
}

/// 保存先を確かめた結果
enum SaveTargetResolution: Equatable {
    case usable(CalendarChoice, source: SaveTargetSource)
    case unavailable(SaveTargetProblem, source: SaveTargetSource)
    /// TimyCue のみ（この iPhone の中へ保存する。Apple カレンダーへは書かない。spec §89.2）
    case timyCueOnly(source: SaveTargetSource)
    /// まだ決まっていない（保存の前に確かめる。Q111-4）
    case notChosen

    var problem: SaveTargetProblem? {
        if case .unavailable(let problem, _) = self { return problem }
        return nil
    }

    var source: SaveTargetSource {
        switch self {
        case .usable(_, let source), .unavailable(_, let source), .timyCueOnly(let source): source
        case .notChosen: .settingsDefault
        }
    }

    var isTimyCueOnly: Bool {
        if case .timyCueOnly = self { return true }
        return false
    }
}

/// 保存先の決まり（spec §89.2・§89.4。2026-10-17・2026-10-18 決定）。画面とは切り離して、ここだけで決める。
/// Apple カレンダーで使えるのは、今も見えていて、書き込めて、TimyCue で表示を ON にしていて、表示のみ（祝日など）でないカレンダーだけ。
/// 使えない保存先へは保存しない。次の段（設定の既定・iPhone の既定）や別のカレンダーへも勝手に移らない（v1.2 の自動の切り替えは廃止）。
/// 「TimyCue のみ」と「まだ決まっていない」は Apple へは書かない（S2）。決めるだけで、設定は書き換えない
struct SaveTargetRules: Equatable {
    /// 見えるカレンダー（書き込めないものも含む）
    var calendars: [CalendarChoice] = []
    /// 表示しないカレンダー・表示のみの手直し・設定の既定の保存先とその種類
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

    /// 保存先に選べる Apple カレンダー（使えるものだけ。使えないものは候補の一覧に出さない）
    var candidates: [CalendarChoice] {
        calendars.filter { problem(with: $0.id) == nil }
    }

    /// 新しい予定の「カレンダー」の行の選択肢：「TimyCue のみ」と、使える Apple カレンダー（spec §89.2・§89.3・Q97）
    var newEventChoices: [SaveChoice] {
        [.timyCueOnly] + candidates.map { SaveChoice.calendar($0.id) }
    }

    /// 保存先を決める。予定ごとの選び → 設定の既定（種類）の順。
    /// 設定の既定が Apple なら、設定の既定のカレンダー → iPhone の既定 の順に、最初に指定のある段だけを確かめ、
    /// その段が使えなければ、次の段へは落ちずに理由を返す。種類のない設定（移行の前）は、前の版と同じ Apple の決まりで扱う
    func resolve(choice: SaveChoice?) -> SaveTargetResolution {
        switch choice {
        case .timyCueOnly?:
            return .timyCueOnly(source: .event)
        case .calendar(let id)?:
            return resolve(id, source: .event)
        case nil:
            break
        }
        switch preferences.saveTargetKind {
        case .timyCueOnly?: return .timyCueOnly(source: .settingsDefault)
        case .askBeforeSaving?: return .notChosen
        case .appleCalendar?, nil: return appleDefaultResolution
        }
    }

    /// 予定ごとの Apple カレンダーの指定（nil は設定の既定）で決める
    func resolve(eventCalendarID: String?) -> SaveTargetResolution {
        resolve(choice: eventCalendarID.map(SaveChoice.calendar))
    }

    /// 設定の既定の Apple の保存先（設定の既定のカレンダー → iPhone の既定。使えない段から次の段へは落ちない）
    private var appleDefaultResolution: SaveTargetResolution {
        if let id = preferences.defaultCalendarID { return resolve(id, source: .settingsDefault) }
        return systemDefaultResolution
    }

    /// iPhone の既定だけを確かめる（設定の既定は見ない）
    var systemDefaultResolution: SaveTargetResolution {
        guard let id = systemDefaultID else { return .unavailable(.noSystemDefault, source: .systemDefault) }
        return resolve(id, source: .systemDefault)
    }

    /// 「Apple Calendarに保存」の移す先（spec §89.5・Q100）。予定ごとの指定があればそれ。
    /// 設定の保存先が Apple ならそれ（設定の既定のカレンダー → iPhone の既定）、TimyCue のみ・まだ決まっていないなら iPhone の既定。
    /// 移す先は Apple カレンダーだけなので、「TimyCue のみ」「まだ決まっていない」は返さない
    func resolveMoveTarget(eventCalendarID: String?) -> SaveTargetResolution {
        if let id = eventCalendarID { return resolve(id, source: .event) }
        switch preferences.saveTargetKind {
        case .appleCalendar?, nil: return appleDefaultResolution
        case .timyCueOnly?, .askBeforeSaving?: return systemDefaultResolution
        }
    }

    /// 書く前に、全部の予定の保存先を確かめる（予定ごとの指定の順に並べて返す）。
    /// 1 件でも使えなければ、その理由を投げる（何も書かないため。spec §89.4）。
    /// 「TimyCue のみ」「まだ決まっていない」になる予定は、Apple へ書かずに止める（書く先の取り違えの守り。S2）
    func usableTargets(for eventCalendarIDs: [String?]) throws -> [CalendarChoice] {
        try eventCalendarIDs.map { id -> CalendarChoice in
            switch resolve(eventCalendarID: id) {
            case .usable(let calendar, _): return calendar
            case .unavailable(let problem, _): throw problem
            case .timyCueOnly, .notChosen: throw SaveRoutingError.notAnAppleSave
            }
        }
    }

    private func resolve(_ id: String, source: SaveTargetSource) -> SaveTargetResolution {
        if let problem = problem(with: id) { return .unavailable(problem, source: source) }
        guard let calendar = calendars.first(where: { $0.id == id }) else { return .unavailable(.notFound, source: source) }
        return .usable(calendar, source: source)
    }

    // MARK: - 名前の出し方（spec §89.2・§89.11・Q106・Q110。文言は決定の例文のほかは仮）

    /// 「TimyCue のみ」をこの iPhone の中の保存だとはっきり示す名前（Q113）
    static let timyCueOnlyLabel = "TimyCue のみ（このiPhone）"
    /// 行の幅が足りないときと、チップの短い名前
    static let timyCueOnlyShortLabel = "TimyCue のみ"
    /// 「TimyCue のみ」の説明（spec §89.2 の推奨の文。必ず消えるとは言い切らない）
    static let timyCueOnlyNote = "このiPhoneに保存します。Appleカレンダーやほかの端末とは同期しません。アプリを削除すると予定が失われる場合があります。"
    /// 保存先がまだ決まっていない
    static let notChosenLabel = "未選択"

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
        case .timyCueOnly:
            return Self.timyCueOnlyLabel
        case .notChosen:
            return Self.notChosenLabel
        }
    }

    /// 行に出す保存先の名前。使えないときは「（使えません）」を付ける
    func label(for resolution: SaveTargetResolution) -> String {
        switch resolution {
        case .usable, .timyCueOnly, .notChosen:
            return name(for: resolution)
        case .unavailable(let problem, _):
            if case .noSystemDefault = problem { return "iPhoneの既定（見つかりません）" }
            return "\(name(for: resolution))（使えません）"
        }
    }

    /// 選択肢（チップ）の名前：「TimyCue のみ」かカレンダー名
    func choiceLabel(_ choice: SaveChoice) -> String {
        switch choice {
        case .timyCueOnly:
            return Self.timyCueOnlyShortLabel
        case .calendar(let id):
            return calendars.first(where: { $0.id == id })?.title ?? "見つからないカレンダー"
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
