import Foundation
import Observation

/// Home の画面の状態（どの吹き出しを出しているか・開いている画面）。Home に出す中身そのものは HomeScreenModel が予定から計算する。
/// 予定の行・出発の点を押すと、別画面へ移らず Home の上に予定詳細の吹き出しを出す（v1.2「予定詳細の表示方式」・§88.2）。
/// 「終わった予定 ○件」は Home の中で広げず、吹き出しで一覧を出す（Q84）
@Observable
final class HomeStore {
    enum Bubble: Equatable {
        /// 予定の行・出発の点を押したときの予定詳細。anchorID は押した行（吹き出しをその近くに出す）
        case detail(eventID: UUID, anchorID: String)
        /// 「終わった予定 ○件」の一覧。selected は一覧から開いた予定詳細（もう一度押すと一覧へ戻る：Q29）
        case finished(selected: UUID?)
    }

    /// 「終わった予定 ○件」の吹き出しを出す位置の名前
    static let finishedAnchorID = "finished"

    private(set) var bubble: Bubble? = nil
    /// ［予定を登録］で開いた新規の 3 分割画面（初期日付は今日、開始時刻は未設定。Q42-8）
    var newEventDay: CalendarDay? = nil
    /// 予定詳細の吹き出しの「編集」で開く 3 分割画面（Q30）
    var editRequest: EditRequest? = nil
    /// 重複候補の一覧（Q50）
    var showsDuplicates = false
    /// 「場所を確認」の候補選択／検索（Q66）を開いている予定
    var placeCheck: CalendarEvent? = nil

    init() {}

    /// 吹き出しを出す位置の名前（出していなければ nil）
    var bubbleAnchorID: String? {
        switch bubble {
        case .detail(_, let anchorID)?:
            return anchorID
        case .finished?:
            return Self.finishedAnchorID
        case nil:
            return nil
        }
    }

    /// 予定の行・出発の点を押した。同じ行をもう一度押したら閉じる（月カレンダーの吹き出しと同じ。Q9）
    func tapRow(eventID: UUID, anchorID: String) {
        let next = Bubble.detail(eventID: eventID, anchorID: anchorID)
        bubble = bubble == next ? nil : next
    }

    /// 「終わった予定 ○件」を押した。出していれば閉じる
    func tapFinished() {
        if case .finished? = bubble {
            bubble = nil
        } else {
            bubble = .finished(selected: nil)
        }
    }

    /// 「終わった予定」の一覧から予定を押した：同じ吹き出しの中身を予定詳細に切り替える（Q28(a)）
    func showFinishedDetail(_ eventID: UUID) {
        bubble = .finished(selected: eventID)
    }

    /// 予定詳細の中をもう一度押した：一覧へ戻る（Q29）
    func backToFinishedList() {
        bubble = .finished(selected: nil)
    }

    /// 吹き出しの外を押した・予定を消した
    func closeBubble() {
        bubble = nil
    }

    /// 予定が変わった（追加・編集・削除・日付の変化・保存先の変更・Apple 連携の ON/OFF）とき。吹き出しの予定がもうなければ閉じる
    func reconcile(eventIDs: Set<UUID>) {
        switch bubble {
        case .detail(let id, _)?:
            if !eventIDs.contains(id) { bubble = nil }
        case .finished(let selected?)?:
            if !eventIDs.contains(selected) { bubble = .finished(selected: nil) }
        case .finished(nil)?, nil:
            break
        }
    }
}
