import Foundation

/// Le calendrier de référence de l'application.
///
/// Volontairement figé sur ISO 8601 et Europe/Paris, et non sur `Calendar.current` :
/// - l'API FlOpEDT raisonne en semaines ISO. `Calendar.current` suit la locale de
///   l'appareil, dont `firstWeekday` et `minimalDaysInFirstWeek` varient d'un pays
///   à l'autre, ce qui décale le numéro de semaine demandé au serveur ;
/// - les cours ont lieu à Blagnac. « Aujourd'hui » et « maintenant » doivent rester
///   ceux de l'IUT même si l'utilisateur voyage.
public enum FlopCalendar {
    public static let timeZone: TimeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt

    /// Calendrier ISO 8601 : semaines du lundi au dimanche, semaine 1 = celle du
    /// premier jeudi de l'année.
    public static let iso: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }()

    /// Le jour courant à Blagnac, ramené à minuit.
    public static func today(now: Date = .now) -> Date {
        iso.startOfDay(for: now)
    }

    /// Minutes écoulées depuis minuit — l'unité utilisée par l'API pour
    /// `start_time`, `day_start_time` et les durées.
    public static func minutesSinceMidnight(of date: Date) -> Int {
        let parts = iso.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// La date à afficher au retour au premier plan, ou `nil` s'il n'y a rien à
    /// changer.
    ///
    /// iOS garde une app en mémoire plusieurs jours. Sans cela, l'étudiant qui
    /// ferme l'app lundi soir et la rouvre mardi matin retrouve la journée de
    /// lundi : la semaine est bien retéléchargée, mais le jour sélectionné ne
    /// bouge pas, et comme c'est toujours la même semaine ISO le bouton
    /// « Aujourd'hui » ne s'affiche même pas.
    ///
    /// On ne bouge que si le jour civil a changé **et** que l'utilisateur était
    /// resté sur ce qui était alors aujourd'hui : quelqu'un qui consultait la
    /// semaine prochaine doit la retrouver telle quelle.
    public static func dateAfterResume(selected: Date, lastActive: Date, now: Date = .now) -> Date? {
        let previousToday = today(now: lastActive)
        let currentToday = today(now: now)
        guard previousToday != currentToday else { return nil }
        guard iso.isDate(selected, inSameDayAs: previousToday) else { return nil }
        return currentToday
    }
}
