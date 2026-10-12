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

/// TimyCue の情報の項目。繰り返し予定で「この回だけ変えた項目」を記録するのに使う（追加仕様書 §2.7.1・Q53）
enum MetadataField: String, Codable, CaseIterable {
    case color
    case arrivalTarget
    case transport
    case route
    case notifications
}

/// 予定のうち、TimyCue だけが使う情報（仕様 §84）。Apple カレンダーの予定とは別に保存する（仕様 §68）。
struct TimyCueEventMetadata: Equatable, Codable {
    var color: EventColor = .orange
    /// 到着目標：予定開始の何分前に着きたいか（仕様 §49）。nil は未設定（その場所の前回設定や既定値を使う）
    var arrivalTargetMinutes: Int?
    var transport: TransportMode = .auto
    var route: RouteOption = .auto
    var notifications = NotificationPreference()
    /// 繰り返し予定で、ユーザーが「この予定のみ」で変えた項目（個別上書き）。
    /// 値の違いで推測せず、変えた履歴で見分ける（追加仕様書 §2.7.1・Q53）。古いファイルにはないので省略できる
    var overrides: Set<MetadataField>?

    /// 個別上書きの項目（空なら、すべてシリーズ共通の設定）
    var overriddenFields: Set<MetadataField> {
        get { overrides ?? [] }
        set { overrides = newValue.isEmpty ? nil : newValue }
    }

    /// その項目の値が同じか
    func hasSameValue(as other: TimyCueEventMetadata, for field: MetadataField) -> Bool {
        switch field {
        case .color: color == other.color
        case .arrivalTarget: arrivalTargetMinutes == other.arrivalTargetMinutes
        case .transport: transport == other.transport
        case .route: route == other.route
        case .notifications: notifications == other.notifications
        }
    }

    /// その項目の値を other から写す
    mutating func copyValue(of field: MetadataField, from other: TimyCueEventMetadata) {
        switch field {
        case .color: color = other.color
        case .arrivalTarget: arrivalTargetMinutes = other.arrivalTargetMinutes
        case .transport: transport = other.transport
        case .route: route = other.route
        case .notifications: notifications = other.notifications
        }
    }

    /// ユーザーが変えた項目
    func changedFields(to other: TimyCueEventMetadata) -> Set<MetadataField> {
        Set(MetadataField.allCases.filter { !hasSameValue(as: other, for: $0) })
    }
}

/// 繰り返し予定の TimyCue の情報の当て方（追加仕様書 §2.7・§2.7.1・Q53）。
/// シリーズ全体の共通設定と、回ごとの個別上書きを分けて扱う
enum RecurringMetadata {
    /// 「この予定のみ」：その回に新しい値を入れ、変えた項目を個別上書きとして記録する
    static func thisOnly(before: TimyCueEventMetadata, after: TimyCueEventMetadata) -> TimyCueEventMetadata {
        var result = after
        result.overriddenFields = before.overriddenFields.union(before.changedFields(to: after))
        return result
    }

    /// 「これ以降」「すべて」：対象の回に、変えた項目の新しい値を当てる。
    /// ほかの回で個別上書きされている項目は残す。編集していた回そのものの、変えた項目の個別上書きは解除する
    static func series(target: TimyCueEventMetadata,
                       changed: Set<MetadataField>,
                       newValues: TimyCueEventMetadata,
                       isEditedOccurrence: Bool) -> TimyCueEventMetadata {
        var result = target
        for field in changed {
            if isEditedOccurrence {
                result.copyValue(of: field, from: newValues)
                result.overriddenFields.remove(field)
            } else if !target.overriddenFields.contains(field) {
                result.copyValue(of: field, from: newValues)
            }
        }
        return result
    }

    /// シリーズ共通の設定を更新する（個別上書きの印は持たない）
    static func updatedCommon(_ common: TimyCueEventMetadata, changed: Set<MetadataField>, newValues: TimyCueEventMetadata) -> TimyCueEventMetadata {
        var result = common
        for field in changed { result.copyValue(of: field, from: newValues) }
        result.overrides = nil
        return result
    }
}
