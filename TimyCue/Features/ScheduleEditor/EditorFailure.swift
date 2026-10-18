import Foundation

/// 3 分割画面で、保存・「Apple Calendarに保存」・削除に失敗したときに出すアラートの中身（spec §89.9。2026-10-17 決定 7、2026-10-18 Q107・Q110）。
/// 成功したように閉じず、理由と次の操作を出す。設定画面へ直接移るボタンは置かない（Q110）。文言は決定の例文のほかは仮
struct EditorFailure: Equatable, Identifiable {
    enum Action: Equatable {
        case save
        case moveToApple
        case delete
    }

    let action: Action
    let title: String
    let message: String
    /// 知らせを閉じたら、画面も閉じる（もう保存するものがない・その場で押し直させないとき）
    var closesEditor = false

    var id: String { title + message }

    static func title(for action: Action) -> String {
        switch action {
        case .save: "保存できませんでした"
        case .moveToApple: "Apple Calendarに保存できませんでした"
        case .delete: "削除できませんでした"
        }
    }

    /// 保存先が使えないので、何も書かずに止めたとき（spec §89.4）。
    /// canChooseInRow：作成画面の「カレンダー」の行で、ほかの保存先を選べるか
    static func saveTarget(_ problem: SaveTargetProblem,
                           source: SaveTargetSource,
                           systemDefaultLabel: String,
                           action: Action,
                           canChooseInRow: Bool) -> EditorFailure {
        let isMove = action == .moveToApple
        let target = isMove ? "移す先" : "保存先"
        let name = source == .systemDefault ? "「\(systemDefaultLabel)」" : SaveTargetRules.title(of: problem).map { "「\($0)」" } ?? ""

        var sentences = ["\(target)のカレンダーを確認してください。"]
        switch problem {
        case .hidden:
            sentences.append("\(target)の\(name)は、TimyCue で表示を OFF にしています。")
        case .displayOnly:
            sentences.append("\(target)の\(name)は表示のみのカレンダーです。")
        case .readOnly:
            sentences.append("\(target)の\(name)には予定を書き込めません。")
        case .notFound:
            sentences.append("\(target)にしていたカレンダーが見つかりません。")
        case .noSystemDefault:
            sentences.append("iPhone の既定のカレンダーが見つかりません。")
        }
        if isMove {
            switch problem {
            case .hidden: sentences.append("移すと TimyCue に出なくなるため、移していません。")
            case .displayOnly: sentences.append("移すと TimyCue で編集できず、出発の案内もしなくなるため、移していません。")
            default: sentences.append("移していません。")
            }
            sentences.append("TimyCue の中の予定はそのまま残っています。")
        } else {
            sentences.append("予定は保存していません。")
        }

        // 次の操作。その予定だけの指定が使えないときは、まず「カレンダー」の行で選び直してもらう
        if source == .event && canChooseInRow {
            sentences.append("「カレンダー」の行で別のカレンダーを選んでください。")
        } else {
            if case .hidden = problem {
                sentences.append("設定 ＞ カレンダー連携 で表示を ON にするか、新しい予定の保存先を変えてください。")
            } else {
                sentences.append("設定 ＞ カレンダー連携 で新しい予定の保存先を変えてください。")
            }
            if canChooseInRow {
                sentences.append(isMove
                                 ? "この予定だけ別のカレンダーに移すときは、「カレンダー」の行で選んでください。"
                                 : "この予定だけ別のカレンダーに保存するときは、「カレンダー」の行で選んでください。")
            }
        }
        return EditorFailure(action: action, title: title(for: action), message: sentences.joined())
    }

    /// 書いていない・消していないと確かめたとき（書く前に止まった・失敗のあと確かめても見つからなかった。spec §89.9・2026-10-18 S1b）
    static func notWritten(action: Action) -> EditorFailure {
        let message = switch action {
        case .save:
            "Apple カレンダーか、この iPhone への書き込みに失敗しました。予定は保存していません。もう一度お試しください。"
        case .moveToApple:
            "Apple Calendarへの書き込みに失敗しました。Apple Calendarには作っていません。TimyCue の中の予定はそのまま残っています。もう一度お試しください。"
        case .delete:
            "削除できませんでした。予定は残っています。もう一度お試しください。"
        }
        return EditorFailure(action: action, title: title(for: action), message: message)
    }

    /// 編集の保存に失敗したとき。Apple カレンダーの予定は、直ったかどうかをその場で確かめられないので、確かめてもらう
    /// （直す保存は、押し直しても予定は増えない）
    static func updateFailed(isAppleEvent: Bool) -> EditorFailure {
        EditorFailure(action: .save, title: title(for: .save),
                      message: isAppleEvent
                          ? "変更を保存できませんでした。予定の内容が変わっていないか、カレンダーで確かめてから、もう一度お試しください。"
                          : "変更を保存できませんでした。予定は前の内容のままです。もう一度お試しください。")
    }

    /// 書けたか・消せたかを確かめられなかったとき。失敗とは言わず、自動ではやり直さない
    static func unconfirmed(action: Action) -> EditorFailure {
        switch action {
        case .save, .moveToApple:
            EditorFailure(action: action, title: "保存結果を確認できませんでした",
                          message: "保存結果を確認できませんでした。重複を防ぐため、自動で再保存していません。カレンダーで予定があるか確かめてください。")
        case .delete:
            EditorFailure(action: action, title: "削除結果を確認できませんでした",
                          message: "削除できたか確認できませんでした。カレンダーで予定が残っているか確かめてください。")
        }
    }

    /// 複数日の一部だけ保存できた・結果を確かめられない日があったとき（spec §89.9・Q110）。
    /// 保存した日・保存していない日・確認が必要な日を分けて出す。保存していない日だけが選ばれた状態で、もう一度保存できる。
    /// 保存していない日がなければ、知らせのあと閉じる
    static func partialSave(saved: [CalendarDay], notSaved: [CalendarDay], unknown: [CalendarDay],
                            settingsSaved: Bool) -> EditorFailure {
        var lines: [String] = []
        let title: String
        if unknown.isEmpty {
            title = "一部の日だけ保存しました"
        } else {
            title = "保存結果を確認できませんでした"
            lines.append("保存結果を確認できませんでした。重複を防ぐため、自動で再保存していません。")
            lines.append("確認が必要な日：\(dayList(unknown))")
        }
        if !saved.isEmpty { lines.append("保存した日：\(dayList(saved))") }
        if !notSaved.isEmpty { lines.append("保存していない日：\(dayList(notSaved))") }
        if !unknown.isEmpty { lines.append("確認が必要な日に予定があるか、カレンダーで確かめてください。") }
        if !notSaved.isEmpty {
            lines.append("保存していない日だけを残しました。もう一度保存すると、その日だけを保存します（保存した日は重ねて保存しません）。")
        }
        if !settingsSaved { lines.append("到着目標などの TimyCue の設定は、あとで自動でもう一度保存します。") }
        return EditorFailure(action: .save, title: title, message: lines.joined(separator: "\n"), closesEditor: notSaved.isEmpty)
    }

    /// 予定は保存できたのに、到着目標などの TimyCue の設定を保存できなかったとき。予定は保存してあるので、押し直してもらわない
    static func settingsNotSaved(isEdit: Bool) -> EditorFailure {
        EditorFailure(action: .save, title: isEdit ? "変更を保存しました" : "予定を保存しました",
                      message: "到着目標などの TimyCue の設定を保存できませんでした。予定は保存してあるので、もう一度保存しなくてかまいません。設定は、あとで自動でもう一度保存します。",
                      closesEditor: true)
    }

    /// 「Apple Calendarに保存」で、Apple に作れたか確かめられなかったとき。作り直さず、元の予定も消さない
    static func moveUnconfirmed() -> EditorFailure {
        EditorFailure(action: .moveToApple, title: "保存結果を確認できませんでした",
                      message: "Apple Calendarに予定を作れたか確認できませんでした。重複を防ぐため、自動で作り直さず、TimyCue の中の予定も消していません。カレンダーで同じ予定があるか確かめてください。",
                      closesEditor: true)
    }

    /// 「Apple Calendarに保存」で、Apple に作れたあとに止まったとき。両方に残し、どちらも自動では消さない
    static func moveIncomplete(settingsCopied: Bool) -> EditorFailure {
        let reason = settingsCopied
            ? "TimyCue の中の予定を消せなかったため、両方に残っています。"
            : "到着目標などの設定を引き継げなかったため、TimyCue の中の予定は消していません。両方に残っています。"
        return EditorFailure(action: .moveToApple, title: "Apple Calendarに保存しました",
                             message: "Apple Calendarに予定を作りましたが、\(reason)どちらも自動では消しません。もう一度この予定を開いて「Apple Calendarに保存」を押すと、Apple Calendarに作り直さずに続きを行います。重複候補から片方を選ぶこともできます。",
                             closesEditor: true)
    }

    /// 「Apple Calendarに保存」の続き（前に Apple に作った予定がある）で、その予定を今の内容に直せなかったとき。
    /// 両方に残し、どちらも自動では消さない。押し直しても作り直さないので、閉じずにもう一度試せる
    static func moveResumeFailed(unconfirmed: Bool) -> EditorFailure {
        EditorFailure(action: .moveToApple,
                      title: unconfirmed ? "保存結果を確認できませんでした" : title(for: .moveToApple),
                      message: "Apple Calendarには、前に作った予定があります。"
                          + (unconfirmed ? "今の内容に直せたか確認できませんでした。" : "今の内容に直せませんでした。")
                          + "TimyCue の中の予定も消していないので、両方に残っています。どちらも自動では消しません。もう一度押しても Apple Calendarに作り直さず、続きを行います。")
    }

    /// 日の並び（例「10月18日（日）、10月19日（月）」）
    static func dayList(_ days: [CalendarDay]) -> String {
        days.sorted().map { "\($0.month)月\($0.day)日（\($0.weekdaySymbol())）" }.joined(separator: "、")
    }

    /// 編集している予定が見つからなかったとき（Apple カレンダー側で消された・移されたなど）
    static func eventMissing(action: Action) -> EditorFailure {
        EditorFailure(action: action, title: title(for: action),
                      message: "この予定が見つかりませんでした。Apple カレンダーで削除か移動された可能性があります。")
    }
}
