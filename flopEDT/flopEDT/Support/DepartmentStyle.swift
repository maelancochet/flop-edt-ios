import SwiftUI
import FlopEDTKit

/// Habillage des départements.
///
/// L'API ne renvoie que l'abrégé — aucun endpoint accessible en lecture n'expose
/// de libellé long. Ce tableau est donc de la décoration, et non du référentiel :
/// un département inconnu s'affiche avec son abrégé et une icône neutre, sans
/// que l'app ait besoin d'être mise à jour.
enum DepartmentStyle {
    private static let known: [String: (title: String, symbol: String)] = [
        "INFO": ("Informatique", "pc"),
        "CS": ("Carrières Sociales", "person.2.fill"),
        "GIM": ("Génie Industriel et Maintenance", "powercord.fill"),
        "RT": ("Réseaux et Télécommunications", "network"),
        "LPMA": ("LP Maintenance Aéronautique", "airplane")
    ]

    static func title(for abbrev: String) -> String {
        known[abbrev]?.title ?? abbrev
    }

    static func symbol(for abbrev: String) -> String {
        known[abbrev]?.symbol ?? "building.columns"
    }
}

extension Weekday {
    /// « lun. », « mar. »… dans la locale française, quelle que soit celle de
    /// l'appareil : l'emploi du temps est celui d'un IUT français.
    var shortLabel: String {
        let symbols = DateFormatter.frenchShortWeekdays
        // `shortWeekdaySymbols` commence au dimanche.
        return symbols[(offsetFromMonday + 1) % 7]
    }
}

extension DateFormatter {
    static let frenchShortWeekdays: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.shortWeekdaySymbols
    }()

    /// « mars », sans l'année.
    static let frenchMonthOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = FlopCalendar.timeZone
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    /// « mars 2026 ».
    static let frenchMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = FlopCalendar.timeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    /// « jeudi 19 mars ». Locale française imposée : l'emploi du temps est celui
    /// d'un IUT français, quelle que soit la langue de l'appareil.
    static let frenchDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = FlopCalendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}

extension Int {
    /// Minutes depuis minuit → « 08:30 ».
    var asClockTime: String {
        String(format: "%02d:%02d", self / 60, self % 60)
    }

    /// Durée en minutes → « 1 h 25 », « 45 min ».
    var asDuration: String {
        let hours = self / 60
        let minutes = self % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) h" }
        return "\(hours) h \(minutes)"
    }
}

extension Color {
    /// Les couleurs des modules arrivent en hexadécimal depuis le serveur.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let red, green, blue, alpha: UInt64
        switch cleaned.count {
        case 3:
            (alpha, red, green, blue) = (255, (value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6:
            (alpha, red, green, blue) = (255, value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8:
            (alpha, red, green, blue) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
