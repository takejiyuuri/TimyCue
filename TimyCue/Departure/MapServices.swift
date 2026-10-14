import CoreLocation
import Foundation
import MapKit

/// 地図から得た移動時間
struct TravelTime: Equatable {
    /// 所要時間（秒）
    let seconds: TimeInterval
    /// 公共交通のときの、起点を出る時刻（到着の時刻を決めて便を探したとき）
    let departure: Date?
}

enum TravelTimeError: Error, Equatable {
    case transitUnavailable
    case bicycleUnsupported
    case failed
}

/// 移動時間を出すもの。将来 MapKit 以外の公共交通のデータ源を足せるよう、差し替えられるようにしておく（追加仕様書 §27・Q67）
protocol TravelTimeProviding {
    /// arrival を渡すと、その時刻までに着く便・経路で（公共交通）、departure を渡すとその時刻に出るとして（車・徒歩・自転車）計算する
    func travelTime(from origin: CLLocationCoordinate2D,
                    to destination: CLLocationCoordinate2D,
                    transport: TransportMode,
                    departure: Date?,
                    arrival: Date?) async throws -> TravelTime
}

/// MapKit の移動時間（追加仕様書 §8.2）。自転車は MapKit の自転車ルートを使える iOS だけ。
/// 使えない iOS では徒歩のルートから換算せず、計算できない扱い（2026-10-14 決定）
struct MapKitTravelTime: TravelTimeProviding {
    func travelTime(from origin: CLLocationCoordinate2D,
                    to destination: CLLocationCoordinate2D,
                    transport: TransportMode,
                    departure: Date?,
                    arrival: Date?) async throws -> TravelTime {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        switch transport {
        case .car:
            request.transportType = .automobile
        case .walk:
            request.transportType = .walking
        case .publicTransit:
            request.transportType = .transit
        case .bicycle:
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                request.transportType = .cycling
            } else {
                throw TravelTimeError.bicycleUnsupported
            }
            #else
            throw TravelTimeError.bicycleUnsupported
            #endif
        case .auto:
            // 「自動」は、計算の前に手段を決めてから渡す
            throw TravelTimeError.failed
        }
        if let arrival {
            request.arrivalDate = arrival
        } else if let departure {
            request.departureDate = departure
        }
        do {
            let response = try await MKDirections(request: request).calculateETA()
            return TravelTime(seconds: response.expectedTravelTime, departure: response.expectedDepartureDate)
        } catch {
            throw transport == .publicTransit ? TravelTimeError.transitUnavailable : TravelTimeError.failed
        }
    }
}

/// 場所の候補（「場所を確認」・自宅の登録。Q66）
struct PlaceCandidate: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double

    func savedPlace(named name: String? = nil) -> SavedPlace {
        SavedPlace(name: name ?? self.name, address: address, latitude: latitude, longitude: longitude)
    }
}

/// 場所の文字から地点の候補を探す（MapKit の検索）
enum PlaceSearch {
    /// 出す候補の数（仮）
    static let maxCandidates = 15

    static func search(_ text: String, near: CLLocationCoordinate2D?) async -> [PlaceCandidate] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let near {
            request.region = MKCoordinateRegion(center: near, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(maxCandidates).map { item in
            let coordinate = item.placemark.coordinate
            return PlaceCandidate(name: item.name ?? query,
                                  address: item.placemark.title,
                                  latitude: coordinate.latitude,
                                  longitude: coordinate.longitude)
        }
    }
}

extension SavedPlace {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
