import SwiftUI

struct StatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @ObservedObject private var location = LocationReporter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SeasonHeader()
                if let player = model.game?.player {
                    identity(player)
                    switch player.state {
                    case .survivor: survivorPanel(player)
                    case .incubating: incubationPanel(player)
                    case .zombie: zombiePanel(player)
                    }
                    if !location.hasBackgroundAccess {
                        reducedModeNotice
                    }
                    encountersPanel
                }
                Button("Se déconnecter") { Task { await model.signOut() } }
                    .buttonStyle(ActionButtonStyle(prominent: false))
                    .padding(.top, 24)
            }
            .padding(20)
        }
        .refreshable { await model.refresh() }
    }

    private func identity(_ player: Player) -> some View {
        HStack(spacing: 16) {
            AvatarView(avatar: player.avatar, state: player.state, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                GlitchText(text: player.displayName ?? "—", size: 22, weight: .bold)
                Text(stateLabel(player.state))
                    .font(theme.font(12, weight: .bold)).tracking(2)
                    .foregroundStyle(player.state == .survivor ? theme.safe : theme.danger)
            }
        }
    }

    private func stateLabel(_ state: PlayerState) -> String {
        switch state {
        case .survivor: "SURVIVANT"
        case .incubating: "INFECTÉ — INCUBATION"
        case .zombie: "ZOMBIE"
        }
    }

    private func survivorPanel(_ player: Player) -> some View {
        Panel(title: "État sanitaire") {
            Text("Aucune infection détectée.").font(theme.font(15)).foregroundStyle(theme.text)
            if let mask = player.maskUntil {
                Label("Masque actif jusqu'à \(mask.formatted(date: .omitted, time: .shortened))", systemImage: "facemask")
                    .font(theme.font(13)).foregroundStyle(theme.accent)
            } else if (model.game?.quantity(.masque) ?? 0) > 0 {
                Button("Mettre un masque") { Task { await model.useMask() } }
                    .buttonStyle(ActionButtonStyle(prominent: false))
            } else {
                Text("Aucun masque. Fabrique-en un au Labo.").font(theme.font(12)).foregroundStyle(theme.muted)
            }
        }
    }

    private func incubationPanel(_ player: Player) -> some View {
        Panel(title: "Infection détectée") {
            if let place = player.infectedPlace, let at = player.infectedAt {
                GlitchText(text: "\(place), \(at.formatted(date: .omitted, time: .shortened))", size: 15)
            }
            if let transform = player.transformAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, transform.timeIntervalSince(context.date))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRANSFORMATION DANS").font(theme.font(11, weight: .semibold)).foregroundStyle(theme.muted)
                        Text(Duration.seconds(left).formatted(.time(pattern: .hourMinuteSecond)))
                            .font(theme.font(44, weight: .heavy))
                            .foregroundStyle(theme.danger)
                            .contentTransition(.numericText())
                    }
                }
            }
            if (model.game?.quantity(.antidote) ?? 0) > 0 {
                Button("Injecter l'antidote") { Task { await model.useAntidote() } }
                    .buttonStyle(ActionButtonStyle())
            } else {
                Text("Fabrique un antidote au Labo avant la fin du compte à rebours.")
                    .font(theme.font(12)).foregroundStyle(theme.text.opacity(0.8))
            }
        }
    }

    private func zombiePanel(_ player: Player) -> some View {
        Panel(title: "Instinct") {
            GlitchText(text: "Ils sont partout. Je les sens passer.", size: 15)
            HStack(alignment: .firstTextBaseline) {
                Text("\(player.contaminations)").font(theme.font(44, weight: .heavy)).foregroundStyle(theme.accent)
                Text("contaminations cette saison").font(theme.font(12)).foregroundStyle(theme.muted)
            }
            Text("Chaque survivant qui reste près de moi plus de 2 minutes peut tomber. Je n'ai qu'à vivre ma vie.")
                .font(theme.font(12)).foregroundStyle(theme.text.opacity(0.8))
        }
    }

    private var reducedModeNotice: some View {
        Panel(title: "Mode réduit") {
            Text("Sans la localisation « Toujours », tes rencontres ne comptent que quand l'appli est ouverte.")
                .font(theme.font(12)).foregroundStyle(theme.text.opacity(0.8))
            Button("Ouvrir les réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(ActionButtonStyle(prominent: false))
        }
    }

    @ViewBuilder
    private var encountersPanel: some View {
        if !model.encounters.isEmpty {
            Panel(title: "Journal des rencontres") {
                ForEach(model.encounters.prefix(8)) { e in
                    HStack {
                        Image(systemName: e.infected ? "exclamationmark.triangle.fill" : "checkmark.shield")
                            .foregroundStyle(e.infected ? theme.danger : theme.safe)
                        Text(e.place).font(theme.font(13)).foregroundStyle(theme.text)
                        Spacer()
                        Text(e.occurredAt.formatted(date: .omitted, time: .shortened))
                            .font(theme.font(12)).foregroundStyle(theme.muted)
                    }
                }
            }
        }
    }
}
