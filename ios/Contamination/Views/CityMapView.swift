import MapKit
import SwiftUI

/// Carte de Paris par arrondissement : zones vertes, disputées, rouges.
/// Uniquement des agrégats ; jamais de joueur individuel.
struct CityMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var pulse = false
    @State private var selected: ArrondissementStatus?

    private static let shapes = ArrondissementShape.loadAll()
    private static let paris = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.8575, longitude: 2.3460),
        span: MKCoordinateSpan(latitudeDelta: 0.13, longitudeDelta: 0.17))

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(initialPosition: .region(Self.paris)) {
                ForEach(Self.shapes) { shape in
                    let tint = color(for: status(of: shape.code))
                    ForEach(shape.rings.indices, id: \.self) { i in
                        MapPolygon(coordinates: shape.rings[i])
                            .foregroundStyle(tint.opacity(fillOpacity(for: shape.code)))
                            .stroke(tint.opacity(0.9), lineWidth: 1)
                    }
                    Annotation("", coordinate: shape.center, anchor: .center) {
                        Text(shape.code == 1 ? "1er" : "\(shape.code)e")
                            .font(theme.font(11, weight: .bold))
                            .foregroundStyle(theme.text)
                            .onTapGesture { selected = model.city.first { $0.code == shape.code } }
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .colorScheme(.dark)
            .saturation(theme.isZombie ? 0.2 : 0.6)

            VStack(spacing: 10) {
                if let selected {
                    detail(selected)
                }
                legend
            }
            .padding(12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: theme.isZombie ? 1.6 : 2.4).repeatForever()) { pulse = true }
        }
    }

    private func status(of code: Int) -> ArrondissementStatus.Status {
        model.city.first { $0.code == code }?.status ?? .unknown
    }

    private func color(for status: ArrondissementStatus.Status) -> Color {
        switch status {
        case .green: theme.safe
        case .contested: .rgb(0xFFB020)
        case .red: theme.danger
        case .unknown: theme.muted
        }
    }

    /// Côté zombie, les zones infectées pulsent.
    private func fillOpacity(for code: Int) -> Double {
        let base = status(of: code) == .unknown ? 0.08 : 0.28
        guard status(of: code) == .red else { return base }
        return pulse ? base + (theme.isZombie ? 0.3 : 0.12) : base
    }

    private func detail(_ a: ArrondissementStatus) -> some View {
        Panel(title: "Paris \(a.label) — \(a.name)") {
            if let ratio = a.infectionRatio, let players = a.activePlayers {
                Text("\(Int(ratio * 100)) % d'infectés parmi \(players) joueurs actifs")
                    .font(theme.font(13)).foregroundStyle(theme.text)
            } else {
                Text("Pas assez de joueurs pour publier des chiffres.")
                    .font(theme.font(13)).foregroundStyle(theme.muted)
            }
        }
        .onTapGesture { selected = nil }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.green, "Sain")
            legendItem(.contested, "Disputé")
            legendItem(.red, theme.isZombie ? "À nous" : "Tombé")
            legendItem(.unknown, "Inconnu")
        }
        .font(theme.font(11))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.surface.opacity(0.9), in: Capsule())
    }

    private func legendItem(_ status: ArrondissementStatus.Status, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color(for: status)).frame(width: 8)
            Text(label).foregroundStyle(theme.text)
        }
    }
}

/// Contours des arrondissements, embarqués dans l'appli (Resources/arrondissements.geojson).
struct ArrondissementShape: Identifiable {
    let code: Int
    let rings: [[CLLocationCoordinate2D]]
    let center: CLLocationCoordinate2D
    var id: Int { code }

    static func loadAll() -> [ArrondissementShape] {
        guard let url = Bundle.main.url(forResource: "arrondissements", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let features = try? MKGeoJSONDecoder().decode(data) as? [MKGeoJSONFeature]
        else { return [] }

        return features.compactMap { feature in
            guard let props = feature.properties,
                  let json = try? JSONSerialization.jsonObject(with: props) as? [String: Any],
                  let code = json["code"] as? Int
            else { return nil }
            let polygons = feature.geometry.flatMap { geometry -> [MKPolygon] in
                if let multi = geometry as? MKMultiPolygon { return multi.polygons }
                if let polygon = geometry as? MKPolygon { return [polygon] }
                return []
            }
            let rings = polygons.map { polygon in
                var coords = [CLLocationCoordinate2D](repeating: .init(), count: polygon.pointCount)
                polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
                return coords
            }
            guard let largest = polygons.max(by: { $0.pointCount < $1.pointCount }) else { return nil }
            return ArrondissementShape(code: code, rings: rings, center: largest.coordinate)
        }
        .sorted { $0.code < $1.code }
    }
}
