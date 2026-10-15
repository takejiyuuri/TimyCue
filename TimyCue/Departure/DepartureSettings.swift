import Foundation

/// 地図の上の 1 地点（自宅・確かめた予定の場所）
struct SavedPlace: Codable, Equatable, Hashable {
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
}

/// 設定「最初の予定の出発地点」（spec Q42-2）
enum FirstEventOrigin: String, Codable, CaseIterable {
    case home
    case elsewhere

    var displayName: String {
        switch self {
        case .home: "自宅から出ることが多い"
        case .elsewhere: "自宅以外から出ることが多い"
        }
    }
}

/// 設定 ＞ 出発・移動（2026-10-14 決定）。アプリ全体の設定で、予定ごとには持たない
struct DepartureSettings: Codable, Equatable {
    /// 出発の余裕（安全マージン）。初期値は「標準」（2026-10-14 決定）
    var marginLevel: DepartureMath.MarginLevel = .standard
    /// 自宅。未登録なら nil。名前は初めから「自宅」（spec Q42-2）
    var home: SavedPlace?
    /// 最初の予定の出発地点。まだ選んでいなければ nil（固定の起点がないのと同じに扱う）
    var firstEventOrigin: FirstEventOrigin?
    /// 普段よく使う移動手段。移動手段が「自動」で実績がないときの初めの候補（2026-10-14 決定）。未回答なら nil
    var usualTransport: TransportMode?
    /// 「普段よく使う移動手段」をもう聞いたか（選ばずに閉じても、もう自分からは聞かない。設定で変えられる）
    var askedUsualTransport = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case marginLevel, home, firstEventOrigin, usualTransport, askedUsualTransport
    }

    /// あとから項目を足しても、前のファイルを読めるようにする
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marginLevel = try container.decodeIfPresent(DepartureMath.MarginLevel.self, forKey: .marginLevel) ?? .standard
        home = try container.decodeIfPresent(SavedPlace.self, forKey: .home)
        firstEventOrigin = try container.decodeIfPresent(FirstEventOrigin.self, forKey: .firstEventOrigin)
        usualTransport = try container.decodeIfPresent(TransportMode.self, forKey: .usualTransport)
        askedUsualTransport = try container.decodeIfPresent(Bool.self, forKey: .askedUsualTransport) ?? false
    }
}

/// 予定の場所の文字と、確かめた地点の対応（追加仕様書 §23.1：一度確定した場所名と地点の対応は学習する）。
/// 文字だけの場所は、ここに地点がなければ「場所を確認してください」（Q66）
struct PlaceBook: Codable, Equatable {
    var places: [String: SavedPlace] = [:]

    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func place(for text: String?) -> SavedPlace? {
        guard let text else { return nil }
        let key = Self.key(text)
        return key.isEmpty ? nil : places[key]
    }

    mutating func confirm(_ place: SavedPlace, for text: String) {
        let key = Self.key(text)
        guard !key.isEmpty else { return }
        places[key] = place
    }
}
