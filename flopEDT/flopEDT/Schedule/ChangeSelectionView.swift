import SwiftUI

/// Le changement d'emploi du temps depuis la barre d'outils.
///
/// Exactement le même parcours qu'au premier lancement — un seul écran à
/// maintenir — avec en plus la possibilité d'annuler.
///
/// C'est ici, à la racine de la feuille, que vit le `dismiss` : appelé depuis
/// une vue poussée dans le `NavigationStack`, il se contenterait de dépiler la
/// navigation et laisserait la feuille ouverte.
struct ChangeSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OnboardingView(isModal: true) { dismiss() }
    }
}
