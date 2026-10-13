import Foundation

enum PlayerState: String, Decodable {
    case survivor
    case incubating
    case zombie
}

struct Avatar: Codable, Equatable {
    var mask: MaskStyle
    var color: String

    enum MaskStyle: String, Codable, CaseIterable, Identifiable {
        case classic, visor, filter, plague
        var id: String { rawValue }
        var label: String {
            switch self {
            case .classic: "Classique"
            case .visor: "Visière"
            case .filter: "Double filtre"
            case .plague: "Bec"
            }
        }
    }

    static let `default` = Avatar(mask: .classic, color: "#2EE6D6")
    static let palette = ["#2EE6D6", "#F2F5F7", "#7CFF6B", "#FFB020", "#5B8CFF", "#FF5C8A"]
}

struct Player: Decodable {
    let id: UUID
    let displayName: String?
    let avatar: Avatar
    let state: PlayerState
    let infectedAt: Date?
    let infectedPlace: String?
    let transformAt: Date?
    let maskUntil: Date?
    let rationAvailable: Bool
    let contaminations: Int
    let cures: Int
    let labContribution: Int
    let arrondissement: Int?
}

struct Season: Decodable {
    let id: Int
    let strainName: String
    let startedAt: Date
    let endsAt: Date
    let labPoints: Int
    let labGoal: Int
    let activePlayers: Int
    let zombies: Int
    let infectionRatio: Double

    var labProgress: Double { min(1, Double(labPoints) / Double(max(labGoal, 1))) }
}

struct GameState: Decodable {
    let player: Player
    let inventory: [String: Int]
    let season: Season?
    let serverTime: Date

    func quantity(_ item: Item) -> Int { inventory[item.rawValue] ?? 0 }
}

struct ArrondissementStatus: Decodable, Identifiable {
    enum Status: String, Decodable {
        case green, contested, red, unknown
    }

    let code: Int
    let name: String
    let activePlayers: Int?
    let infectionRatio: Double?
    let status: Status

    var id: Int { code }
    var label: String { code == 1 ? "1er" : "\(code)e" }
}

struct LeaderboardEntry: Decodable, Identifiable {
    let rank: Int
    let displayName: String
    let contaminations: Int
    let isMe: Bool
    var id: String { "\(rank)-\(displayName)" }
}

struct EncounterLog: Decodable, Identifiable {
    let occurredAt: Date
    let place: String
    let infected: Bool
    let byGhost: Bool
    var id: Date { occurredAt }
}

/// Objets connus de l'appli ; la source de vérité reste la table public.items.
enum Item: String, CaseIterable, Identifiable {
    case tissu, filtre, alcool, plante, reactif, masque, antidote

    var id: String { rawValue }

    static let ingredients: [Item] = [.tissu, .filtre, .alcool, .plante, .reactif]

    var name: String {
        switch self {
        case .tissu: "Tissu"
        case .filtre: "Filtre à charbon"
        case .alcool: "Alcool médical"
        case .plante: "Plante médicinale"
        case .reactif: "Réactif"
        case .masque: "Masque"
        case .antidote: "Antidote"
        }
    }

    var symbol: String {
        switch self {
        case .tissu: "square.stack.3d.down.forward"
        case .filtre: "circle.hexagongrid"
        case .alcool: "drop"
        case .plante: "leaf"
        case .reactif: "testtube.2"
        case .masque: "facemask"
        case .antidote: "syringe"
        }
    }

    /// Points de recherche par unité déposée au Laboratoire.
    var labPoints: Int {
        switch self {
        case .tissu, .alcool: 1
        case .filtre, .plante: 2
        case .reactif: 3
        case .masque, .antidote: 0
        }
    }

    var recipe: [(Item, Int)] {
        switch self {
        case .masque: [(.tissu, 2), (.filtre, 1)]
        case .antidote: [(.plante, 2), (.alcool, 1), (.reactif, 1)]
        default: []
        }
    }
}
