import SwiftUI
import UserNotifications

@main
struct ContaminationApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.didBecomeActive() } }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // iOS relance l'appli en arrière-plan lors d'un déplacement significatif :
        // il faut réarmer la localisation tout de suite.
        Task { @MainActor in LocationReporter.shared.start() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.didRegister(deviceToken: deviceToken)
    }

    // Appli ouverte : on affiche quand même l'alerte, et on rafraîchit l'état.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        NotificationCenter.default.post(name: .gameStateMayHaveChanged, object: nil)
        return [.banner, .sound]
    }
}

extension Notification.Name {
    static let gameStateMayHaveChanged = Notification.Name("gameStateMayHaveChanged")
}
