import CoreLocation
import Foundation
import Observation

/// 現在地を取る（追加仕様書 §25.1）。許可は初めて現在地が要るときに求める（JIT。初めは「このAppの使用中」）。
/// 断られたら、自分から何度も求め直さない
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    /// いちばん新しい現在地
    private(set) var location: CLLocation? = nil
    /// 見本の予定で動かすとき（画面写真・自動テスト）は現在地を使わない（許可の画面を出さない）
    let isEnabled: Bool

    private let manager = CLLocationManager()
    @ObservationIgnored private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    /// ホームが前面の間、現在地の変化を受け取っているか
    @ObservationIgnored private var isWatching = false

    /// これより古い現在地は使わず、取り直す（秒。仮）
    static let freshSeconds: TimeInterval = 120

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        authorization = .notDetermined
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 現在地を 1 回取る。まだ聞いていなければ、ここで「このAppの使用中」の許可を求める。取れなければ nil
    func currentLocation() async -> CLLocation? {
        guard isEnabled else { return nil }
        // 現在地の変化を受け取っている間は、300m 動くたびに新しくなるので、手元のいちばん新しい現在地で足りる
        if isWatching, let location {
            return location
        }
        if let location, Date().timeIntervalSince(location.timestamp) < Self.freshSeconds {
            return location
        }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        default:
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
                // 受け取っている間は、次の知らせ（初めの 1 回はすぐ来る）を待つ
                if !isWatching { manager.requestLocation() }
            }
        }
    }

    /// ホームが前面の間だけ、現在地が 300m 動くたびに受け取る（前のルート計算の地点から動いたら計算し直すため）。
    /// 許可がまだなら何もしない（ここでは許可を求めない）
    func startWatching() {
        guard isEnabled else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.distanceFilter = DeparturePlanner.significantMoveMeters
            manager.startUpdatingLocation()
            isWatching = true
        default:
            break
        }
    }

    func stopWatching() {
        manager.stopUpdatingLocation()
        isWatching = false
    }

    private func finish(_ location: CLLocation?) {
        if let location { self.location = location }
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in self.finish(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            guard !self.waiters.isEmpty else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.finish(nil)
            default:
                break
            }
        }
    }
}
