import Foundation
import Testing
@testable import FlopEDTKit

@Suite("Semaine d'emploi du temps")
struct WeekScheduleTests {

    private static let selection = ScheduleSelection(department: "INFO", promo: "BUT1", group: "1A")

    private func sample() throws -> WeekSchedule {
        WeekSchedule(
            week: ISOWeek(week: 12, year: 2026),
            selection: Self.selection,
            courses: try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-BUT1-1A"),
            version: 270
        )
    }

    @Test("Les cours sont triés par jour puis par heure")
    func sortsCourses() throws {
        let schedule = try sample()
        // Tuples non équatables : on compare une clé entière équivalente.
        let keys = schedule.courses.map { $0.day.offsetFromMonday * 10_000 + $0.startTime }
        #expect(keys == keys.sorted())
    }

    @Test("Les cours se retrouvent par jour")
    func filtersByDay() throws {
        let schedule = try sample()
        let friday = schedule.courses(on: .friday)
        #expect(!friday.isEmpty)
        #expect(friday.allSatisfy { $0.day == .friday })
        #expect(friday.map(\.startTime) == friday.map(\.startTime).sorted())

        // Le week-end est affiché mais reste vide tant qu'aucun cours n'y est
        // placé — la place est là pour les ajouts personnels à venir.
        #expect(schedule.courses(on: .sunday).isEmpty)
    }

    @Test("Les cours se retrouvent par date, uniquement dans leur semaine")
    func filtersByDate() throws {
        let schedule = try sample()
        #expect(!schedule.courses(on: TestSupport.date("2026-03-20")).isEmpty) // vendredi
        #expect(schedule.courses(on: TestSupport.date("2026-03-22")).isEmpty)  // dimanche
        // Une date d'une autre semaine ne rend rien, même si le jour correspond.
        #expect(schedule.courses(on: TestSupport.date("2026-03-27")).isEmpty)
    }

    /// L'API n'expose pas de calendrier scolaire : une semaine sans aucun cours
    /// est le seul signal fiable, et il ne coûte aucune requête.
    @Test("Une semaine sans cours se reconnaît")
    func detectsEmptyWeek() {
        let empty = WeekSchedule(
            week: ISOWeek(week: 33, year: 2026),
            selection: Self.selection,
            courses: []
        )
        #expect(empty.isEmpty)
        #expect(empty.busyDays.isEmpty)
        #expect(empty.timeRange(using: [:]) == nil)
    }

    @Test("Les jours occupés sont recensés")
    func listsBusyDays() throws {
        let schedule = try sample()
        #expect(schedule.busyDays.contains(.friday))
        #expect(!schedule.busyDays.contains(.saturday))
    }

    /// Permet de resserrer la grille sur ce qui est réellement occupé, au lieu
    /// d'afficher l'amplitude complète avec du vide en haut et en bas.
    @Test("L'amplitude réelle de la semaine se calcule")
    func computesTimeRange() throws {
        let schedule = try sample()
        let durations = try TestSupport
            .decode([CourseType].self, from: "coursetypes-INFO")
            .reduce(into: [String: Int]()) { $0[$1.name] = $1.duration }

        let range = try #require(schedule.timeRange(using: durations))
        #expect(range.lowerBound == schedule.courses.map(\.startTime).min())
        #expect(range.upperBound > range.lowerBound)
        // Le premier cours de la semaine commence à 8h00.
        #expect(range.lowerBound == 480)
    }

    /// Le même contenu arrive deux fois au lancement — cache puis réseau. Sans
    /// cette comparaison, l'écran se réanimerait pour rien à chaque ouverture.
    @Test("Deux versions du même contenu sont reconnues comme identiques")
    func comparesContentIgnoringTimestamps() throws {
        let first = try sample()
        let second = WeekSchedule(
            week: first.week,
            selection: first.selection,
            courses: first.courses,
            version: 999,
            fetchedAt: first.fetchedAt.addingTimeInterval(3600)
        )
        #expect(first.hasSameCourses(as: second))
        #expect(first != second)

        let modified = WeekSchedule(
            week: first.week,
            selection: first.selection,
            courses: Array(first.courses.dropFirst()),
            version: first.version
        )
        #expect(!first.hasSameCourses(as: modified))
    }
}

@Suite("Cache de l'emploi du temps")
struct ScheduleCacheTests {

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func schedule(week: ISOWeek, selection: ScheduleSelection) -> WeekSchedule {
        WeekSchedule(week: week, selection: selection, courses: [], version: 1)
    }

    @Test("Un aller-retour par le disque conserve la semaine")
    func roundTrips() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try FileScheduleCache(directory: directory)

        let selection = ScheduleSelection(department: "INFO", promo: "BUT1", group: "1A")
        let week = ISOWeek(week: 12, year: 2026)
        let key = ScheduleCacheKey(selection: selection, week: week)

        #expect(cache.read(key) == nil)
        cache.write(schedule(week: week, selection: selection), for: key)
        #expect(cache.read(key)?.week == week)

        cache.removeAll()
        #expect(cache.read(key) == nil)
    }

    /// Deux groupes différents ne doivent jamais partager une entrée.
    @Test("La sélection fait partie de la clé")
    func keyIncludesSelection() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try FileScheduleCache(directory: directory)

        let week = ISOWeek(week: 12, year: 2026)
        let first = ScheduleSelection(department: "INFO", promo: "BUT1", group: "1A")
        let second = ScheduleSelection(department: "INFO", promo: "BUT1", group: "1B")

        cache.write(schedule(week: week, selection: first), for: .init(selection: first, week: week))
        #expect(cache.read(.init(selection: second, week: week)) == nil)
        #expect(cache.read(.init(selection: first, week: week)) != nil)
    }

    @Test("Un nom de groupe inhabituel donne un nom de fichier sûr")
    func sanitisesFileName() {
        let selection = ScheduleSelection(department: "INFO", promo: "BUT 2/A", group: "1er Étage")
        let key = ScheduleCacheKey(selection: selection, week: ISOWeek(week: 3, year: 2027))
        #expect(!key.fileName.contains("/"))
        #expect(!key.fileName.contains(" "))
        #expect(key.fileName.hasSuffix("2027-W3.json"))
    }

    @Test("Le cache est élagué au-delà de sa taille maximale")
    func prunesOldEntries() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try FileScheduleCache(directory: directory)
        let selection = ScheduleSelection(department: "INFO", promo: "BUT1", group: "1A")

        for offset in 0..<(FileScheduleCache.maxEntries + 6) {
            let week = ISOWeek(week: 12, year: 2026).advanced(by: offset)
            cache.write(schedule(week: week, selection: selection), for: .init(selection: selection, week: week))
        }

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count <= FileScheduleCache.maxEntries)
    }
}
