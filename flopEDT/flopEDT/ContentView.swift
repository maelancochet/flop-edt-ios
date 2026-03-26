import SwiftUI

/// Vue principale de l'application
/// Gère l'affichage de la vue d'accueil et la persistance des préférences utilisateur
struct ContentView: View {
    
    // MARK: - Propriétés stockées (AppStorage)
    
    /// Département sélectionné pour le téléchargement de l'emploi du temps
    @AppStorage("departementtodownload") var departementtodownload: String = ""
    
    /// Département actuellement téléchargé et affiché
    @AppStorage("departementdownloaded") var departementdownloaded: String = ""
    
    /// Programme de formation sélectionné
    @AppStorage("trainprog") var trainprog: String = ""
    
    /// Filtre pour les cours magistraux (CM)
    @AppStorage("filtreCM") var filtreCM: String = ""
    
    /// Filtre de groupe sélectionné
    @AppStorage("filtreGroupe") var filtreGroupe: String = ""
    
    /// Filtre de sous-groupe sélectionné
    @AppStorage("filtreSousGroupe") var filtreSousGroupe: String = ""
    
    // MARK: - Body
    
    var body: some View {
        HomeView()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

