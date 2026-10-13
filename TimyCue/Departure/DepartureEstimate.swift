import Foundation

/// ある予定の推奨出発時刻の見込み。ホーム・通知・Live Activity は、これを見て状態を決める（追加仕様書 §45）
enum DepartureEstimate: Equatable {
    /// 場所のない予定：出発時刻・移動時間・ETA を出さない。予定開始が基準（追加仕様書 §36.2）
    case notNeeded
    /// 推奨出発時刻（追加仕様書 §8.1）
    case available(Date)
    /// 場所はあるが、出発時刻を計算できない。製品では黙って予定開始へ切り替えず、別の状態にする（追加仕様書 §44.11）
    case unavailable
    /// 出発時刻の計算をまだ作っていない（開発中だけ）。予定開始で仮に動かしてよい（追加仕様書 §44.11）
    case notImplemented

    /// 第 5 段階の出発時刻の計算（地図の移動時間・起点・現在地）ができるまでの、開発中だけの見込み。
    /// 場所のない予定は出発を計算しない。場所のある予定は「まだ作っていない」（予定開始で仮に動かす）
    static func development(for event: CalendarEvent) -> DepartureEstimate {
        HomeSchedule.hasPlace(event) ? .notImplemented : .notNeeded
    }
}
