import Foundation

/// Les codes de jour de l'API FlOpEDT (`m`, `tu`, `w`, `th`, `f`, `sa`, `su`).
public enum Weekday: String, Codable, CaseIterable, Sendable, Comparable {
    case monday = "m"
    case tuesday = "tu"
    case wednesday = "w"
    case thursday = "th"
    case friday = "f"
    case saturday = "sa"
    case sunday = "su"

    /// Rang du jour dans une semaine ISO, le lundi valant 0.
    public var offsetFromMonday: Int {
        switch self {
        case .monday: 0
        case .tuesday: 1
        case .wednesday: 2
        case .thursday: 3
        case .friday: 4
        case .saturday: 5
        case .sunday: 6
        }
    }

    /// Le jour correspondant à une date.
    ///
    /// Passe par le décalage depuis le lundi ISO plutôt que par
    /// `component(.weekday)`, qui est numéroté à partir du dimanche et ne
    /// s'aligne sur l'ordre d'affichage que dans les locales où la semaine
    /// commence le dimanche. C'est précisément l'erreur de
    /// `HorizontalCalendar.swift:168`, qui décalait d'un jour la sélection sur
    /// tout appareil réglé en français.
    public init(date: Date) {
        let weekday = FlopCalendar.iso.component(.weekday, from: date)
        // ISO 8601 : 1 = dimanche … 7 = samedi. On ramène au lundi = 0.
        let offset = (weekday + 5) % 7
        self = Weekday.allCases[offset]
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.offsetFromMonday < rhs.offsetFromMonday
    }
}
