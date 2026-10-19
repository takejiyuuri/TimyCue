import Observation
import UIKit

/// Home の右上に出す電池の残量（spec §88.2：Home だけ iOS のステータスバーを出さず、アプリ独自の電池の表示を置く）。
/// 残量が取れないとき（シミュレータなど）は出さない（nil）。形（マーク・％・充電中・残りが少ないとき）は仮で、H2 の実機で決める
struct HomeBatteryReading: Equatable {
    /// 残量（0〜100％）
    let percent: Int
    let isCharging: Bool

    /// UIDevice の値から作る。残量が分からない（-1）・状態が分からないときは nil
    init?(level: Float, state: UIDevice.BatteryState) {
        guard level >= 0, level <= 1, state != .unknown else { return nil }
        percent = Int((level * 100).rounded())
        isCharging = state == .charging || state == .full
    }

    init(percent: Int, isCharging: Bool) {
        self.percent = min(max(percent, 0), 100)
        self.isCharging = isCharging
    }

    /// 「80%」
    var text: String { "\(percent)%" }

    /// 残りが少ない（充電していないとき）
    var isLow: Bool { !isCharging && percent <= HomeLayoutMetrics.batteryLowPercent }

    /// 電池のマーク（SF Symbols。残量に近い段のもの。充電中は稲妻つき）
    var symbolName: String {
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }

    /// 読み上げ
    var accessibilityText: String {
        "バッテリー \(percent)パーセント" + (isCharging ? "、充電中" : "")
    }
}

/// 右上の電池の縦の位置（spec §88.2。2026-10-19 の見やすさの調整）。画面に依らない計算だけを置く。
/// Home は iOS のステータスバーを出さないので、電池を、ふだんのステータスバーの電池に近い高さへ寄せる。電池は日付の行の中で
/// 縦の中央にそろえて置き、そこから lift だけ上へずらす（日付・時計・タイムラインの縦の位置は動かさない）。
/// Safe Area の上が大きい機種（Dynamic Island・ノッチ。上が約 44〜62pt）では決めた量だけ上げ、小さい機種（SE など。ステータスバーを
/// 隠すと 0、出していれば 20pt）では、画面の上の端から batteryMinimumScreenTop を残すよう、上げる量を抑える。
/// 電池は右の端にそろえたまま（Dynamic Island・ノッチは画面の中央にあるので、横に重ならない）
enum HomeBatteryPlacement {
    /// 電池を上へずらす量（pt。0 以上）
    static func lift(safeAreaTop: CGFloat) -> CGFloat {
        let room = safeAreaTop + HomeLayoutMetrics.topPadding - HomeLayoutMetrics.batteryMinimumScreenTop
        return min(HomeLayoutMetrics.batteryLift, max(0, room))
    }

    /// ずらしたあとの電池の上の端の、画面の上の端からの位置の下限（pt）。日付の行の上の端から数える控えめな見込みで、
    /// 行の中で縦の中央にそろえる分のすき間（数 pt）は入れない。実際の上の端は、これより少し下になる
    static func topEdge(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + HomeLayoutMetrics.topPadding - lift(safeAreaTop: safeAreaTop)
    }

    /// 電池の左の端（画面の左からの位置。標準の文字の大きさでの幅の見込みから）
    static func leadingEdge(screenWidth: CGFloat) -> CGFloat {
        screenWidth - HomeLayoutMetrics.horizontalPadding - HomeLayoutMetrics.batteryEstimatedWidth
    }
}

/// 電池の残量の見張り（Home を出しているあいだだけ。UIDevice の電池の監視）。値は reading に入る
@Observable
final class HomeBattery {
    private(set) var reading: HomeBatteryReading? = nil
    /// 画面写真用の見本の残量を使っている（DEBUG の起動引数 -TimyCueSampleBattery のとき）
    @ObservationIgnored private var usesSample = false

    init() {}

    /// 見張りを始めて、今の値を読む
    @MainActor
    func start() {
        #if DEBUG
        if let sample = Self.sampleReading() {
            usesSample = true
            reading = sample
            return
        }
        #endif
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
    }

    /// 今の値を読み直す（残量・充電の状態が変わったという知らせを受けたとき）
    @MainActor
    func refresh() {
        guard !usesSample else { return }
        let device = UIDevice.current
        reading = HomeBatteryReading(level: device.batteryLevel, state: device.batteryState)
    }

    /// 見張りをやめる（Home を出ていないとき）
    @MainActor
    func stop() {
        guard !usesSample else { return }
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    #if DEBUG
    /// Codemagic の画面写真用：起動引数 `-TimyCueSampleBattery 80`（充電中は `80c`）。シミュレータは電池の残量を返さないため。
    /// DEBUG のときだけ（公開版・TestFlight の形には入らない）
    static func sampleReading(_ defaults: UserDefaults = .standard) -> HomeBatteryReading? {
        guard var raw = defaults.string(forKey: "TimyCueSampleBattery") else { return nil }
        let charging = raw.hasSuffix("c")
        if charging { raw.removeLast() }
        guard let percent = Int(raw) else { return nil }
        return HomeBatteryReading(percent: percent, isCharging: charging)
    }
    #endif
}
