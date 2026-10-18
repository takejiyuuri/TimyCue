import Foundation

/// Apple カレンダー（EventKit）の保存先（spec §89.6。S6）。CalendarConnection が使う分だけをまとめる。
/// 連携を OFF にしても捨てずに止めておき（メモリの上の結び付けを失わない）、ON に戻したら使い直す。
/// テストでは EventKit の代わりの保存先を使う
protocol AppleCalendarRepository: EventRepository {
    /// 裏での読み込みが済んで、予定が変わったとき（画面の処理の中で呼ぶ）
    var onLoaded: (@MainActor () -> Void)? { get set }
    /// 見えるカレンダー（書き込めないものも含む）
    func calendars() -> [CalendarChoice]
    /// iPhone の「新規イベントのデフォルトカレンダー」
    var systemDefaultCalendarID: String? { get }
    /// 頼んだ範囲を裏で読み直す
    func reloadCache()
    /// 前回の保存の途中で終わっていたら、記録した鍵で結び付け直す。確かめてもらう記録を返す（spec §89.9）
    func recover(now: Date) -> [SaveJournalEntry]
    /// 止める：書けていない結び付けを先に書き、読み込みと書き込みをやめ、読んだ予定を捨てる（連携 OFF）
    func pause()
    /// 使い直す：最初の読み込みで、消えた予定をもう一度確かめる（連携 ON）
    func resume()
    /// 「見つからない」の記録をやり直す（OFF の前に付けた記録で、ON に戻した直後に予定を消さない。spec §89.6・Q103）
    func resetMissingRecords()
}
