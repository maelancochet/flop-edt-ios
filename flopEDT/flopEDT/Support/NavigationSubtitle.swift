import SwiftUI

/// `navigationSubtitle` n'existe qu'à partir d'iOS 26, or l'app cible iOS 18.
///
/// En dessous, le sous-titre est simplement absent. Les écrans concernés restent
/// lisibles sans lui : l'emploi du temps garde son titre de mois, et l'écran de
/// sélection garde ses coches, qui indiquent le département, la promo et le
/// groupe suivis.
extension View {
    @ViewBuilder
    func navigationSubtitleIfAvailable(_ text: String?) -> some View {
        if #available(iOS 26.0, *), let text {
            navigationSubtitle(text)
        } else {
            self
        }
    }
}
