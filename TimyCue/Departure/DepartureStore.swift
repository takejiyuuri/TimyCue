import CoreLocation
import Foundation
import Observation

/// 推奨出発時刻の計算と、その結果（第 5 段階。追加仕様書 §8・§45）。ホーム（あとで通知・Live Activity も）はここの見込みを見る。
/// 設定 ＞ 出発・移動（出発の余裕・自宅・最初の予定の出発地点・普段よく使う移動手段）と、確かめた場所の地点もここに持つ
@MainActor
@Observable
final class DepartureStore {
    private(set) var settings: DepartureSettings
    private(set) var placeBook: PlaceBook
    private(set) var estimates: [UUID: DepartureEstimate] = [:]
    /// 「普段よく使う移動手段」を聞いている（移動手段が「自動」の予定を初めて計算するとき、1 回だけ。2026-10-14 決定）
    private(set) var asksUsualTransport = false

    /// 見本の予定で動かすとき（画面写真・自動テスト）は計算しない（開発中の見込みで出す）
    let isEnabled: Bool
    let location: LocationProvider

    @ObservationIgnored private let travel: TravelTimeProviding
    @ObservationIgnored private let settingsFile: JSONFile<DepartureSettings>?
    @ObservationIgnored private let placeBookFile: JSONFile<PlaceBook>?
    @ObservationIgnored private var records: [UUID: Record] = [:]
    @ObservationIgnored private var running: Set<UUID> = []

    /// 前に計算したときの入力と結果。同じ入力なら 5 分たつまで計算し直さない
    private struct Record {
        var inputs: Inputs
        var calculatedAt: Date
        var usedLocation: CLLocation?
        /// いちばん新しい、計算できた推奨出発時刻と、それを計算した時刻
        var lastValid: Date?
        var lastValidAt: Date?
    }

    private struct Inputs: Equatable {
        var start: Date
        var placeKey: String
        var transport: TransportMode?
        var arrivalTargetMinutes: Int
        var settings: DepartureSettings
        var destination: SavedPlace?
        var origin: DeparturePlanner.Origin
    }

    init(isEnabled: Bool,
         location: LocationProvider,
         travel: TravelTimeProviding = MapKitTravelTime(),
         settingsFile: JSONFile<DepartureSettings>? = JSONFile(url: JSONFile<DepartureSettings>.appSupportURL(named: "departure-settings.json"),
                                                               empty: DepartureSettings()),
         placeBookFile: JSONFile<PlaceBook>? = JSONFile(url: JSONFile<PlaceBook>.appSupportURL(named: "place-book.json"),
                                                        empty: PlaceBook())) {
        self.isEnabled = isEnabled
        self.location = location
        self.travel = travel
        self.settingsFile = settingsFile
        self.placeBookFile = placeBookFile
        settings = settingsFile?.load() ?? DepartureSettings()
        placeBook = placeBookFile?.load() ?? PlaceBook()
    }

    // MARK: - 見込み

    /// その予定の推奨出発時刻の見込み
    func estimate(for event: CalendarEvent) -> DepartureEstimate {
        guard isEnabled else { return .development(for: event) }
        guard HomeSchedule.hasPlace(event) else { return .notNeeded }
        return estimates[event.id] ?? .pending
    }

    /// 計算し直す。ホームを開いたとき・1 分ごと・前面に戻ったとき・予定が変わったときに呼ぶ。
    /// 5 分たった・入力（場所・移動手段・予定時刻・到着目標・設定・起点）が変わった・現在地が大きく動いた予定だけ計算する。
    /// force なら全部すぐ計算する（2026-10-14 決定：5 分は定期の基本値。変わったときはすぐ）
    func refresh(events: [CalendarEvent], metadata: (UUID) -> TimyCueEventMetadata?, now: Date, force: Bool = false) {
        guard isEnabled else { return }
        let targets = DeparturePlanner.eventsToCalculate(in: events, now: now)
        let ids = Set(targets.map(\.id))
        for id in Array(estimates.keys) where !ids.contains(id) {
            estimates[id] = nil
            records[id] = nil
        }
        for event in targets where !running.contains(event.id) {
            let info = metadata(event.id)
            let origin = DeparturePlanner.origin(for: event, among: events, settings: settings, placeBook: placeBook,
                                                 lastDeparture: records[event.id]?.lastValid, now: now)
            let inputs = Inputs(start: HomeSchedule.startDate(of: event),
                                placeKey: PlaceBook.key(event.locationName ?? ""),
                                transport: DeparturePlanner.transport(for: info, settings: settings),
                                arrivalTargetMinutes: info?.arrivalTargetMinutes ?? TimyCueEventMetadata.defaultArrivalTargetMinutes,
                                settings: settings,
                                destination: placeBook.place(for: event.locationName),
                                origin: origin)
            if !force, let record = records[event.id], record.inputs == inputs,
               now.timeIntervalSince(record.calculatedAt) < TimeInterval(DeparturePlanner.recalculateIntervalMinutes * 60),
               !movedSignificantly(since: record.usedLocation, origin: origin) {
                continue
            }
            let fallback = DeparturePlanner.plannedOrigin(for: event, among: events, settings: settings, placeBook: placeBook)
            calculate(event.id, inputs: inputs, fallbackOrigin: fallback, now: now)
        }
    }

    private func movedSignificantly(since used: CLLocation?, origin: DeparturePlanner.Origin) -> Bool {
        guard origin == .currentLocation, let used, let latest = location.location else { return false }
        return latest.distance(from: used) >= DeparturePlanner.significantMoveMeters
    }

    private func calculate(_ id: UUID, inputs: Inputs, fallbackOrigin: SavedPlace?, now: Date) {
        // 場所が文字だけで地点が決まっていない（Q66）
        guard let destination = inputs.destination else {
            store(.unavailable(.placeUnconfirmed), for: id, inputs: inputs, now: now, usedLocation: nil)
            return
        }
        // 「自動」で、普段よく使う移動手段をまだ選んでいない（1 回だけ聞く）
        guard let transport = inputs.transport else {
            if !settings.askedUsualTransport { asksUsualTransport = true }
            store(.unavailable(.transportNotChosen), for: id, inputs: inputs, now: now, usedLocation: nil)
            return
        }
        // 固定の起点がなく、予定開始の 4 時間前より前：まだ計算しない
        if inputs.origin == .notYet {
            store(.pending, for: id, inputs: inputs, now: now, usedLocation: nil)
            return
        }
        running.insert(id)
        let travel = travel
        Task { @MainActor in
            defer { self.running.remove(id) }
            var usedLocation: CLLocation?
            let from: CLLocationCoordinate2D
            switch inputs.origin {
            case .place(let place):
                from = place.coordinate
            case .currentLocation:
                if let current = await self.location.currentLocation() {
                    usedLocation = current
                    from = current.coordinate
                } else if let fallbackOrigin {
                    // 現在地が取れないときは、前の予定・自宅からの計算を目安として続ける（追加仕様書 §32.1）
                    from = fallbackOrigin.coordinate
                } else {
                    self.store(.unavailable(.failed), for: id, inputs: inputs, now: now, usedLocation: nil)
                    return
                }
            case .notYet:
                return
            }
            let result: DepartureEstimate
            do {
                let departure = try await DeparturePlanner.recommendedDeparture(
                    from: from, to: destination.coordinate, transport: transport, start: inputs.start,
                    arrivalTargetMinutes: inputs.arrivalTargetMinutes, margin: inputs.settings.marginLevel, now: now, travel: travel)
                result = .available(departure)
            } catch TravelTimeError.transitUnavailable {
                result = .unavailable(.transitUnavailable)
            } catch TravelTimeError.bicycleUnsupported {
                result = .unavailable(.bicycleUnsupported)
            } catch {
                result = .unavailable(.failed)
            }
            self.store(result, for: id, inputs: inputs, now: now, usedLocation: usedLocation)
        }
    }

    private func store(_ estimate: DepartureEstimate, for id: UUID, inputs: Inputs, now: Date, usedLocation: CLLocation?) {
        let previous = records[id]
        var lastValid = previous?.lastValid
        var lastValidAt = previous?.lastValidAt
        var shown = estimate
        switch estimate {
        case .available(let departure):
            lastValid = departure
            lastValidAt = now
        case .unavailable(.failed), .unavailable(.transitUnavailable):
            // 一度計算できたあとの一時的な失敗は、行き先と移動手段が同じなら 15 分まで前の値を使い続ける（追加仕様書 §25.6）
            if let lastValid, let lastValidAt, let previous,
               previous.inputs.destination == inputs.destination, previous.inputs.transport == inputs.transport,
               now.timeIntervalSince(lastValidAt) < TimeInterval(DeparturePlanner.keepLastValidMinutes * 60) {
                shown = .available(lastValid)
            }
        default:
            break
        }
        estimates[id] = shown
        records[id] = Record(inputs: inputs, calculatedAt: now, usedLocation: usedLocation,
                             lastValid: lastValid, lastValidAt: lastValidAt)
    }

    // MARK: - 設定 ＞ 出発・移動

    func setMarginLevel(_ level: DepartureMath.MarginLevel) {
        settings.marginLevel = level
        saveSettings()
    }

    /// 自宅を登録する（名前は初めから「自宅」。spec Q42-2）。nil で登録を消す
    func setHome(_ place: SavedPlace?) {
        settings.home = place
        saveSettings()
    }

    func setFirstEventOrigin(_ origin: FirstEventOrigin?) {
        settings.firstEventOrigin = origin
        saveSettings()
    }

    func setUsualTransport(_ transport: TransportMode?) {
        settings.usualTransport = transport
        settings.askedUsualTransport = true
        asksUsualTransport = false
        saveSettings()
    }

    /// ホームの「普段よく使う移動手段を選んでください」を押したとき、もう一度聞く
    func askUsualTransport() {
        asksUsualTransport = true
    }

    /// 「普段よく使う移動手段」を選ばずに閉じた（もう自分からは聞かない。設定で選べる）
    func dismissUsualTransportQuestion() {
        settings.askedUsualTransport = true
        asksUsualTransport = false
        saveSettings()
    }

    /// 場所の文字に、確かめた地点を結び付ける（Q66。一度確定した対応は覚えておく：追加仕様書 §23.1）
    func confirmPlace(_ place: SavedPlace, for text: String) {
        placeBook.confirm(place, for: text)
        try? placeBookFile?.save(placeBook)
    }

    private func saveSettings() {
        try? settingsFile?.save(settings)
    }
}
