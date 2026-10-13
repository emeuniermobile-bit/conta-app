import Foundation
import Supabase

/// Accès au serveur : toutes les actions de jeu passent par des fonctions RPC
/// (voir supabase/migrations). L'appli ne lit ni n'écrit aucune table directement.
final class Backend: Sendable {
    static let shared = Backend()

    let client: SupabaseClient

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlString = info["SupabaseURL"] as? String, let url = URL(string: urlString),
              let key = info["SupabaseAnonKey"] as? String, !key.isEmpty
        else {
            fatalError("SupabaseURL / SupabaseAnonKey manquants : voir ios/Config/Secrets.example.xcconfig")
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    // MARK: - Compte (un compte par numéro de téléphone)

    func sendCode(to phone: String) async throws {
        try await client.auth.signInWithOTP(phone: phone)
    }

    func verify(phone: String, code: String) async throws {
        try await client.auth.verifyOTP(phone: phone, token: code, type: .sms)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - Jeu

    func gameState() async throws -> GameState {
        try await call("get_game_state")
    }

    func cityMap() async throws -> [ArrondissementStatus] {
        try await call("get_city_map")
    }

    func leaderboard() async throws -> [LeaderboardEntry] {
        try await call("get_leaderboard")
    }

    func myEncounters() async throws -> [EncounterLog] {
        try await call("get_my_encounters")
    }

    func setupProfile(name: String, avatar: Avatar) async throws {
        struct Params: Encodable { let p_display_name: String; let p_avatar: Avatar }
        try await perform("setup_profile", Params(p_display_name: name, p_avatar: avatar))
    }

    func registerDevice(apnsToken: String?, sandbox: Bool, backgroundLocation: Bool?) async throws {
        struct Params: Encodable {
            let p_apns_token: String?
            let p_sandbox: Bool
            let p_background_location: Bool?
        }
        try await perform("register_device", Params(p_apns_token: apnsToken, p_sandbox: sandbox,
                                                    p_background_location: backgroundLocation))
    }

    func reportLocation(latitude: Double, longitude: Double, accuracy: Double,
                        recordedAt: Date, until: Date? = nil) async throws {
        struct Params: Encodable {
            let p_lat: Double
            let p_lng: Double
            let p_accuracy: Double
            let p_recorded_at: String
            let p_until: String?
        }
        let iso = ISO8601DateFormatter()
        try await perform("report_location", Params(p_lat: latitude, p_lng: longitude, p_accuracy: accuracy,
                                                    p_recorded_at: iso.string(from: recordedAt),
                                                    p_until: until.map(iso.string(from:))))
    }

    func claimDailyRation() async throws -> [String: Int] {
        try await call("claim_daily_ration")
    }

    func craft(_ item: Item, quantity: Int = 1) async throws {
        struct Params: Encodable { let p_item: String; let p_quantity: Int }
        try await perform("craft", Params(p_item: item.rawValue, p_quantity: quantity))
    }

    func useMask() async throws {
        try await perform("use_mask")
    }

    func useAntidote() async throws {
        try await perform("use_antidote")
    }

    func contributeToLab(_ item: Item, quantity: Int) async throws {
        struct Params: Encodable { let p_item: String; let p_quantity: Int }
        try await perform("contribute_to_lab", Params(p_item: item.rawValue, p_quantity: quantity))
    }

    // MARK: - RPC

    private struct NoParams: Encodable, Sendable {}

    private func call<T: Decodable>(_ function: String) async throws -> T {
        try await call(function, NoParams())
    }

    private func call<T: Decodable, P: Encodable & Sendable>(_ function: String, _ params: P) async throws -> T {
        let response = try await client.rpc(function, params: params).execute()
        return try JSONDecoder.game.decode(T.self, from: response.data)
    }

    private func perform(_ function: String) async throws {
        try await perform(function, NoParams())
    }

    private func perform<P: Encodable & Sendable>(_ function: String, _ params: P) async throws {
        _ = try await client.rpc(function, params: params).execute()
    }
}

extension JSONDecoder {
    /// Décode les réponses Postgres : clés snake_case, dates ISO 8601 avec microsecondes.
    static let game: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = PostgresDate.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "date invalide : \(string)")
            }
            return date
        }
        return decoder
    }()
}

enum PostgresDate {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Accepte « 2026-10-13T08:42:00.123456+00:00 » : la fraction de seconde est
    /// retirée avant l'analyse puis rajoutée, ISO8601DateFormatter ne gérant que 3 décimales.
    static func parse(_ string: String) -> Date? {
        var text = string.replacingOccurrences(of: " ", with: "T")
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let digitsEnd = text[dot...].dropFirst().firstIndex(where: { !$0.isNumber }) ?? text.endIndex
            fraction = Double("0" + text[dot..<digitsEnd]) ?? 0
            text.removeSubrange(dot..<digitsEnd)
        }
        return formatter.date(from: text)?.addingTimeInterval(fraction)
    }
}

/// Messages lisibles pour les erreurs levées par les fonctions SQL.
enum GameError {
    static func message(for error: Error) -> String {
        let text = String(describing: error)
        let known: [(String, String)] = [
            ("ration_already_claimed", "Ration déjà récupérée aujourd'hui. Reviens demain."),
            ("not_enough_items", "Il te manque des ingrédients."),
            ("zombies_cannot_craft", "Les zombies ne fabriquent rien."),
            ("zombies_cannot_research", "Le Laboratoire n'ouvre pas aux zombies."),
            ("mask_useless_now", "Trop tard pour un masque : tu es déjà infecté."),
            ("not_incubating", "Tu n'es pas infecté."),
            ("not_a_sample", "Cet objet ne sert pas d'échantillon."),
            ("no_active_season", "Aucune saison en cours."),
        ]
        return known.first { text.contains($0.0) }?.1 ?? "Liaison avec le centre de crise perdue. Réessaie."
    }
}
