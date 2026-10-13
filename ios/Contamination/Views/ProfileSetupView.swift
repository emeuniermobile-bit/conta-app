import SwiftUI

struct ProfileSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var name = ""
    @State private var avatar = Avatar.default

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlitchText(text: "FICHE SURVIVANT", size: 24, weight: .heavy)
                HStack {
                    Spacer()
                    AvatarView(avatar: avatar, size: 140)
                    Spacer()
                }
                Panel(title: "Nom de code") {
                    TextField("2 à 24 caractères", text: $name)
                        .font(theme.font(20, weight: .bold))
                        .foregroundStyle(theme.text)
                        .textInputAutocapitalization(.never)
                }
                Panel(title: "Masque") {
                    Picker("Masque", selection: $avatar.mask) {
                        ForEach(Avatar.MaskStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        ForEach(Avatar.palette, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 32)
                                .overlay(Circle().stroke(theme.text, lineWidth: avatar.color == hex ? 3 : 0))
                                .onTapGesture { avatar.color = hex }
                        }
                    }
                }
                Button("Rejoindre Paris") {
                    Task { await model.setupProfile(name: trimmed, avatar: avatar) }
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(!(2...24).contains(trimmed.count) || model.busy)
            }
            .padding(24)
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}
