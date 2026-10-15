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
    /// 出発時刻に添えて小さく出す知らせ（目安・古い値。2026-10-14 決定）
    private(set) var notes: [UUID: DepartureNote] = [:]
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
        /// その計算に使った現在地（現在地を起点にしたときだけ）
        var usedLocation: CLLocation?
        /// いちばん新しい、計算できた推奨出発時刻・地図の移動時間・計算した時刻と、そのときの起点・現在地
        var lastValid: Date?
        var lastValidAt: Date?
        var lastTravelSeconds: TimeInterval?
        var lastValidOrigin: DeparturePlanner.Origin?
        var lastValidLocation: CLLocation?

        init(inputs: Inputs, calculatedAt: Date) {
            self.inputs = inputs
            self.calculatedAt = calculatedAt
        }
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

    /// 出発時刻に添える小さな知らせ（「現在地を取得できないため、自宅からの目安です」「最新の交通情報を取得できません」）
    func note(for event: CalendarEvent) -> DepartureNote? {
        guard case .available = estimate(for: event) else { return nil }
        return notes[event.id]
    }

    /// 計算し直す。ホームを開いたとき・1 分ごと・前面に戻ったとき・予定が変わったときに呼ぶ。
    /// 5 分たった・入力（場所・移動手段・予定時刻・到着目標・設定・起点）が変わった・現在地が大きく動いた予定だけ計算する。
    /// force なら全部すぐ計算する（2026-10-14 決定：5 分は定期の基本値。変わったときはすぐ）
    func refresh(events: [CalendarEvent], metadata: (UUID) -> TimyCueEventMetadata?, now: Date, force: Bool = false) {
        guard isEnabled else { return }
        let targets = DeparturePlanner.eventsToCalculate(in: events, now: now)
        let ids = Set(targets.map(\.id))
        // 予定が過ぎた・変わったら、次の予定へずらす（計算の対象から外れた予定の結果は捨てる）
        for id in Array(estimates.keys) where !ids.contains(id) {
            estimates[id] = nil
            notes[id] = nil
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

    /// 前のルート計算に使った現在地から 300m 以上動いたか（2026-10-14 決定）
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
        // 起点・行き先・移動手段が同じなら、前に計算できた移動時間を 1 回目の概算に使う（2026-10-14 決定）
        let previous = records[id]
        let previousTravelSeconds = previous?.lastValidOrigin == inputs.origin
            && previous?.inputs.destination == inputs.destination && previous?.inputs.transport == inputs.transport
            ? previous?.lastTravelSeconds : nil
        Task { @MainActor in
            defer { self.running.remove(id) }
            var usedLocation: CLLocation?
            var note: DepartureNote?
            let from: CLLocationCoordinate2D
            switch inputs.origin {
            case .place(let place):
                from = place.coordinate
            case .currentLocation:
                if let current = await self.location.currentLocation() {
                    usedLocation = current
                    from = current.coordinate
                } else if let fallbackOrigin {
                    // 現在地が取れないときは、前の予定・自宅からの計算を目安として続け、目安だと小さく知らせる（追加仕様書 §32.1・2026-10-14 決定）
                    from = fallbackOrigin.coordinate
                    note = .fallbackOrigin(fallbackOrigin.name)
                } else {
                    self.store(.unavailable(.failed), for: id, inputs: inputs, now: now, usedLocation: nil)
                    return
                }
            case .notYet:
                return
            }
            do {
                let result = try await DeparturePlanner.recommendedDeparture(
                    from: from, to: destination.coordinate, transport: transport, start: inputs.start,
                    arrivalTargetMinutes: inputs.arrivalTargetMinutes, margin: inputs.settings.marginLevel, now: now,
                    previousTravelSeconds: previousTravelSeconds, travel: travel)
                self.store(.available(result.departure), note: note, travelSeconds: result.travelSeconds,
                           for: id, inputs: inputs, now: now, usedLocation: usedLocation)
            } catch TravelTimeError.transitUnavailable {
                self.store(.unavailable(.transitUnavailable), for: id, inputs: inputs, now: now, usedLocation: usedLocation)
            } catch TravelTimeError.bicycleUnavailable {
                self.store(.unavailable(.bicycleUnavailable), for: id, inputs: inputs, now: now, usedLocation: usedLocation)
            } catch {
                self.store(.unavailable(.failed), for: id, inputs: inputs, now: now, usedLocation: usedLocation)
            }
        }
    }

    private func store(_ estimate: DepartureEstimate,
                       note: DepartureNote? = nil,
                       travelSeconds: TimeInterval? = nil,
                       for id: UUID,
                       inputs: Inputs,
                       now: Date,
                       usedLocation: CLLocation?) {
        var record = records[id] ?? Record(inputs: inputs, calculatedAt: now)
        var shown = estimate
        var shownNote = note
        switch estimate {
        case .available(let departure):
            record.lastValid = departure
            record.lastValidAt = now
            record.lastTravelSeconds = travelSeconds
            record.lastValidOrigin = inputs.origin
            record.lastValidLocation = usedLocation
        case .unavailable(.failed), .unavailable(.transitUnavailable), .unavailable(.bicycleUnavailable):
            // 一度計算できたあとの一時的な失敗は、起点・行き先・移動手段が同じ（現在地なら前のルート計算の地点から 300m 未満）なら、
            // 15 分まで前の値を使い、「最新の交通情報を取得できません」と小さく出す（追加仕様書 §25.6・2026-10-14 決定）
            if let lastValid = record.lastValid, let lastValidAt = record.lastValidAt,
               now.timeIntervalSince(lastValidAt) < TimeInterval(DeparturePlanner.keepLastValidMinutes * 60),
               record.inputs.destination == inputs.destination, record.inputs.transport == inputs.transport,
               originUnchanged(record, inputs: inputs, usedLocation: usedLocation) {
                shown = .available(lastValid)
                shownNote = .staleTraffic
            }
        default:
            break
        }
        record.inputs = inputs
        record.calculatedAt = now
        record.usedLocation = usedLocation
        records[id] = record
        estimates[id] = shown
        notes[id] = shownNote
    }

    /// 前に計算できたときと起点が実質同じか。現在地なら、前のルート計算に使った地点から 300m 未満
    private func originUnchanged(_ record: Record, inputs: Inputs, usedLocation: CLLocation?) -> Bool {
        guard let lastOrigin = record.lastValidOrigin, lastOrigin == inputs.origin else { return false }
        guard inputs.origin == .currentLocation else { return true }
        guard let before = record.lastValidLocation, let now = usedLocation ?? location.location else { return false }
        return now.distance(from: before) < DeparturePlanner.significantMoveMeters
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
