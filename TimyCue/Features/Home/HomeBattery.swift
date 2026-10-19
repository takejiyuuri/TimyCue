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

/// Home の画面のいちばん上の形（右上の電池の置き方を切り替える。2026-10-19 の上の段の最終調整）。
/// Safe Area の上の高さから見分ける：Dynamic Island の機種は 59・62pt、ノッチの機種は 44〜50pt、ホームボタンの機種は
/// ステータスバーを隠すと 0（出していれば 20pt）。表示の拡大で Dynamic Island の機種が小さくなったときはノッチとして扱う（安全な側）
enum HomeTopShape: Equatable {
    case dynamicIsland
    case notch
    /// 上に切り欠きがない（ホームボタンの機種。SE など）
    case flat

    static func from(safeAreaTop: CGFloat) -> HomeTopShape {
        if safeAreaTop >= HomeLayoutMetrics.dynamicIslandMinimumSafeTop { return .dynamicIsland }
        if safeAreaTop >= HomeLayoutMetrics.notchMinimumSafeTop { return .notch }
        return .flat
    }
}

/// 右上の電池（％とマークをひとまとめ）の置き場所（spec §88.2。2026-10-19 の上の段の最終調整）。画面に依らない計算だけを置く。
/// Home は iOS のステータスバーを出さないので、電池を、ふだんのステータスバーの電池に近い高さ（ステータスバーの帯の縦の中心）に置く。
/// 帯の高さは、センサーの張り出しを含む Safe Area の上の高さ（切り欠きのない機種は、ふつうのステータスバーの 20pt）。
/// Dynamic Island の機種では、帯の中心は Dynamic Island の縦の中心とほぼそろう。帯の中に置くと、切り欠き（の少し広めの見込み）との
/// 横のあいだが batteryCutoutClearance に足りないとき（ノッチの機種。ノッチの右の「耳」は「100%」とマークには狭い）は、
/// 切り欠きの下に batteryCutoutClearance をあけて置く。右は画面の角の丸みを避ける。電池は日付の行とは別に、画面全体に広げた層に
/// 画面の座標で置き（HomeBatteryLayer。frame の中心に置く）、電池の場所を変えても日付・時計・タイムラインは動かない
struct HomeBatteryPlacement: Equatable {
    enum Mode: Equatable {
        /// ステータスバーの帯の縦の中心
        case statusBarBand
        /// 切り欠き（ノッチなど）の下
        case belowCutout
    }

    let shape: HomeTopShape
    let mode: Mode
    /// 電池の中心の、画面の上の端からの位置（pt）
    let centerY: CGFloat
    /// 電池の右の端と、画面の右の端のあいだ（pt）
    let trailingInset: CGFloat

    /// 電池の枠（画面の座標。size は電池の大きさ。既定は見込みの大きさ）
    func frame(screenWidth: CGFloat, size: CGSize = HomeLayoutMetrics.batteryEstimatedSize) -> CGRect {
        CGRect(x: screenWidth - trailingInset - size.width, y: centerY - size.height / 2, width: size.width, height: size.height)
    }

    /// 画面の大きさと Safe Area の上の高さから、電池の置き場所を決める
    static func make(screenWidth: CGFloat, safeAreaTop: CGFloat,
                     size: CGSize = HomeLayoutMetrics.batteryEstimatedSize) -> HomeBatteryPlacement {
        let shape = HomeTopShape.from(safeAreaTop: safeAreaTop)
        let halfHeight = size.height / 2
        let bandCenter = max(statusBarBandHeight(safeAreaTop: safeAreaTop) / 2,
                             HomeLayoutMetrics.batteryMinimumScreenTop + halfHeight)
        let band = HomeBatteryPlacement(shape: shape, mode: .statusBarBand, centerY: bandCenter,
                                        trailingInset: cornerSafeTrailingInset(screenWidth: screenWidth, top: bandCenter - halfHeight,
                                                                               shape: shape))
        guard let cutout = cutoutEstimate(screenWidth: screenWidth, safeAreaTop: safeAreaTop) else { return band }
        if band.frame(screenWidth: screenWidth, size: size).minX - cutout.maxX >= HomeLayoutMetrics.batteryCutoutClearance {
            return band
        }
        let top = cutout.maxY + HomeLayoutMetrics.batteryCutoutClearance
        return HomeBatteryPlacement(shape: shape, mode: .belowCutout, centerY: top + halfHeight,
                                    trailingInset: cornerSafeTrailingInset(screenWidth: screenWidth, top: top, shape: shape))
    }

    /// ステータスバーの帯の高さ：Dynamic Island・ノッチの機種は、ステータスバーを隠しても Safe Area の上に残るセンサーの張り出しの高さ。
    /// 切り欠きのない機種は、隠すと Safe Area の上が 0 になりうるので、ふつうのステータスバーの高さ
    static func statusBarBandHeight(safeAreaTop: CGFloat) -> CGFloat {
        HomeTopShape.from(safeAreaTop: safeAreaTop) == .flat ? HomeLayoutMetrics.flatStatusBarHeight : safeAreaTop
    }

    /// 切り欠き（Dynamic Island・ノッチ）の見込みの枠（画面の座標。実際より少し広く・下まで見る）。切り欠きのない機種は nil
    static func cutoutEstimate(screenWidth: CGFloat, safeAreaTop: CGFloat) -> CGRect? {
        let halfWidthRatio: CGFloat
        switch HomeTopShape.from(safeAreaTop: safeAreaTop) {
        case .dynamicIsland: halfWidthRatio = HomeLayoutMetrics.dynamicIslandHalfWidthRatio
        case .notch: halfWidthRatio = HomeLayoutMetrics.notchHalfWidthRatio
        case .flat: return nil
        }
        let halfWidth = screenWidth * halfWidthRatio
        return CGRect(x: screenWidth / 2 - halfWidth, y: 0, width: halfWidth * 2,
                      height: safeAreaTop * HomeLayoutMetrics.cutoutBottomRatio)
    }

    /// 電池の右上の角が、画面の角の丸み（の見込み）から batteryCornerClearance 以上内側になる右の余白（画面の左右の余白より小さくしない）。
    /// top は電池の上の端（画面の上の端から）。切り欠きのない機種は角が丸くないので、画面の左右の余白のまま
    static func cornerSafeTrailingInset(screenWidth: CGFloat, top: CGFloat, shape: HomeTopShape) -> CGFloat {
        let padding = HomeLayoutMetrics.horizontalPadding
        guard shape != .flat else { return padding }
        let radius = screenWidth * HomeLayoutMetrics.screenCornerRadiusRatio
        guard top < radius else { return padding }
        let rise = radius - max(0, top)
        let intrusion = radius - (radius * radius - rise * rise).squareRoot()
        return max(padding, intrusion + HomeLayoutMetrics.batteryCornerClearance)
    }

    /// ステータスバーを隠した Home での Safe Area の上の高さ（pt）。Dynamic Island・ノッチの機種はセンサーの張り出しの分が残り、
    /// ホームボタンの機種は 0 になりうる。画面全体に広げた電池の層（Safe Area を無視する GeometryReader）で測った値と、窓（UIKit）の値の
    /// 大きいほうを使う（どちらかが 0 で返っても、切り欠きのある機種を切り欠きなしと取り違えない）。おかしな値は使わない。
    /// 画面の中の位置（global の座標）には頼らない（2026-10-19 ビルド確認 #77 で、電池が計算した高さに来なかったため）
    static func topInset(swiftUI: CGFloat, window: CGFloat?) -> CGFloat {
        [swiftUI, window ?? 0].filter { $0.isFinite && $0 > 0 }.max() ?? 0
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
