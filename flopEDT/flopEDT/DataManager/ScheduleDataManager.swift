import Foundation

// MARK: - Schedule Data Manager

/// Gestionnaire centralisé pour le téléchargement et la mise en cache des emplois du temps
actor ScheduleDataManager {
    
    // MARK: - Singleton
    
    static let shared = ScheduleDataManager()
    
    // MARK: - Properties

    private let baseURL = "https://flopedt.iut-blagnac.fr/fr/api"

    /// Cache des données brutes par semaine
    private var weekCache: [String: Data] = [:]
    
    // MARK: - Initialization
    
    private init() {}

    // MARK: - Cache Management
    
    /// Vide tous les caches de données
    func clearCache() {
        weekCache.removeAll()
    }
    
    /// Retourne les données mises en cache pour une semaine spécifique
    func cachedData(for week: Int, year: Int) -> Data? {
        let key = cacheKey(week: week, year: year)
        return weekCache[key]
    }
    
    /// Vérifie si des données sont en cache
    var hasCachedData: Bool {
        !weekCache.isEmpty
    }

    // MARK: - Network Methods
    
    /// Télécharge l'emploi du temps pour une semaine spécifique
    /// - Parameters:
    ///   - dept: Code du département (ex: "INFO", "GIM")
    ///   - week: Numéro de la semaine
    ///   - year: Année
    ///   - workCopy: Version de travail (par défaut: 0)
    /// - Returns: Données JSON brutes de l'emploi du temps
    func fetchSchedule(dept: String, week: Int, year: Int, workCopy: Int = 0) async throws -> Data {
        let key = cacheKey(week: week, year: year)

        if let cached = weekCache[key] {
            return cached
        }
        
        let urlString = "\(baseURL)/fetch/scheduledcourses/?dept=\(dept)&week=\(week)&year=\(year)&work_copy=\(workCopy)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        weekCache[key] = data

        return data
    }
    
    /// Télécharge plusieurs semaines consécutives à partir de la semaine actuelle
    /// - Parameters:
    ///   - dept: Code du département
    ///   - numberOfWeeks: Nombre de semaines à télécharger (par défaut: 5)
    /// - Returns: Liste des données téléchargées
    func fetchMultipleWeeks(dept: String, numberOfWeeks: Int = 5) async throws -> [Data] {
        let calendar = Calendar.current
        let today = Date()
        let mondayOfThisWeek = Date.getMondayOfWeek(for: today)
        
        var results: [Data] = []
        
        for weekOffset in 0..<numberOfWeeks {
            guard let targetMonday = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: mondayOfThisWeek) else {
                continue
            }
            
            let weekNumber = calendar.component(.weekOfYear, from: targetMonday)
            let year = calendar.component(.year, from: targetMonday)
            
            do {
                let data = try await fetchSchedule(dept: dept, week: weekNumber, year: year)
                results.append(data)
            } catch {
                continue
            }
        }
        if results.isEmpty {
                throw URLError(.cannotConnectToHost)
        }
        return results
    }
    
    // MARK: - Data Retrieval
    
    /// Récupère tous les cours disponibles dans le cache
    /// - Returns: Liste de tous les cours mis en cache
    func getAllCachedCourses() throws -> [ScheduledCourse] {
        var allCourses: [ScheduledCourse] = []
        let decoder = JSONDecoder()
        
        for data in weekCache.values {
            let courses = try decoder.decode([ScheduledCourse].self, from: data)
            allCourses.append(contentsOf: courses)
        }
        
        return allCourses
    }
    
    // MARK: - Helper Methods
    
    /// Génère une clé unique pour identifier une semaine dans le cache
    private func cacheKey(week: Int, year: Int) -> String {
        return "\(year)-W\(week)"
    }
    
    /// Calcule le numéro de semaine et l'année pour une date donnée
    static func getWeekNumber(for date: Date) -> (week: Int, year: Int) {
        let calendar = Calendar.current
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.year, from: date)
        return (week, year)
    }
}

// MARK: - Public API Extension

extension ScheduleDataManager {
    
    /// Charge l'emploi du temps pour la semaine actuelle et les 4 semaines suivantes
    /// - Parameter dept: Code du département
    func loadCurrentAndUpcomingWeeks(dept: String) async throws {
        let numberOfWeeks = 5
        _ = try await fetchMultipleWeeks(dept: dept, numberOfWeeks: numberOfWeeks)
    }
    
    /// Récupère les cours pour une semaine spécifique par rapport à la semaine actuelle
    /// - Parameters:
    ///   - weekOffset: Décalage en semaines (0 = semaine actuelle, 1 = semaine suivante, etc.)
    ///   - dept: Code du département
    /// - Returns: Liste des cours pour la semaine demandée
    func getCoursesForWeek(_ weekOffset: Int, dept: String) async throws -> [ScheduledCourse] {
        let calendar = Calendar.current
        let today = Date()
        let mondayOfThisWeek = Date.getMondayOfWeek(for: today)
        
        guard let targetMonday = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: mondayOfThisWeek) else {
            return []
        }
        
        let (week, year) = ScheduleDataManager.getWeekNumber(for: targetMonday)
        
        let data = try await fetchSchedule(dept: dept, week: week, year: year)
        
        let decoder = JSONDecoder()
        return try decoder.decode([ScheduledCourse].self, from: data)
    }
}
