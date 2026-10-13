import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let theme = Theme(player: model.game?.player, now: context.date)
            ZStack {
                ThemedBackground()
                switch model.phase {
                case .loading:
                    ProgressView().tint(theme.accent)
                case .signedOut:
                    AuthView()
                case .needsProfile:
                    ProfileSetupView()
                case .needsLocation:
                    LocationPrimerView()
                case .playing:
                    MainView()
                }
            }
            .environment(\.theme, theme)
            .tint(theme.accent)
            .animation(.easeInOut(duration: 0.6), value: theme)
            .overlay(alignment: .top) { ToastView().environment(\.theme, theme) }
        }
    }
}

private struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        if let message = model.toast {
            Text(message)
                .font(theme.font(13, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(theme.surface, in: Capsule())
                .overlay(Capsule().stroke(theme.accent.opacity(0.6)))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(3))
                    model.toast = nil
                }
                .onTapGesture { model.toast = nil }
        }
    }
}
