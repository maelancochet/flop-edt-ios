import SwiftUI

/// Vue représentant une ligne de tâche/cours dans l'emploi du temps
/// Affiche les informations d'un cours avec trois états possibles : vide, en chargement, ou avec données complètes
struct TaskRow: View {
    // MARK: - États de la vue
    
    /// Indique si aucun cours n'est prévu
    var isEmpty: Bool = false
    
    /// Indique si les données sont en cours de chargement
    var isDownloading: Bool = false
    
    // MARK: - Propriétés des données du cours
    
    /// Heure du cours (format: "9h30")
    var time: String = ""
    
    /// Nom complet du module
    var moduleName: String = ""
    
    /// Abréviation du module (ex: "CreaDB")
    var moduleAbbrev: String = ""
    
    /// Type de cours (TD, TP, CM, etc.)
    var type: String = ""
    
    /// Nom ou initiales du tuteur/professeur
    var tutor: String = ""
    
    /// Nom de la salle de cours
    var room: String = ""
    
    /// Couleur du cercle au format hexadécimal (ex: "#FFC0CB")
    var colorBg: String = ""
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if isDownloading {
                loadingStateView
            }
            else if isEmpty {
                emptyStateView
            }
            else {
                courseContentView
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .black.opacity(0.35), radius: 1)
        }
    }
    
    // MARK: - Vues d'état
    
    /// Vue affichée pendant le chargement des données
    private var loadingStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.gray)
            /// Instagram
            //Text("@m3_maelan")
              //  .font(.system(size: 14))
                //.fontWeight(.semibold)
                //.foregroundStyle(.gray)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }
    
    /// Vue affichée lorsqu'aucun cours n'est prévu
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("Pas de cours ce jour")
                .font(.system(size: 14))
                .fontWeight(.semibold)
            /// Instagram
            //Text("@m3_maelan")
                //.font(.system(size: 14))
                //.fontWeight(.semibold)
                //.foregroundStyle(.gray)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }
    
    /// Vue affichant les informations complètes du cours
    private var courseContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill((Color(hex: colorBg) ?? Color(hex: "#FFC0CB"))!)
                .frame(width: 13, height: 13)
            
            HStack {
                Text(moduleAbbrev)
                    .font(.system(size: 14))
                .fontWeight(.semibold)
                Text("-")
                    .font(.system(size: 14))
                    .fontWeight(.semibold)
                Text(type)
                    .font(.system(size: 14))
                    .fontWeight(.semibold)
            }
           
            HStack {
                Text(time)
                
                Spacer(minLength: 0)
                
                Text(tutor)
                Text("/")
                Text(room)
            }
            .font(.caption)
            .foregroundStyle(.gray)
            .padding(.top, 5)
        }
        .lineLimit(1)
        .padding(15)
    }
}

// MARK: - Extensions

/// Extension pour convertir les codes couleurs hexadécimaux en Color SwiftUI
extension Color {
    /// Initialise une couleur à partir d'une chaîne hexadécimale
    /// - Parameter hex: Code couleur hexadécimal (formats supportés: RGB 12-bit, RGB 24-bit, ARGB 32-bit)
    /// - Returns: Une couleur SwiftUI ou nil si le format est invalide
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 10) {
        TaskRow(
            time: "9h30",
            moduleName: "Création de Base de Données",
            moduleAbbrev: "CreaDB",
            type: "TD",
            tutor: "OT",
            room: "Amphi3",
            colorBg: ""
        )
        TaskRow(isEmpty: true)
        TaskRow(isDownloading: true)
    }
    .padding(55)
}
