import SwiftUI

/// Ration quotidienne, fabrication et dépôt d'échantillons au Laboratoire mondial.
struct LabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SeasonHeader()
                if let game = model.game {
                    if game.player.state == .zombie {
                        zombieView(game)
                    } else {
                        rationPanel(game)
                        craftPanel(game)
                        inventoryPanel(game)
                    }
                }
            }
            .padding(20)
        }
        .refreshable { await model.refresh() }
    }

    private func rationPanel(_ game: GameState) -> some View {
        Panel(title: "Ration quotidienne") {
            if game.player.rationAvailable {
                Text("Le centre de crise a déposé ta ration du jour.").font(theme.font(13)).foregroundStyle(theme.text)
                Button("Récupérer") { Task { await model.claimRation() } }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(model.busy)
            } else {
                Text("Prochaine ration demain.").font(theme.font(13)).foregroundStyle(theme.muted)
            }
        }
    }

    private func craftPanel(_ game: GameState) -> some View {
        Panel(title: "Fabrication") {
            ForEach([Item.masque, .antidote]) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol).font(.title2).foregroundStyle(theme.accent).frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.name)  ×\(game.quantity(item))")
                            .font(theme.font(15, weight: .bold)).foregroundStyle(theme.text)
                        Text(item.recipe.map { "\($0.1) \($0.0.name.lowercased())" }.joined(separator: " · "))
                            .font(theme.font(11)).foregroundStyle(theme.muted)
                    }
                    Spacer()
                    Button("Fabriquer") { Task { await model.craft(item) } }
                        .buttonStyle(ActionButtonStyle(prominent: false))
                        .frame(width: 120)
                        .disabled(!canCraft(item, game) || model.busy)
                }
            }
        }
    }

    private func inventoryPanel(_ game: GameState) -> some View {
        Panel(title: "Ingrédients — dépôt au Laboratoire") {
            ForEach(Item.ingredients) { item in
                let quantity = game.quantity(item)
                HStack {
                    Image(systemName: item.symbol).foregroundStyle(theme.accent).frame(width: 24)
                    Text(item.name).font(theme.font(13)).foregroundStyle(theme.text)
                    Spacer()
                    Text("×\(quantity)").font(theme.font(13, weight: .bold)).foregroundStyle(theme.text)
                    Button {
                        Task { await model.contribute(item, quantity: 1) }
                    } label: {
                        Text("+\(item.labPoints) pt").font(theme.font(11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(quantity == 0 || model.busy)
                }
            }
            Text("Chaque échantillon rapproche Paris du remède universel. Ta contribution : \(game.player.labContribution) pts.")
                .font(theme.font(11)).foregroundStyle(theme.muted)
        }
    }

    private func zombieView(_ game: GameState) -> some View {
        Panel(title: "Le Laboratoire") {
            GlitchText(text: "Ils cherchent un remède. Qu'ils cherchent.", size: 15)
            Text("Plus je contamine, moins ils sont nombreux à alimenter leur barre. Si 90 % de la ville tombe, nous gagnons.")
                .font(theme.font(12)).foregroundStyle(theme.text.opacity(0.8))
        }
    }

    private func canCraft(_ item: Item, _ game: GameState) -> Bool {
        item.recipe.allSatisfy { game.quantity($0.0) >= $0.1 }
    }
}
