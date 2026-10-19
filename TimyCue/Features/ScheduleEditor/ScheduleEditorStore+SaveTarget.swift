import Foundation

/// 保存の前の選び直しの中身（spec §89.4・2026-10-17 決定 2・3・Q99。S3）。文言は仮
struct SaveTargetPrompt: Equatable {
    let problem: SaveTargetProblem
    let source: SaveTargetSource
    /// 使えない保存先の名前（「iPhoneの既定（Default）」など）
    let targetName: String
    /// 表示 OFF のときだけ、そのカレンダー（「表示をONにして保存」に使う）
    let hiddenCalendarID: String?
    let message: String

    /// ボタンに出すカレンダーの名前（「Default」など。取れなければ targetName）
    var calendarTitle: String {
        SaveTargetRules.title(of: problem) ?? targetName
    }
}

/// 作成・編集の画面の「カレンダー」の行と、保存の前の確かめ（spec §89.3・§89.4・Q97・Q99・Q105・Q110・Q111-4・Q113。S3）。
/// ここは読むだけ。選んだものを当てるのは chooseSaveTarget（この予定だけ。設定の既定は変えない。Q99）
extension ScheduleEditorStore {
    // MARK: - 「カレンダー」の行

    /// 行を開いたときの選択肢（チップ）。
    /// 新規・コピー（連携中）：「TimyCue のみ」と使える Apple カレンダー（Q97）。
    /// 書き込める Apple の予定の編集（連携中）：使える Apple カレンダー（今の所属を含む。Apple の予定を TimyCue のみへ移す操作は仕様にない）。
    /// ローカルの予定の編集（連携中）：「Apple Calendarに保存」の移す先（使える Apple カレンダー。移す先を確かめの画面で選ぶ形は S5）。
    /// 新規・コピーを開いているあいだに連携が外れ、出していた Apple の保存先に保存できない：「TimyCue のみ」だけ（2026-10-19 ユーザー指示 3）。
    /// それ以外（連携していない・書き込めない予定）は選べない（閲覧専用）
    var calendarRowChoices: [SaveChoice] {
        guard isConnectedToApple else { return canChooseInCalendarRow ? [SaveChoice.timyCueOnly] : [] }
        switch mode {
        case .new, .copy:
            return saveTargets.newEventChoices
        case .edit:
            guard !areAppleFieldsLocked, editingEvent != nil else { return [] }
            return saveTargetCandidates.map { SaveChoice.calendar($0.id) }
        }
    }

    /// 行で選べるか（選べなければ鍵の印を付けて、開かない＝閲覧専用。Q113）。連携していないときは、新規・コピーを開いているあいだに
    /// 連携が外れて、出していた Apple の保存先に保存できないときだけ（TimyCue のみを選べる。2026-10-19 ユーザー指示 3）
    var canChooseInCalendarRow: Bool {
        guard isConnectedToApple else { return mode.allowsMultipleDays && lostAppleTargetName != nil }
        switch mode {
        case .new, .copy:
            return true
        case .edit:
            guard !areAppleFieldsLocked, let event = editingEvent else { return false }
            if event.source == .timyCue { return !saveTargetCandidates.isEmpty }
            // Apple の予定は、今の所属のほかに使える候補があるときだけ
            return saveTargetCandidates.contains { $0.id != event.calendarID }
        }
    }

    /// 行が「Apple Calendarに保存」の移す先を選ぶものか（連携中にローカルの予定を編集しているとき）
    var calendarRowIsMoveTarget: Bool {
        canMoveToAppleCalendar
    }

    /// 選ばれているチップ。使えない保存先・まだ決まっていないときは、どれも選ばれていないことにする
    var selectedSaveChoice: SaveChoice? {
        switch mode {
        case .new, .copy:
            switch pendingSaveTarget {
            case .timyCueOnly?: return .timyCueOnly
            case .usable(let calendar, _)?: return .calendar(calendar.id)
            default: return nil
            }
        case .edit:
            return selectedSaveTargetID.map(SaveChoice.calendar)
        }
    }

    /// チップの名前（「TimyCue のみ」かカレンダー名）
    func choiceLabel(_ choice: SaveChoice) -> String {
        saveTargets.choiceLabel(choice)
    }

    /// 保存の前の選び直しのボタンの名前（「TimyCue のみ（このiPhone）に保存」「「仕事」に保存」）
    func promptButtonTitle(_ choice: SaveChoice) -> String {
        switch choice {
        case .timyCueOnly: "\(SaveTargetRules.timyCueOnlyLabel)に保存"
        case .calendar: "「\(saveTargets.choiceLabel(choice))」に保存"
        }
    }

    /// 行を開いたときの、チップの下の説明（文言は仮。TimyCue のみは spec §89.2 の推奨の文）
    var calendarRowNote: String? {
        guard isConnectedToApple else {
            // 開いているあいだに連携が外れて、出していた Apple の保存先に保存できない（2026-10-19 ユーザー指示 3）
            guard mode.allowsMultipleDays, let name = lostAppleTargetName else { return nil }
            return "保存先の「\(name)」（Apple カレンダー）には保存できません（\(appleLinkStatus.saveUnavailableReason)）。「TimyCue のみ」を選ぶと、このiPhoneに保存します。保存するときにも確かめます。"
        }
        if calendarRowIsMoveTarget {
            return "「Apple Calendarに保存」の移す先を選びます。この予定は、このiPhoneに保存しています。"
        }
        guard mode.allowsMultipleDays else { return nil }
        switch pendingSaveTarget {
        case .timyCueOnly?:
            return SaveTargetRules.timyCueOnlyNote
        case .usable(let calendar, _)?:
            return "Apple カレンダーの「\(calendar.title)」に保存します。ここで選んだ保存先は、この予定だけに使います。"
        case .notChosen?:
            return "保存先を選んでください。"
        case .unavailable?:
            return "今の保存先は使えません。保存先を選んでください。ここで選んだ保存先は、この予定だけに使います。"
        case nil:
            return nil
        }
    }

    // MARK: - 初めて保存する前の確かめ（Q111-4）

    /// 保存先がまだ決まっていない（移行で特定できなかった今の利用者が、連携中に初めて新しい予定を保存する）。
    /// 足りない項目があるときは、先に行で知らせる（§46）
    var needsFirstSaveTargetChoice: Bool {
        guard !isFinished, mode.allowsMultipleDays, saveIssues.isEmpty else { return false }
        if case .notChosen? = pendingSaveTarget { return true }
        return false
    }

    /// 初めての確かめの選択肢：「TimyCue のみ」・使えるときの「iPhoneの既定（名前）」・それ以外の使えるカレンダー（数は EditorMetrics）
    var firstSaveTargetOptions: [DefaultSaveTarget] {
        Array(allFirstSaveTargetOptions.prefix(EditorMetrics.firstSaveTargetChoiceLimit))
    }

    /// 選択肢が多くて全部を並べきれない（「ほかのカレンダーを選ぶ」を出す）
    var hasMoreFirstSaveTargets: Bool {
        allFirstSaveTargetOptions.count > EditorMetrics.firstSaveTargetChoiceLimit
    }

    private var allFirstSaveTargetOptions: [DefaultSaveTarget] {
        var options: [DefaultSaveTarget] = [.timyCueOnly]
        var systemDefaultCalendarID: String?
        if case .usable(let calendar, _) = saveTargets.systemDefaultResolution {
            options.append(.systemDefault)
            systemDefaultCalendarID = calendar.id
        }
        // iPhone の既定のカレンダーは重ねて出さない
        options += saveTargets.candidates.filter { $0.id != systemDefaultCalendarID }.map { DefaultSaveTarget.calendar($0.id) }
        return options
    }

    /// 初めての確かめのボタンの名前
    func defaultTargetLabel(_ target: DefaultSaveTarget) -> String {
        switch target {
        case .timyCueOnly: SaveTargetRules.timyCueOnlyLabel
        case .systemDefault: saveTargets.systemDefaultLabel
        case .calendar(let id): saveTargets.choiceLabel(.calendar(id))
        }
    }

    /// 既定として選んだものを、この予定だけの選びに直したもの（既定を保存できなかったとき、この予定の選びだけ残す）
    func eventChoice(for target: DefaultSaveTarget) -> SaveChoice? {
        switch target {
        case .timyCueOnly: return SaveChoice.timyCueOnly
        case .systemDefault: return saveTargets.systemDefaultID.map(SaveChoice.calendar)
        case .calendar(let id): return SaveChoice.calendar(id)
        }
    }

    // MARK: - 保存の前の選び直し（spec §89.4・E-10）

    /// 新しい予定（新規・コピー）を連携中に保存しようとして、保存先が使えないとき。保存の前に知らせて選び直してもらう。
    /// 選び直す候補に「TimyCue のみ」を含める。表示 OFF のときだけ「表示をONにして保存」を出す（表示のみの解除は勧めない。Q99）
    var saveTargetPrompt: SaveTargetPrompt? {
        guard !isFinished, mode.allowsMultipleDays, isConnectedToApple, saveIssues.isEmpty,
              case .unavailable(let problem, let source)? = pendingSaveTarget else { return nil }
        let name = saveTargets.name(for: .unavailable(problem, source: source))
        var hiddenCalendarID: String?
        if case .hidden = problem {
            switch source {
            case .event: hiddenCalendarID = content.calendarID
            case .settingsDefault: hiddenCalendarID = saveTargets.preferences.defaultCalendarID
            case .systemDefault: hiddenCalendarID = saveTargets.systemDefaultID
            }
        }
        let reason: String = switch problem {
        case .hidden: "保存先の「\(name)」は、TimyCue で表示を OFF にしています。"
        case .displayOnly: "保存先の「\(name)」は表示のみのカレンダーです。"
        case .readOnly: "保存先の「\(name)」には予定を書き込めません。"
        case .notFound: "保存先にしていたカレンダーが見つかりません。"
        case .noSystemDefault: "iPhone の既定のカレンダーが見つかりません。"
        }
        return SaveTargetPrompt(problem: problem, source: source, targetName: name, hiddenCalendarID: hiddenCalendarID,
                                message: reason + "保存先を選んでください。ここで選んだ保存先は、この予定だけに使います。")
    }

    /// 選び直しの選択肢：「TimyCue のみ」と、使える Apple カレンダー（数は EditorMetrics）
    var saveTargetPromptChoices: [SaveChoice] {
        [SaveChoice.timyCueOnly] + saveTargetCandidates.prefix(EditorMetrics.saveTargetPromptCalendarLimit).map { SaveChoice.calendar($0.id) }
    }

    /// 使える Apple カレンダーが多くて全部を並べきれない（「ほかのカレンダーを選ぶ」を出す）
    var hasMoreSaveTargets: Bool {
        saveTargetCandidates.count > EditorMetrics.saveTargetPromptCalendarLimit
    }

    // MARK: - 開いているあいだに連携が外れたときの確かめ（2026-10-19 ユーザー指示 3）

    /// 新規・コピーを開いているあいだに連携が外れ（連携 OFF・許可がなくなった）、画面に出していた Apple カレンダーの保存先に
    /// 保存できないとき、保存の前に出す確かめの本文。黙って TimyCue のみへ変えない（「TimyCue のみ（このiPhone）に保存」か「やめる」）。
    /// 足りない項目があるときは、先に行で知らせる（§46）。文言は仮
    var linkLossPrompt: String? {
        guard !isFinished, mode.allowsMultipleDays, !isConnectedToApple, saveIssues.isEmpty,
              let name = lostAppleTargetName else { return nil }
        return "保存先の「\(name)」（Apple カレンダー）には保存できません（\(appleLinkStatus.saveUnavailableReason)）。\(SaveTargetRules.timyCueOnlyLabel)に保存しますか？"
    }

    // MARK: - 「Apple Calendarに保存」

    /// 移す先が使えるときの名前（「iPhoneの既定（家）」など）。確かめの文とボタンの下に出す
    var moveToAppleTargetName: String? {
        guard let target = moveToAppleTarget, case .usable = target else { return nil }
        return saveTargets.name(for: target)
    }
}
