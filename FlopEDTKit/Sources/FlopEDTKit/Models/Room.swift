import Foundation

/// `GET /rooms/room/?dept=`
///
/// `basicRooms` est la clé du calcul des salles libres : les salles se
/// chevauchent. Réserver `B101-B102` occupe B101 *et* B102, `1er Etage + B219`
/// en bloque sept d'un coup, et `Entretien` bloque B010, B115 et B005. Sans
/// cette table, le calcul est faux.
public struct Room: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let subroomOf: [Int]
    public let departments: [Int]
    public let isBasic: Bool
    public let basicRooms: [RoomRef]
}

/// `GET /fetch/unavailableroom/?dept=&week=&year=`
///
/// Indisponibilités hors cours : ménage, maintenance, réunions.
public struct RoomUnavailability: Codable, Hashable, Sendable {
    public let room: String
    public let day: Weekday
    /// Minutes depuis minuit.
    public let startTime: Int
    /// Durée en minutes.
    public let duration: Int
    public let value: Int

    public var endTime: Int { startTime + duration }
}
