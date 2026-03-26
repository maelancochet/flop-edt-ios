import SwiftUI

/// Point d'entrée principal de l'application flop!EDT
/// Gère la configuration globale et le cycle de vie de l'application
@main
struct FlopEDTApp: App {
    
    // MARK: - Constantes

    static let version = "26.01.1-rc"
    
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
