import EventKit

/// Apple カレンダー連携の状態（spec §89.6・Q101・Q102・Q115。S6）。iPhone の許可の状態と、TimyCue の連携の ON/OFF から決める。
/// 利用者がわざと OFF にした状態（off）と、まだ連携していない・許可がない状態（notLinked・needsPermission・unavailable）を分ける
enum AppleLinkStatus: Equatable {
    /// 連携している（連携 ON で、フルアクセスがある）
    case linked
    /// 利用者が TimyCue の設定で連携を OFF にした（エラーではない正常な選択）
    case off
    /// まだ連携していない（許可をまだ求めていない）
    case notLinked
    /// 許可がない（拒否・追加のみ）
    case needsPermission
    /// 端末の制限で使えない
    case unavailable

    static func resolve(authorization: EKAuthorizationStatus, linkEnabled: Bool) -> AppleLinkStatus {
        guard linkEnabled else { return .off }
        switch authorization {
        case .fullAccess, .authorized: return .linked
        case .notDetermined: return .notLinked
        case .denied, .writeOnly: return .needsPermission
        case .restricted: return .unavailable
        @unknown default: return .notLinked
        }
    }

    /// 設定トップの「カレンダー連携」の右に出す状態（v1.2「設定画面」。OFF は Q102 のおすすめの「OFF」。文言は仮）。
    /// OFF でも、端末の制限で使えないときは「利用できません」
    func statusLabel(authorization: EKAuthorizationStatus) -> String {
        if self == .off {
            return authorization == .restricted ? "利用できません" : "OFF"
        }
        return Self.permissionLabel(for: authorization)
    }

    /// iPhone の許可の状態の言い方
    static func permissionLabel(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess, .authorized: "接続済み"
        case .writeOnly: "一部許可"
        case .denied: "許可が必要"
        case .restricted: "利用できません"
        case .notDetermined: "未接続"
        @unknown default: "未接続"
        }
    }

    /// Apple カレンダーに保存できない理由（連携していないとき。作成画面の行・保存の前の確かめに出す。2026-10-19 ユーザー指示 3。文言は仮）
    var saveUnavailableReason: String {
        switch self {
        case .off: "連携が OFF です"
        case .notLinked, .needsPermission: "カレンダーの許可がありません"
        case .unavailable: "この端末では Apple カレンダーを使えません"
        case .linked: "連携していません"
        }
    }

    /// Home に「カレンダーを連携、または予定を登録すると…」のカードを出すか。まだ連携していない・許可がないときは今の案内のまま
    /// （Q42-8・Q115）。わざと OFF にしたときは、連携を促すカード・帯を出さない（Q102）
    var showsSetupCard: Bool {
        switch self {
        case .notLinked, .needsPermission, .unavailable: true
        case .linked, .off: false
        }
    }
}
