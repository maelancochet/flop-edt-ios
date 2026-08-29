import Foundation

/// Une semaine ISO 8601, telle que l'API FlOpEDT l'attend.
///
/// Ce type existe pour empêcher le bug de la v1, qui construisait les paramètres
/// `week` et `year` avec `component(.weekOfYear)` et `component(.year)`. Ces deux
/// champs sont incohérents à cheval sur le nouvel an : le lundi 29/12/2025
/// appartient à la semaine ISO 1 de **2026**, mais `.year` renvoie 2025. La v1
/// demandait donc la semaine 1 de 2025 et affichait un emploi du temps vide.
///
/// L'année stockée ici est toujours l'année ISO (`yearForWeekOfYear`).
public struct ISOWeek: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    /// Numéro de semaine ISO, de 1 à 53.
    public let week: Int
    /// Année ISO — celle du jeudi de la semaine, pas forcément celle du lundi.
    public let year: Int

    public init(week: Int, year: Int) {
        self.week = week
        self.year = year
    }

    /// La semaine ISO qui contient cette date.
    public init(containing date: Date) {
        let parts = FlopCalendar.iso.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        self.week = parts.weekOfYear ?? 1
        self.year = parts.yearForWeekOfYear ?? 1970
    }

    public static func current(now: Date = .now) -> ISOWeek {
        ISOWeek(containing: now)
    }

    /// Le lundi de cette semaine, à minuit.
    public var monday: Date {
        var parts = DateComponents()
        parts.weekOfYear = week
        parts.yearForWeekOfYear = year
        parts.weekday = 2 // 1 = dimanche, 2 = lundi
        guard let date = FlopCalendar.iso.date(from: parts) else {
            return FlopCalendar.iso.startOfDay(for: .now)
        }
        return FlopCalendar.iso.startOfDay(for: date)
    }

    /// Les sept jours de la semaine, du lundi au dimanche.
    ///
    /// Le week-end est inclus délibérément : la bande de dates en garde la place,
    /// et l'API accepte déjà les codes `sa` et `su`.
    public var days: [Date] {
        let start = monday
        return (0..<7).compactMap {
            FlopCalendar.iso.date(byAdding: .day, value: $0, to: start)
        }
    }

    public func date(of weekday: Weekday) -> Date? {
        FlopCalendar.iso.date(byAdding: .day, value: weekday.offsetFromMonday, to: monday)
    }

    public func contains(_ date: Date) -> Bool {
        ISOWeek(containing: date) == self
    }

    /// Décale de `count` semaines. Passe correctement les frontières d'année,
    /// y compris les années ISO à 53 semaines.
    public func advanced(by count: Int) -> ISOWeek {
        guard let shifted = FlopCalendar.iso.date(byAdding: .weekOfYear, value: count, to: monday) else {
            return self
        }
        return ISOWeek(containing: shifted)
    }

    /// Nombre de semaines à ajouter à `self` pour atteindre `other`.
    public func distance(to other: ISOWeek) -> Int {
        FlopCalendar.iso.dateComponents([.weekOfYear], from: monday, to: other.monday).weekOfYear ?? 0
    }

    public static func < (lhs: ISOWeek, rhs: ISOWeek) -> Bool {
        (lhs.year, lhs.week) < (rhs.year, rhs.week)
    }

    public var description: String { "S\(week)/\(year)" }
}
