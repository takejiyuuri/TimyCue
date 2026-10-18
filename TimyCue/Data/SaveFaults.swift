import Foundation

/// 保存の途中の失敗を再現する場所（spec §89.9・2026-10-18 S1b 指示 10）。失敗の再現の印（TIMYCUE_SAVE_FAULTS）を付けたビルドの
/// 「設定 ＞ 開発用：保存の失敗の再現」で印を付けると、次の 1 回だけそこで失敗する。
/// この印はビルド確認（シミュレータのテスト・画面写真）だけに付け、TestFlight と公開版には付けない。印のないビルドでは、
/// 印を付ける処理・画面・起動引数の読み取りがなく（コンパイルされない）、check は何もせず、consume はいつも false
/// （2026-10-18 S1a＋S1b TestFlight 配信の指示：本番の構成で失敗の再現を動かさない・通常の TestFlight の操作で途中の失敗を起こさない）
enum SaveFault: String, CaseIterable, Identifiable {
    /// Apple カレンダーへ書く前
    case appleBeforeWrite
    /// Apple カレンダーへ書けた直後
    case appleAfterWrite
    /// Apple カレンダーへ書けた直後にアプリを終える（再起動のあとの復旧を確かめる）
    case terminateAfterAppleWrite
    /// 予定と Apple の予定の結び付けのファイルの保存
    case appleLinksWrite
    /// 複数日の登録の 2 日目
    case multiDaySecondDay
    /// 「Apple Calendarに保存」で、Apple に作ったあと・元の予定を消す前
    case moveAfterAppleWrite
    /// 端末の中の予定のファイルの保存
    case localEventsWrite
    /// TimyCue の設定（到着目標など）のファイルの保存
    case metadataWrite
    /// カレンダー連携の設定（表示・保存先など）の保存
    case settingsWrite
    /// Apple カレンダーの予定を消したあとの、結び付けの保存
    case appleLinksAfterDelete
    /// Apple カレンダーへ書いた結果を「確かめられない」にする
    case unknownResult

    var id: String { rawValue }
}

/// 再現した失敗（検証用のビルドだけで起きる）
struct SaveFaultInjected: Error, Equatable {
    let fault: SaveFault
}

/// 失敗の印を付けて・外して・使う。公開版では印を付けられず、check は何もしない
enum SaveFaults {
    #if TIMYCUE_SAVE_FAULTS
    private static var armed: Set<SaveFault> = []

    static var armedFaults: Set<SaveFault> { armed }

    static func arm(_ fault: SaveFault) { armed.insert(fault) }

    static func disarm(_ fault: SaveFault) { armed.remove(fault) }
    #endif

    /// 印が付いていれば、その印を外して 1 回だけ失敗させる。公開版・印がないときは何もしない
    static func check(_ fault: SaveFault?) throws {
        #if TIMYCUE_SAVE_FAULTS
        guard let fault, armed.remove(fault) != nil else { return }
        throw SaveFaultInjected(fault: fault)
        #endif
    }

    /// 印が付いていれば、その印を外して true（失敗させずに、呼ぶ側で振る舞いを変えるとき）。公開版では false
    static func consume(_ fault: SaveFault) -> Bool {
        #if TIMYCUE_SAVE_FAULTS
        return armed.remove(fault) != nil
        #else
        return false
        #endif
    }
}
