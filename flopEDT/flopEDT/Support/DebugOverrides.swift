import Foundation
import FlopEDTKit

/// Réglages de mise au point, actifs uniquement en build de développement.
///
/// Préparer la rentrée en plein été pose un problème pratique : la semaine
/// courante est vide, donc tous les écrans le sont aussi. Ces bascules
/// permettent d'ouvrir l'app sur une date de cours réelle sans toucher au code.
///
/// Dans Xcode : schéma → Run → Arguments → Environment Variables.
/// En ligne de commande, préfixer par `SIMCTL_CHILD_` :
///
/// ```
/// SIMCTL_CHILD_FLOP_DEBUG_DATE=2026-03-19 xcrun simctl launch booted flopEDT.flopEDT
/// ```
enum DebugOverrides {
    /// Jour affiché au lancement, au format `aaaa-mm-jj`.
    static var initialDate: Date? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["FLOP_DEBUG_DATE"] else { return nil }
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return FlopCalendar.iso.date(from: components).map(FlopCalendar.iso.startOfDay(for:))
        #else
        return nil
        #endif
    }

    /// Ouvre directement une feuille au lancement : `rooms`, `settings` ou
    /// `change`. Évite d'avoir à naviguer à la main pour vérifier un écran.
    static var initialScreen: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["FLOP_DEBUG_SCREEN"]
        #else
        nil
        #endif
    }
}
