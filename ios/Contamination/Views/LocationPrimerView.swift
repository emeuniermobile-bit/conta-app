import SwiftUI

/// Explique la permission « Toujours » avant de la demander.
/// Sans elle, on joue en mode réduit (ration quotidienne, rencontres appli ouverte).
struct LocationPrimerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @ObservedObject private var location = LocationReporter.shared
    @State private var askedAlways = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlitchText(text: "LE VIRUS TE SUIT", size: 26, weight: .heavy)
                Text("Dans Contamination, tu peux être infecté dans le métro sans ouvrir l'appli. Pour ça, le centre de crise a besoin de savoir à peu près où tu passes.")
                    .font(theme.font(14)).foregroundStyle(theme.text)

                Panel(title: "Ce que le jeu garde") {
                    bullet("mappin.and.ellipse", "Une zone de 50 m, jamais ta position exacte.")
                    bullet("clock.arrow.circlepath", "Effacée au bout de 6 heures.")
                    bullet("eye.slash", "Personne ne voit où tu es : la carte ne montre que des arrondissements.")
                    bullet("battery.100", "Pas de GPS continu : seulement tes grands déplacements.")
                }

                Panel(title: "Sans « Toujours »") {
                    Text("Tu joues en mode réduit : ration quotidienne, fabrication, et rencontres seulement quand l'appli est ouverte.")
                        .font(theme.font(13)).foregroundStyle(theme.text.opacity(0.85))
                }

                switch location.authorization {
                case .notDetermined:
                    Button("Autoriser la localisation") { location.requestWhenInUse() }
                        .buttonStyle(ActionButtonStyle())
                case .authorizedWhenInUse where !askedAlways:
                    Button("Passer à « Toujours »") {
                        askedAlways = true
                        location.requestAlways()
                    }
                    .buttonStyle(ActionButtonStyle())
                    Button("Continuer en mode réduit") { model.finishLocationPrimer() }
                        .buttonStyle(ActionButtonStyle(prominent: false))
                default:
                    Button(location.hasBackgroundAccess ? "Entrer dans Paris" : "Continuer en mode réduit") {
                        model.finishLocationPrimer()
                    }
                    .buttonStyle(ActionButtonStyle())
                }
            }
            .padding(24)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(theme.font(13)).foregroundStyle(theme.text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(theme.accent)
        }
    }
}
