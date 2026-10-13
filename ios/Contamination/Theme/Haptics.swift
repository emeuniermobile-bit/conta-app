import UIKit

enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Survivant : battement sec. Zombie : pulsation lente et lourde.
    static func stateChanged(to state: PlayerState) {
        let generator = UIImpactFeedbackGenerator(style: state == .zombie ? .heavy : .rigid)
        generator.prepare()
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + (state == .zombie ? 0.6 : 0.18)) {
            generator.impactOccurred(intensity: 0.7)
        }
    }
}
