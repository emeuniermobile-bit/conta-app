import SwiftUI

struct MainView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        TabView {
            StatusView()
                .tabItem { Label(theme.isZombie ? "Moi" : "Statut", systemImage: theme.isZombie ? "eye.trianglebadge.exclamationmark" : "waveform.path.ecg") }
            CityMapView()
                .tabItem { Label("Paris", systemImage: "map") }
            LabView()
                .tabItem { Label("Labo", systemImage: "flask") }
            LeaderboardView()
                .tabItem { Label("Classement", systemImage: "list.number") }
        }
        .toolbarBackground(theme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

/// En-tête commun : souche en cours et barre du Laboratoire.
struct SeasonHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        if let season = model.game?.season {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(season.strainName.uppercased())
                        .font(theme.font(12, weight: .bold)).tracking(2).foregroundStyle(theme.accent)
                    Spacer()
                    Text("Fin \(season.endsAt, format: .relative(presentation: .named))")
                        .font(theme.font(11)).foregroundStyle(theme.muted)
                }
                LabBar(progress: season.labProgress)
                HStack {
                    Text("Laboratoire \(Int(season.labProgress * 100)) %")
                    Spacer()
                    Text("Infectés \(Int(season.infectionRatio * 100)) %")
                }
                .font(theme.font(11)).foregroundStyle(theme.muted)
            }
        }
    }
}

struct LabBar: View {
    let progress: Double
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.muted.opacity(0.25))
                Rectangle().fill(theme.isZombie ? theme.muted : theme.safe)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}
