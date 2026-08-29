import SwiftUI
import FlopEDTKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .starting:
            StartupView()
        case .onboarding:
            OnboardingView()
        case .schedule(let selection):
            // Pas de `.id(selection)` ici : forcer une vue neuve remettait bien
            // les données à zéro, mais détruisait l'écran entier derrière la
            // feuille encore ouverte — d'où un aplat blanc le temps d'une image.
            // `ScheduleScreen` réagit désormais elle-même au changement.
            ScheduleScreen(selection: selection)
        }
    }
}

/// Écran d'attente du tout premier lancement, quand ni le cache ni l'instantané
/// embarqué n'ont rien donné — c'est-à-dire presque jamais.
private struct StartupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let error = model.lastError {
                LoadFailure(error: error) { await model.start() }
            } else {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Chargement de flop!EDT…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

