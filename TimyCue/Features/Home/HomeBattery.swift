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
