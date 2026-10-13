import SwiftUI

/// Inscription et connexion par numéro de téléphone (un compte par numéro).
struct AuthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("CENTRE DE CRISE — PARIS")
                    .font(theme.font(11, weight: .semibold)).tracking(3).foregroundStyle(theme.muted)
                GlitchText(text: "CONTAMINATION", size: 34, weight: .heavy)
                Text("Une épidémie se propage dans la ville quand les gens se croisent. Tu commences survivant.")
                    .font(theme.font(14)).foregroundStyle(theme.text.opacity(0.8))
            }

            Panel(title: codeSent ? "Code reçu par SMS" : "Identification") {
                if codeSent {
                    TextField("123456", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(theme.font(28, weight: .bold))
                        .foregroundStyle(theme.text)
                    Button("Entrer") {
                        Task { _ = await model.verify(phone: normalizedPhone, code: code) }
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(code.count < 6 || model.busy)
                    Button("Changer de numéro") { codeSent = false; code = "" }
                        .buttonStyle(ActionButtonStyle(prominent: false))
                } else {
                    TextField("06 12 34 56 78", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(theme.font(24, weight: .bold))
                        .foregroundStyle(theme.text)
                    Button("Recevoir un code") {
                        Task { codeSent = await model.sendCode(to: normalizedPhone) }
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(normalizedPhone.count < 12 || model.busy)
                }
            }
            Text("Un compte par numéro de téléphone. Ton numéro n'est jamais montré aux autres joueurs.")
                .font(theme.font(11)).foregroundStyle(theme.muted)
            Spacer()
        }
        .padding(24)
    }

    /// « 06 12 34 56 78 » → « +33612345678 ».
    private var normalizedPhone: String {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("+") { return digits }
        if digits.hasPrefix("0") { return "+33" + digits.dropFirst() }
        return "+33" + digits
    }
}
