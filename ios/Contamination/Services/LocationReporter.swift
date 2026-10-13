import CoreLocation
import UIKit

/// Envoie la position approximative au serveur.
///
/// Batterie : pas de GPS continu. On s'appuie sur les « changements de position
/// significatifs » d'iOS (environ 500 m) et sur les visites (arrivée / départ
/// d'un lieu), qui réveillent l'appli même fermée si la permission « Toujours »
/// est accordée. Appli ouverte, une position précise est demandée de temps en temps.
@MainActor
final class LocationReporter: NSObject, ObservableObject {
    static let shared = LocationReporter()

    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var lastSent: (location: CLLocation, at: Date)?

    var hasBackgroundAccess: Bool { authorization == .authorizedAlways }
    var hasAnyAccess: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    override private init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
    }

    /// Première étape : « Pendant l'utilisation ». iOS ne permet de proposer
    /// « Toujours » qu'ensuite (voir requestAlways).
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    /// À appeler au lancement, y compris quand iOS relance l'appli en arrière-plan.
    func start() {
        guard hasAnyAccess else { return }
        if hasBackgroundAccess {
            manager.allowsBackgroundLocationUpdates = true
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
        }
        manager.requestLocation()
    }

    /// Appli au premier plan : une position fraîche pour la carte et les rencontres.
    func refresh() {
        guard hasAnyAccess else { return }
        manager.requestLocation()
    }

    private func send(_ location: CLLocation, until: Date? = nil) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500 else { return }
        // Inutile d'envoyer deux fois le même point à quelques secondes d'intervalle.
        if until == nil, let last = lastSent,
           last.location.distance(from: location) < 50, location.timestamp.timeIntervalSince(last.at) < 120 {
            return
        }
        lastSent = (location, location.timestamp)

        // En arrière-plan, iOS laisse quelques secondes pour finir la requête.
        let task = UIApplication.shared.beginBackgroundTask(withName: "report-location")
        Task {
            defer { UIApplication.shared.endBackgroundTask(task) }
            try? await Backend.shared.reportLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                recordedAt: location.timestamp,
                until: until)
        }
    }
}

extension LocationReporter: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.start()
            try? await Backend.shared.registerDevice(apnsToken: nil, sandbox: PushRegistrar.isSandbox,
                                                     backgroundLocation: status == .authorizedAlways)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.send(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let location = CLLocation(coordinate: visit.coordinate, altitude: 0,
                                  horizontalAccuracy: visit.horizontalAccuracy, verticalAccuracy: -1,
                                  timestamp: visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate)
        let departure = visit.departureDate == .distantFuture ? nil : visit.departureDate
        Task { @MainActor in self.send(location, until: departure) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
