import Foundation

actor ScheduleDataManager {
    static let shared = ScheduleDataManager()

    private let baseURL = "https://flopedt.iut-blagnac.fr/fr/api"
    private var weekCache: [String: Data] = [:]

    private init() {}

    func clearCache() {
        weekCache.removeAll()
    }

    func cachedData(for week: Int, year: Int) -> Data? {
        weekCache[cacheKey(week: week, year: year)]
    }

    var hasCachedData: Bool {
        !weekCache.isEmpty
    }

    func fetchSchedule(dept: String, week: Int, year: Int, workCopy: Int = 0) async throws -> Data {
        let key = cacheKey(dept: dept, week: week, year: year)

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

    func fetchMultipleWeeks(dept: String, numberOfWeeks: Int = 5) async throws -> [Data] {
        let calendar = Calendar.current
        let mondayOfThisWeek = Date.getMondayOfWeek(for: Date())

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

    func getAllCachedCourses() throws -> [ScheduledCourse] {
        var allCourses: [ScheduledCourse] = []
        let decoder = JSONDecoder()

        for data in weekCache.values {
            let courses = try decoder.decode([ScheduledCourse].self, from: data)
            allCourses.append(contentsOf: courses)
        }

        return allCourses
    }

    private func cacheKey(dept: String = "", week: Int, year: Int) -> String {
        "\(dept)-\(year)-W\(week)"
    }

    static func getWeekNumber(for date: Date) -> (week: Int, year: Int) {
        let calendar = Calendar.current
        return (calendar.component(.weekOfYear, from: date), calendar.component(.year, from: date))
    }
}

extension ScheduleDataManager {
    func loadCurrentAndUpcomingWeeks(dept: String) async throws {
        _ = try await fetchMultipleWeeks(dept: dept, numberOfWeeks: 5)
    }

    func getCoursesForWeek(_ weekOffset: Int, dept: String) async throws -> [ScheduledCourse] {
        let calendar = Calendar.current
        let mondayOfThisWeek = Date.getMondayOfWeek(for: Date())

        guard let targetMonday = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: mondayOfThisWeek) else {
            return []
        }

        let (week, year) = ScheduleDataManager.getWeekNumber(for: targetMonday)
        let data = try await fetchSchedule(dept: dept, week: week, year: year)
        return try JSONDecoder().decode([ScheduledCourse].self, from: data)
    }
}
