import Foundation

/// 推奨出発時刻の計算（追加仕様書 §8.1〜§8.3。2026-10-13 確定）。画面に依らない計算だけを置く。
/// 推奨出発時刻 ＝ 到着目標の時刻 − 予測移動時間 − 安全マージン。
/// 予測移動時間（地図の移動時間・駐車・入口まで）は 1 分単位に切り上げ、安全マージンは最後に足す。
/// 地図の移動時間を取る所（起点・現在地・地図への問い合わせ）は、まだない（第 5 段階の続き）
enum DepartureMath {
    /// 安全マージンの設定（追加仕様書 §8.3・Q68）：標準・やや余裕・かなり余裕
    enum MarginLevel: String, CaseIterable, Codable {
        case standard
        case relaxed
        case generous

        var displayName: String {
            switch self {
            case .standard: "標準"
            case .relaxed: "やや余裕"
            case .generous: "かなり余裕"
            }
        }

        /// 移動時間に対する割合（％）と、いちばん短い分
        var percent: Int {
            switch self {
            case .standard: 10
            case .relaxed: 15
            case .generous: 25
            }
        }

        var minimumMinutes: Int {
            switch self {
            case .standard: 3
            case .relaxed: 5
            case .generous: 10
            }
        }
    }

    /// 車で、駐車の学習がない場所に足す汎用のバッファ（駐車場所探し・駐車・入口までの短い徒歩。追加仕様書 §8.2）
    static let carParkingBufferMinutes = 5

    /// 地図などから得た移動時間を、1 分単位に切り上げる（28 分 34 秒 → 29 分。追加仕様書 §8.2）
    static func minutes(ofTravel seconds: TimeInterval) -> Int {
        max(0, Int((seconds / 60).rounded(.up)))
    }

    /// 予測移動時間（分）。地図の移動時間に、車なら駐車にかかる時間（学習がなければ汎用の 5 分）を足す（追加仕様書 §8.2）。
    /// 移動手段が「自動」なら、内部で予測した手段にしてから渡す（追加仕様書 §30.1）
    static func predictedTravelMinutes(mapSeconds: TimeInterval,
                                       transport: TransportMode,
                                       learnedParkingMinutes: Int? = nil) -> Int {
        let base = minutes(ofTravel: mapSeconds)
        guard transport == .car else { return base }
        return base + (learnedParkingMinutes ?? carParkingBufferMinutes)
    }

    /// 安全マージン（分）。移動時間の割合といちばん短い分の大きい方。割合の端数は 1 分単位に切り上げる
    /// （37 分 × 10％ ＝ 3.7 分 → 4 分。追加仕様書 §8.3）
    static func safetyMarginMinutes(travelMinutes: Int, level: MarginLevel) -> Int {
        let byRate = (max(travelMinutes, 0) * level.percent + 99) / 100
        return max(byRate, level.minimumMinutes)
    }

    /// 到着目標の時刻（予定開始の○分前。0 分前なら予定開始時刻。追加仕様書 §8.1）
    static func arrivalTarget(start: Date, arrivalTargetMinutes: Int) -> Date {
        start.addingTimeInterval(-TimeInterval(arrivalTargetMinutes * 60))
    }

    /// 推奨出発時刻（追加仕様書 §8.1）。例：予定開始 10:00・到着目標 10 分前・予測移動 30 分・安全マージン 5 分 → 9:15。
    /// 公共交通は、安全マージンを乗車時間に足さず、到着目標を前倒しして便を探すので、この式では出さない（追加仕様書 §8.3）
    static func recommendedDeparture(start: Date,
                                     arrivalTargetMinutes: Int,
                                     travelMinutes: Int,
                                     marginMinutes: Int) -> Date {
        arrivalTarget(start: start, arrivalTargetMinutes: arrivalTargetMinutes)
            .addingTimeInterval(-TimeInterval((travelMinutes + marginMinutes) * 60))
    }
}
