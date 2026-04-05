import CoreLocation

final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastPlacemark: String?
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
    }

    /// 현재 위치의 스냅샷 반환
    func currentChunkLocation() -> ChunkLocation? {
        guard let loc = lastLocation else { return nil }
        return ChunkLocation(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            placemark: lastPlacemark
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location

        // 역지오코딩 (동/구 수준)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let place = placemarks?.first else { return }
            let parts = [place.locality, place.subLocality].compactMap { $0 }
            self?.lastPlacemark = parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}
