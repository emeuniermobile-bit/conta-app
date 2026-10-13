import SwiftUI

/// Silhouette avec masque à gaz ; se transforme quand le joueur devient zombie.
struct AvatarView: View {
    let avatar: Avatar
    var state: PlayerState = .survivor
    var size: CGFloat = 96

    var body: some View {
        let color = state == .zombie ? Color.rgb(0x7A8F5A) : Color(hex: avatar.color)
        ZStack {
            // Épaules
            Capsule()
                .fill(Color.rgb(0x1B262E))
                .frame(width: size * 0.95, height: size * 0.5)
                .offset(y: size * 0.42)
            // Tête
            Circle()
                .fill(state == .zombie ? Color.rgb(0x3E4A33) : Color.rgb(0x26343D))
                .frame(width: size * 0.62)
                .offset(y: -size * 0.08)
            mask(color: color)
                .offset(y: -size * 0.02)
            if state == .zombie {
                // Masque arraché, yeux rouges.
                HStack(spacing: size * 0.14) {
                    Circle().fill(Color.rgb(0xFF1E1E)).frame(width: size * 0.07)
                    Circle().fill(Color.rgb(0xFF1E1E)).frame(width: size * 0.07)
                }
                .offset(y: -size * 0.14)
                .shadow(color: .red, radius: 4)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(state == .zombie ? Color.rgb(0xFF1E1E) : color.opacity(0.7), lineWidth: 2))
        .rotationEffect(.degrees(state == .zombie ? -6 : 0))
    }

    @ViewBuilder
    private func mask(color: Color) -> some View {
        let eye = Circle().fill(Color.black.opacity(0.85)).overlay(Circle().stroke(color, lineWidth: size * 0.02))
        VStack(spacing: size * 0.02) {
            switch avatar.mask {
            case .visor:
                Capsule().fill(Color.black.opacity(0.85)).overlay(Capsule().stroke(color, lineWidth: size * 0.02))
                    .frame(width: size * 0.42, height: size * 0.14)
            default:
                HStack(spacing: size * 0.08) {
                    eye.frame(width: size * 0.15)
                    eye.frame(width: size * 0.15)
                }
            }
            switch avatar.mask {
            case .filter:
                HStack(spacing: size * 0.12) {
                    Circle().fill(color).frame(width: size * 0.14)
                    Circle().fill(color).frame(width: size * 0.14)
                }
            case .plague:
                Triangle().fill(color).frame(width: size * 0.16, height: size * 0.2)
            default:
                Circle().fill(color).frame(width: size * 0.18)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: size * 0.015).padding(size * 0.03))
            }
        }
        .opacity(state == .zombie ? 0.35 : 1)
        .rotationEffect(.degrees(state == .zombie ? 18 : 0))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
