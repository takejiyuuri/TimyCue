import Foundation

/// 移動手段（仕様 §50）。公共交通は電車・地下鉄・バス・路面電車・フェリーなどをまとめたもので、細かくは選ばせない。
enum TransportMode: String, CaseIterable, Codable {
    case auto
    case car
    case walk
    case bicycle
    case publicTransit

    var displayName: String {
        switch self {
        case .auto: "自動"
        case .car: "車"
        case .walk: "徒歩"
        case .bicycle: "自転車"
        case .publicTransit: "公共交通"
        }
    }
}

/// 車のルート（仕様 §52）。移動手段が車のときだけ使う。高速料金は出さない。
enum RouteOption: String, CaseIterable, Codable {
    case auto
    case preferHighway
    case preferLocalRoads

    var displayName: String {
        switch self {
        case .auto: "自動"
        case .preferHighway: "高速優先"
        case .preferLocalRoads: "一般道優先"
        }
    }
}

/// 予定のうち、TimyCue だけが使う情報（仕様 §84）。Apple カレンダーの予定とは別に保存する（仕様 §68）。
struct TimyCueEventMetadata: Equatable, Codable {
    var color: EventColor = .orange
    /// 到着目標：予定開始の何分前に着きたいか（仕様 §49）。nil は未設定（その場所の前回設定や既定値を使う）
    var arrivalTargetMinutes: Int?
    var transport: TransportMode = .auto
    var route: RouteOption = .auto
    var notifications = NotificationPreference()
}
