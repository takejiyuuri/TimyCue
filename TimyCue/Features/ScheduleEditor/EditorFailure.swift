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

    /// 書き込みの途中で失敗したとき。S1a では、一部だけ書けたかを確かめられないので、確かめてからやり直してもらう
    /// （予定を重複させないため。一部だけの成功の扱いは S1b。spec §89.9）
    static func writeFailed(action: Action) -> EditorFailure {
        let message = switch action {
        case .save:
            "Apple カレンダーか、この iPhone への書き込みに失敗しました。予定が一部だけ保存されていることがあるため、カレンダーで確かめてから、もう一度お試しください。"
        case .moveToApple:
            "Apple カレンダーへの書き込みに失敗しました。予定が Apple カレンダーと TimyCue の両方に残っていることがあるため、カレンダーで確かめてから、もう一度お試しください。"
        case .delete:
            "削除の途中で失敗しました。予定が残っているか、カレンダーで確かめてから、もう一度お試しください。"
        }
        return EditorFailure(action: action, title: title(for: action), message: message)
    }

    /// 編集している予定が見つからなかったとき（Apple カレンダー側で消された・移されたなど）
    static func eventMissing(action: Action) -> EditorFailure {
        EditorFailure(action: action, title: title(for: action),
                      message: "この予定が見つかりませんでした。Apple カレンダーで削除か移動された可能性があります。")
    }
}
