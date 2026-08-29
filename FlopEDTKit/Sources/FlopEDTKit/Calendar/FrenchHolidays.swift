import Foundation

/// Les jours fériés français, calculés hors ligne.
///
/// L'API FlOpEDT n'expose ni les fériés ni les vacances — vérifié sur l'ensemble
/// des 153 endpoints du schéma. Plutôt que d'appeler un service externe ou de
/// figer une liste de dates à remettre à jour chaque année, tout se déduit de la
/// date de Pâques : trois fériés sont mobiles, les huit autres sont fixes.
public struct FrenchHoliday: Hashable, Sendable {
    public let date: Date
    public let name: String
}

public enum FrenchHolidays {
    /// Dimanche de Pâques, par l'algorithme de Meeus/Jones/Butcher.
    /// Valable sur tout le calendrier grégorien.
    public static func easter(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1

        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return FlopCalendar.iso.date(from: parts) ?? .distantPast
    }

    /// Les onze jours fériés de l'année, triés par date.
    public static func all(year: Int) -> [FrenchHoliday] {
        let easterSunday = easter(year: year)

        func fixed(_ month: Int, _ day: Int, _ name: String) -> FrenchHoliday? {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            guard let date = FlopCalendar.iso.date(from: parts) else { return nil }
            return FrenchHoliday(date: FlopCalendar.iso.startOfDay(for: date), name: name)
        }

        func afterEaster(_ days: Int, _ name: String) -> FrenchHoliday? {
            guard let date = FlopCalendar.iso.date(byAdding: .day, value: days, to: easterSunday) else { return nil }
            return FrenchHoliday(date: FlopCalendar.iso.startOfDay(for: date), name: name)
        }

        return [
            fixed(1, 1, "Jour de l'an"),
            afterEaster(1, "Lundi de Pâques"),
            fixed(5, 1, "Fête du Travail"),
            fixed(5, 8, "Victoire 1945"),
            afterEaster(39, "Ascension"),
            afterEaster(50, "Lundi de Pentecôte"),
            fixed(7, 14, "Fête nationale"),
            fixed(8, 15, "Assomption"),
            fixed(11, 1, "Toussaint"),
            fixed(11, 11, "Armistice 1918"),
            fixed(12, 25, "Noël")
        ]
        .compactMap { $0 }
        .sorted { $0.date < $1.date }
    }

    /// Les fériés d'une année, calculés une seule fois.
    ///
    /// ``name(on:)`` est appelé une fois par cellule de la bande de dates, à
    /// chaque rendu. Recalculer Pâques, onze dates et un tri à chaque appel se
    /// voyait au défilement.
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var byYear: [Int: [Date: String]] = [:]

        func names(for year: Int) -> [Date: String] {
            lock.withLock {
                if let known = byYear[year] { return known }
                let computed = Dictionary(
                    all(year: year).map { ($0.date, $0.name) },
                    uniquingKeysWith: { first, _ in first }
                )
                byYear[year] = computed
                return computed
            }
        }
    }

    /// Le nom du férié tombant ce jour-là, s'il y en a un.
    public static func name(on date: Date) -> String? {
        let day = FlopCalendar.iso.startOfDay(for: date)
        let year = FlopCalendar.iso.component(.year, from: day)
        return cache.names(for: year)[day]
    }

    public static func isHoliday(_ date: Date) -> Bool {
        name(on: date) != nil
    }
}
