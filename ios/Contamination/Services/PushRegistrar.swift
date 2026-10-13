import UIKit
import UserNotifications

/// Notifications d'alerte : demande d'autorisation et envoi du jeton APNs au serveur.
enum PushRegistrar {
    static var isSandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    @MainActor
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    static func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            try? await Backend.shared.registerDevice(apnsToken: token, sandbox: isSandbox, backgroundLocation: nil)
        }
    }
}
