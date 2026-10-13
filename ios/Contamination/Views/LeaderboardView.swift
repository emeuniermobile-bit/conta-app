import SwiftUI

/// Classement des meilleurs contaminateurs de la saison.
struct LeaderboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SeasonHeader()
                Panel(title: "Meilleurs contaminateurs") {
                    if model.leaderboard.isEmpty {
                        Text("Personne n'a encore contaminé. Pour l'instant.")
                            .font(theme.font(13)).foregroundStyle(theme.muted)
                    }
                    ForEach(model.leaderboard) { entry in
                        HStack {
                            Text(String(format: "%02d", entry.rank))
                                .font(theme.font(13, weight: .bold)).foregroundStyle(theme.muted)
                            Text(entry.displayName)
                                .font(theme.font(15, weight: entry.isMe ? .heavy : .regular))
                                .foregroundStyle(entry.isMe ? theme.accent : theme.text)
                            Spacer()
                            Text("\(entry.contaminations)")
                                .font(theme.font(15, weight: .bold)).foregroundStyle(theme.danger)
                        }
                    }
                }
            }
            .padding(20)
        }
        .refreshable { await model.refresh() }
    }
}
