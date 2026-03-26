import SwiftUI

/// Point d'entrée principal de l'application flop!EDT
/// Gère la configuration globale et le cycle de vie de l'application
@main
struct FlopEDTApp: App {
    
    // MARK: - Propriétés
    
    /// Version actuelle de l'application stockée dans UserDefaults
    /// Format: MAJOR.MINOR.PATCH-STAGE (ex: 25.11.6-beta)
    @AppStorage("version") var version: String = "26.01.1-rc"
    
    // MARK: - Initialisation
    
    init() {
        // Configuration initiale de l'application
        // Possibilité d'ajouter ici la configuration de l'apparence, des services, etc.
    }
    
    // MARK: - Scene Configuration
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Historique des versions

/*
 Version 26.01.1-rc
 - Version actuelle
 */
