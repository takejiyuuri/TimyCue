import Foundation

// 書き込みの結果を、成功・失敗・結果不明に分ける（spec §89.9・2026-10-18 S1b）。
// Apple カレンダー（EventKit）と TimyCue の中の保存を 1 つの取引とはみなさない。1 件ずつ書いて、その結果を確かめる

/// 1 件の書き込みの結果
enum WriteOutcome: Equatable {
    /// 書けたことを確かめた
    case saved
    /// 書いていないことを確かめた（書く前に止めた・失敗のあとで確かめても見つからなかった）
    case notSaved
    /// 書けたかどうか確かめられない。重複を防ぐため、自動では書き直さない
    case unknown
}

/// 書けたかどうか確かめられなかった（削除のあとで、消えたか確かめられないときなど）
enum WriteCheckError: Error, Equatable {
    case unconfirmed
}

/// 新しい予定を 1 件ずつ書いた結果（複数日は日ごとに分ける）
struct InsertReport {
    /// 書けた予定
    var saved: [CalendarEvent] = []
    /// 書いていない予定（失敗した予定と、そのあとで書かなかった予定）
    var notSaved: [CalendarEvent] = []
    /// 書けたか確かめられない予定
    var unknown: [CalendarEvent] = []
    /// 最初の失敗（理由を出すため）
    var error: Error?

    /// 全部書けた
    var isComplete: Bool { notSaved.isEmpty && unknown.isEmpty }
}

enum InsertRun {
    /// 予定を 1 件ずつ書く。失敗したらそこで止め、残りは書かない（失敗のあとに書き続けて、ばらばらに残さない）。
    /// write が投げたら verify で実際の状態を確かめる（書けていたら成功として扱い、続ける。確かめられなければ結果不明として止める）
    static func run(_ events: [CalendarEvent],
                    write: (CalendarEvent, Int) throws -> Void,
                    verify: (CalendarEvent, Error) -> WriteOutcome) -> InsertReport {
        var report = InsertReport()
        for (index, event) in events.enumerated() {
            let outcome: WriteOutcome
            do {
                try write(event, index)
                outcome = .saved
            } catch {
                report.error = report.error ?? error
                outcome = verify(event, error)
            }
            switch outcome {
            case .saved: report.saved.append(event)
            case .notSaved: report.notSaved.append(event)
            case .unknown: report.unknown.append(event)
            }
            if outcome != .saved {
                report.notSaved.append(contentsOf: events.dropFirst(index + 1))
                break
            }
        }
        return report
    }
}

/// Apple カレンダーへ書いたあとに失敗が届いたときの確かめ（EventKit から読んだ事実だけで決める。名前や日時が似ているだけでは結び付けない）
enum WriteVerification {
    /// foundByIdentifier：書いた予定を識別子で引けた。lookalikes：同じカレンダー・同じ日時・同じ予定名の、まだ結び付けていない、
    /// いま作られたばかりの予定の数。canTrustAbsence：見つからないことを信じてよいか（フルアクセスで、保存先のカレンダーが今もある）
    static func insertOutcome(foundByIdentifier: Bool, lookalikes: Int, canTrustAbsence: Bool) -> WriteOutcome {
        if foundByIdentifier { return .saved }
        // 識別子では引けないのに似た予定があるときは、こちらが作ったものか区別できない
        if lookalikes > 0 { return .unknown }
        return canTrustAbsence ? .notSaved : .unknown
    }

    /// 削除のあとに失敗が届いたとき。.saved は「消せた」。stillExists：まだ引ける。canTrustAbsence：見つからないことを信じてよいか
    static func deleteOutcome(stillExists: Bool, canTrustAbsence: Bool) -> WriteOutcome {
        if stillExists { return .notSaved }
        return canTrustAbsence ? .saved : .unknown
    }
}
