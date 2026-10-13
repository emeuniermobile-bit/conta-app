import SwiftUI
import UIKit

/// Les deux visages de l'appli. Pendant l'incubation, l'interface glisse
/// progressivement du centre de crise (cyan) vers la corruption (rouge).
struct Theme: Equatable {
    /// 0 : survivant sain, 1 : zombie.
    let corruption: Double

    static let survivor = Theme(corruption: 0)
    static let zombie = Theme(corruption: 1)

    init(corruption: Double) {
        self.corruption = min(1, max(0, corruption))
    }

    init(player: Player?, now: Date = .now) {
        guard let player else { self.init(corruption: 0); return }
        switch player.state {
        case .survivor: self.init(corruption: 0)
        case .zombie: self.init(corruption: 1)
        case .incubating:
            // On démarre à 0,15 pour que l'infection se voie immédiatement.
            let total = player.transformAt.flatMap { end in player.infectedAt.map { end.timeIntervalSince($0) } } ?? 3 * 3600
            let left = player.transformAt.map { $0.timeIntervalSince(now) } ?? total
            self.init(corruption: 0.15 + 0.75 * (1 - left / max(total, 1)))
        }
    }

    var isZombie: Bool { corruption >= 1 }

    var background: Color { .mix(.rgb(0x090E12), .rgb(0x0A0000), corruption) }
    var surface: Color { .mix(.rgb(0x111B22), .rgb(0x1A0505), corruption) }
    var accent: Color { .mix(.rgb(0x2EE6D6), .rgb(0xFF1E1E), corruption) }
    var text: Color { .mix(.rgb(0xF2F5F7), .rgb(0xFFD6D6), corruption) }
    var muted: Color { .mix(.rgb(0x6B8794), .rgb(0x8A3A3A), corruption) }
    var danger: Color { .rgb(0xFF3B3B) }
    var safe: Color { .rgb(0x3DDC84) }

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.survivor
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Color {
    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x2EE6D6
        self = .rgb(value)
    }

    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = UIColor(a).rgba, cb = UIColor(b).rgba
        return Color(red: ca.r + (cb.r - ca.r) * t, green: ca.g + (cb.g - ca.g) * t,
                     blue: ca.b + (cb.b - ca.b) * t)
    }
}

private extension UIColor {
    var rgba: (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }
}

// MARK: - Corruption

/// Texte qui tremble pendant l'incubation et se déforme chez les zombies.
struct GlitchText: View {
    let text: String
    var size: CGFloat = 16
    var weight: Font.Weight = .regular
    @Environment(\.theme) private var theme

    var body: some View {
        if theme.corruption == 0 {
            Text(text).font(theme.font(size, weight: weight)).foregroundStyle(theme.text)
        } else {
            TimelineView(.periodic(from: .now, by: theme.isZombie ? 0.12 : 0.2)) { context in
                let seed = UInt64(context.date.timeIntervalSinceReferenceDate * 10)
                let jitter = theme.corruption * 2.5
                ZStack {
                    Text(text).foregroundStyle(theme.accent.opacity(0.5))
                        .offset(x: Self.noise(seed, 1) * jitter, y: Self.noise(seed, 2) * jitter * 0.5)
                    Text(corrupted(seed)).foregroundStyle(theme.text)
                }
                .font(theme.font(size, weight: weight))
            }
        }
    }

    /// Remplace quelques lettres par des glyphes voisins, proportionnellement à la corruption.
    private func corrupted(_ seed: UInt64) -> String {
        let swaps: [Character: Character] = ["a": "@", "e": "3", "i": "!", "o": "0", "s": "$", "t": "7",
                                             "A": "Λ", "E": "Ξ", "O": "Ø", "S": "§", "R": "Я", "N": "И"]
        let rate = theme.isZombie ? 0.18 : theme.corruption * 0.08
        return String(text.enumerated().map { index, char in
            guard let swap = swaps[char] else { return char }
            return Self.noise(seed &+ UInt64(index) &* 31, 7) * 0.5 + 0.5 < rate ? swap : char
        })
    }

    /// Bruit pseudo-aléatoire déterministe dans [-1, 1].
    static func noise(_ seed: UInt64, _ salt: UInt64) -> Double {
        var x = seed &* 6364136223846793005 &+ salt &* 1442695040888963407
        x ^= x >> 33
        x = x &* 0xff51afd7ed558ccd
        x ^= x >> 33
        return Double(x % 2000) / 1000 - 1
    }
}

/// Fond commun : grille de radar (survivant) ou bruit rouge qui pulse (zombie).
struct ThemedBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background
            Canvas { context, size in
                let step: CGFloat = 32
                var path = Path()
                var x: CGFloat = 0
                while x < size.width { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += step }
                context.stroke(path, with: .color(theme.accent.opacity(0.05)), lineWidth: 0.5)
            }
            if theme.corruption > 0 {
                TimelineView(.periodic(from: .now, by: 0.15)) { context in
                    let seed = UInt64(context.date.timeIntervalSinceReferenceDate * 7)
                    Canvas { ctx, size in
                        let lines = Int(3 + theme.corruption * 9)
                        for i in 0..<lines {
                            let y = (GlitchText.noise(seed, UInt64(i)) * 0.5 + 0.5) * size.height
                            let h = 1 + (GlitchText.noise(seed, UInt64(i + 50)) * 0.5 + 0.5) * 6 * theme.corruption
                            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: h)),
                                     with: .color(theme.accent.opacity(0.06 + 0.1 * theme.corruption)))
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(theme.font(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.accent.opacity(0.25), lineWidth: 1))
    }
}

struct ActionButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.font(14, weight: .bold))
            .textCase(.uppercase)
            .tracking(1)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .foregroundStyle(prominent ? theme.background : theme.accent)
            .background(prominent ? theme.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.accent, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}
