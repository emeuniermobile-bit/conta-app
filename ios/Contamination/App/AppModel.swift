import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        case signedOut
        case needsProfile
        case needsLocation
        case playing
    }

    private(set) var phase: Phase = .loading
    private(set) var game: GameState?
    private(set) var city: [ArrondissementStatus] = []
    private(set) var leaderboard: [LeaderboardEntry] = []
    private(set) var encounters: [EncounterLog] = []
    var toast: String?
    var busy = false

    private let backend = Backend.shared
    private var refreshTask: Task<Void, Never>?

    private var locationPrimerDone: Bool {
        get { UserDefaults.standard.bool(forKey: "locationPrimerDone") }
        set { UserDefaults.standard.set(newValue, forKey: "locationPrimerDone") }
    }

    var state: PlayerState { game?.player.state ?? .survivor }

    // MARK: - Cycle de vie

    func start() async {
        NotificationCenter.default.addObserver(forName: .gameStateMayHaveChanged, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }
        for await (_, session) in backend.client.auth.authStateChanges {
            if session == nil {
                game = nil
                phase = .signedOut
            } else {
                await refresh()
                await PushRegistrar.requestAuthorization()
            }
        }
    }

    func didBecomeActive() async {
        LocationReporter.shared.refresh()
        await refresh()
        startPeriodicRefresh()
    }

    private func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard UIApplication.shared.applicationState == .active else { continue }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        do {
            let previous = game?.player.state
            let state = try await backend.gameState()
            game = state
            if let previous, previous != state.player.state {
                Haptics.stateChanged(to: state.player.state)
            }
            updatePhase()
            if phase == .playing {
                async let map = backend.cityMap()
                async let board = backend.leaderboard()
                async let log = backend.myEncounters()
                city = (try? await map) ?? city
                leaderboard = (try? await board) ?? leaderboard
                encounters = (try? await log) ?? encounters
            }
        } catch {
            if phase == .loading { phase = .signedOut }
        }
    }

    private func updatePhase() {
        guard let game else { return }
        if game.player.displayName == nil {
            phase = .needsProfile
        } else if !locationPrimerDone {
            phase = .needsLocation
        } else {
            phase = .playing
        }
    }

    func finishLocationPrimer() {
        locationPrimerDone = true
        LocationReporter.shared.start()
        updatePhase()
    }

    // MARK: - Actions

    func sendCode(to phone: String) async -> Bool {
        await run { try await self.backend.sendCode(to: phone) }
    }

    func verify(phone: String, code: String) async -> Bool {
        await run { try await self.backend.verify(phone: phone, code: code) }
    }

    func setupProfile(name: String, avatar: Avatar) async {
        if await run({ try await self.backend.setupProfile(name: name, avatar: avatar) }) {
            await refresh()
        }
    }

    func claimRation() async {
        var received: [String: Int] = [:]
        if await run({ received = try await self.backend.claimDailyRation() }) {
            let total = received.values.reduce(0, +)
            toast = "Ration reçue : \(total) ingrédients."
            Haptics.success()
            await refresh()
        }
    }

    func craft(_ item: Item) async {
        if await run({ try await self.backend.craft(item) }) {
            toast = "\(item.name) fabriqué."
            Haptics.success()
            await refresh()
        }
    }

    func useMask() async {
        if await run({ try await self.backend.useMask() }) {
            toast = "Masque en place."
            await refresh()
        }
    }

    func useAntidote() async {
        if await run({ try await self.backend.useAntidote() }) {
            toast = "Antidote injecté. Infection enrayée."
            await refresh()
        }
    }

    func contribute(_ item: Item, quantity: Int) async {
        if await run({ try await self.backend.contributeToLab(item, quantity: quantity) }) {
            toast = "+\(item.labPoints * quantity) points de recherche."
            Haptics.success()
            await refresh()
        }
    }

    func signOut() async {
        _ = await run { try await self.backend.signOut() }
    }

    @discardableResult
    private func run(_ action: @escaping () async throws -> Void) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            try await action()
            return true
        } catch {
            toast = GameError.message(for: error)
            Haptics.error()
            return false
        }
    }
}
