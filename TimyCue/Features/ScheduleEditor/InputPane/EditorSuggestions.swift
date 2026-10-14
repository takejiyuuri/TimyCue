import Foundation

/// 予定名の候補（仕様 §47）。過去の同名・似た名前の予定 1 件ぶん
struct TitleSuggestion: Identifiable, Equatable {
    /// もとになった過去の予定
    let id: UUID
    let title: String
    let locationName: String?
    let metadata: TimyCueEventMetadata?
}

/// 場所の候補の種類（仕様 §48）。現在地・検索は移動時間の計算（第5段階）で足す
enum PlaceCandidateKind: Equatable {
    /// 同じ予定名の前回の場所
    case previous
    /// よく使う場所
    case frequent
    /// 最近使った場所
    case recent

    var label: String {
        switch self {
        case .previous: "前回"
        case .frequent: "よく使う"
        case .recent: "最近"
        }
    }
}

struct PlaceCandidate: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let kind: PlaceCandidateKind
}

/// 予定の重なりの警告（仕様 §58）。警告だけで、保存は止めない（Soft Constraint）
enum ScheduleWarning: Equatable {
    /// 実際の時間が重なっている
    case overlap
    /// 直前の予定の終了時刻が分からない
    case previousEndUnknown

    /// §58 の文言どおり
    var message: String {
        switch self {
        case .overlap: "予定が重複"
        case .previousEndUnknown: "前の予定の終了時刻未設定"
        }
    }
}

extension ScheduleEditorStore {
    static let maxTitleSuggestions = 3
    static let maxPlaceCandidatesPerKind = 3

    /// 編集中の予定を除いた、時刻のある過去の予定。新しい順
    private var historyNewestFirst: [CalendarEvent] {
        events
            .filter { $0.id != editingEvent?.id }
            .sorted { ($0.day, $0.startMinute) > ($1.day, $1.startMinute) }
    }

    // MARK: - 予定名の候補（§47）

    /// 入れかけの予定名に合う過去の予定を、最大 2〜3 件。同じ名前を先に、あとは新しい順。名前と場所が同じものは 1 つにまとめる
    func titleSuggestions() -> [TitleSuggestion] {
        let typed = content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return [] }
        let matches = historyNewestFirst.filter { !$0.title.isEmpty && $0.title.localizedCaseInsensitiveContains(typed) }
        let ordered = matches.filter { $0.title == typed } + matches.filter { $0.title != typed }
        var seen = Set<String>()
        var result: [TitleSuggestion] = []
        for event in ordered {
            let key = event.title + "\u{1F}" + (event.locationName ?? "")
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(TitleSuggestion(id: event.id, title: event.title, locationName: event.locationName,
                                          metadata: metadata(for: event.id)))
            if result.count == Self.maxTitleSuggestions { break }
        }
        return result
    }

    /// 候補の予定名を入れる。ほかの設定は勝手に入れない（§47）
    func useTitle(of suggestion: TitleSuggestion) {
        content.title = suggestion.title
    }

    /// 「この予定の設定も使う」を押したときに、入力中の値を置き換える前に確かめるか（2026-10-14 決定）。
    /// 場所・色・到着目標・移動手段のどれかを 3 分割画面を開いたときの値から変えていて、しかも候補の値と違うときだけ確かめる。
    /// 何も変えていなければ、確かめずにすぐ入れる
    func settingsReplacementNeedsConfirmation(for suggestion: TitleSuggestion) -> Bool {
        let initial = initialContent
        if content.locationName != initial.locationName && content.locationName != suggestion.locationName {
            return true
        }
        guard let info = suggestion.metadata else { return false }
        let current = content.metadata
        return (current.color != initial.metadata.color && current.color != info.color)
            || (current.arrivalTargetMinutes != initial.metadata.arrivalTargetMinutes
                && current.arrivalTargetMinutes != info.arrivalTargetMinutes)
            || (current.transport != initial.metadata.transport && current.transport != info.transport)
            || (info.transport == .car && current.route != initial.metadata.route && current.route != info.route)
    }

    /// 候補の予定の設定（場所・色・到着目標・移動手段の 4 つ）を使う。押したときだけ（§47・2026-10-14 決定）。
    /// 移動手段が「車」のときだけ、車のルートの条件も移動手段に付いてくるものとして一緒に引き継ぐ。車以外なら、ルートは今の値のまま。
    /// 通知と出発の余裕は写さず、今の値のまま（通知は予定ごとに意味が変わりやすく、余裕は設定の値を使う方が分かりやすいため）
    func useSettings(of suggestion: TitleSuggestion) {
        setLocationName(suggestion.locationName)
        guard let info = suggestion.metadata else { return }
        content.metadata.color = info.color
        content.metadata.arrivalTargetMinutes = info.arrivalTargetMinutes
        content.metadata.transport = info.transport
        if info.transport == .car {
            content.metadata.route = info.route
        }
    }

    // MARK: - 場所の候補（§48）

    /// 場所の候補：前回の場所・よく使う場所・最近使った場所（同じ場所は先の種類に 1 回だけ）
    func placeCandidates() -> [PlaceCandidate] {
        let history = historyNewestFirst.compactMap { event -> (String, CalendarEvent)? in
            guard let place = event.locationName, !place.isEmpty else { return nil }
            return (place, event)
        }
        var result: [PlaceCandidate] = []
        func add(_ name: String, _ kind: PlaceCandidateKind) {
            guard !result.contains(where: { $0.name == name }) else { return }
            result.append(PlaceCandidate(name: name, kind: kind))
        }

        let title = content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, let previous = history.first(where: { $0.1.title == title }) {
            add(previous.0, .previous)
        }
        let counts = Dictionary(history.map { ($0.0, 1) }, uniquingKeysWith: +)
        let frequent = counts.filter { $0.value >= 2 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(Self.maxPlaceCandidatesPerKind)
        frequent.forEach { add($0.key, .frequent) }
        var recentCount = 0
        for (place, _) in history where recentCount < Self.maxPlaceCandidatesPerKind {
            guard !result.contains(where: { $0.name == place }) else { continue }
            add(place, .recent)
            recentCount += 1
        }
        return result
    }

    /// 場所を選ぶ。過去の場所を選んでも、到着目標・移動手段は書き換えない（Q75）。
    /// 到着目標はユーザーが決める予定側の設定で、場所から入れない（全体既定値のまま。Q70）。
    /// 移動手段は、はっきり指定されていればそのまま、「自動」なら「自動」のまま（過去の実績は自動の判定の内部材料にだけ使う）
    func choosePlace(_ name: String?) {
        setLocationName(name)
    }

    /// 場所を入れる・消す。場所あり／なしが変わったら、通知のタイミングの意味を置き換える
    /// （出発○分前 ↔ 開始○分前、出発時刻 ↔ 予定開始。初めの値には戻さず、通知なしは通知なしのまま。2026-10-14 決定）
    func setLocationName(_ name: String?) {
        let hadPlace = content.hasPlace
        content.locationName = name
        if content.hasPlace != hadPlace {
            content.metadata.notifications = content.metadata.notifications.converted(hasPlace: content.hasPlace)
        }
    }

    // MARK: - 予定の重なり（§58）

    /// その日の、ほかの予定との重なりの警告。start を渡すと、動かしている途中の時刻で判断する（ブロックを動かしている間のリアルタイム判定）
    func warnings(on day: CalendarDay, start: MinuteOfDay? = nil) -> [ScheduleWarning] {
        guard let start = start ?? startMinutes[day] else { return [] }
        let end = durationMinutes(on: day).map { start + $0 }
        return Self.warnings(start: start, end: end, others: timedEvents(on: day))
    }

    /// 重なりの判断。終了時刻の分からない予定は、15 分の予定などとは見なさない（Q15）
    static func warnings(start: MinuteOfDay, end: MinuteOfDay?, others: [CalendarEvent]) -> [ScheduleWarning] {
        let timed = others.filter { !$0.isAllDay }
        let overlaps = timed.contains { other in
            guard let otherEnd = other.endMinute else {
                // 相手の終了が分からない：同じ時刻に始まるときだけ重なりと見る
                return other.startMinute == start
            }
            if let end {
                return start < otherEnd && other.startMinute < end
            }
            return other.startMinute <= start && start < otherEnd
        }
        if overlaps { return [.overlap] }
        let previous = timed.filter { $0.startMinute < start }.max { $0.startMinute < $1.startMinute }
        if let previous, previous.endMinute == nil {
            return [.previousEndUnknown]
        }
        return []
    }
}
