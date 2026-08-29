import Foundation
import Testing
@testable import FlopEDTKit

enum TestSupport {
    /// Une date à midi, heure de Paris — midi pour qu'aucun changement d'heure
    /// ne puisse faire basculer la date d'un jour.
    static func date(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        precondition(parts.count == 3, "date attendue au format aaaa-mm-jj")
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = FlopCalendar.iso.date(from: components) else {
            fatalError("date invalide : \(iso)")
        }
        return date
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = FlopCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    /// Décode une fixture avec exactement la configuration du client réel.
    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: fixture(name))
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)
        var description: String {
            switch self {
            case .missing(let name): "fixture introuvable : \(name).json"
            }
        }
    }
}
