import Foundation

/// ある予定の推奨出発時刻の見込み。ホーム・通知・Live Activity は、これを見て状態を決める（追加仕様書 §45）
enum DepartureEstimate: Equatable {
    /// 場所のない予定：出発時刻・移動時間・ETA を出さない。予定開始が基準（追加仕様書 §36.2）
    case notNeeded
    /// まだ計算していない（初めの計算の途中・計算を始める前）。そのあいだは予定開始で出し、原因は出さない
    case pending
    /// 推奨出発時刻（追加仕様書 §8.1）
    case available(Date)
    /// 場所はあるが、出発時刻を計算できない。黙って開始のカウントダウンへ切り替えず、開始の時計を主にして原因を小さく出す
    /// （追加仕様書 §44.11・§45.3、2026-10-14 決定）
    case unavailable(DepartureProblem)

    /// 開発中（見本の予定で動かすとき）の見込み：場所のない予定は出発を計算しない。場所のある予定は計算しないまま予定開始で出す
    static func development(for event: CalendarEvent) -> DepartureEstimate {
        HomeSchedule.hasPlace(event) ? .pending : .notNeeded
    }
}

/// 出発時刻を計算できない原因。ホームの時計の下などに小さく出す（2026-10-14 決定）
enum DepartureProblem: Equatable {
    /// 場所が文字だけで、地点が決まっていない（Q66）
    case placeUnconfirmed
    /// 公共交通のルートを取れない（追加仕様書 §27・Q67）
    case transitUnavailable
    /// 自転車のルートを取れない（徒歩のルートから換算しない。OS の版で先に弾かず、実際に取れなかったとき。2026-10-14 決定）
    case bicycleUnavailable
    /// 移動手段が「自動」で実績がなく、普段よく使う移動手段もまだ選んでいない（文言は仮）
    case transportNotChosen
    /// そのほかの理由で計算できない（ルートが取れない・現在地が取れない など）
    case failed

    var message: String {
        switch self {
        case .placeUnconfirmed: "場所を確認してください"
        case .transitUnavailable: "公共交通ルートを取得できません"
        case .bicycleUnavailable: "自転車ルートを取得できません"
        case .transportNotChosen: "普段よく使う移動手段を選んでください"
        case .failed: "出発時刻を計算できません"
        }
    }
}

/// 出発時刻は出せているが、添えて知らせること。時計の下などに小さく出す（2026-10-14 決定）。
/// 正確そうな出発時刻を、黙って見せないため
enum DepartureNote: Equatable {
    /// 現在地を使う場面で現在地が取れず、前の予定・自宅からの目安を出している
    case fallbackOrigin(String)
    /// 最新の交通情報を取れず、少し前（15 分以内）の値を出している（追加仕様書 §25.6）
    case staleTraffic

    var message: String {
        switch self {
        case .fallbackOrigin(let name): "現在地を取得できないため、\(name)からの目安です"
        case .staleTraffic: "最新の交通情報を取得できません"
        }
    }
}
