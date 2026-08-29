import Foundation
import Testing
@testable import FlopEDTKit

@Suite("Construction des URL")
struct EndpointTests {

    private let base = FlopAPIClient.blagnac

    private func url<T>(_ endpoint: Endpoint<T>) throws -> String {
        try #require(endpoint.url(relativeTo: base)?.absoluteString)
    }

    @Test("La semaine ISO est reportée telle quelle dans la requête")
    func scheduleURL() throws {
        let endpoint = FlopEndpoints.schedule(
            dept: "INFO",
            week: ISOWeek(week: 1, year: 2026),
            trainProg: "BUT1",
            group: "1A"
        )
        #expect(try url(endpoint) == "https://flopedt.iut-blagnac.fr/fr/api/fetch/scheduledcourses/"
            + "?dept=INFO&group=1A&lineage=true&train_prog=BUT1&week=1&year=2026")
    }

    /// Le scénario du nouvel an de bout en bout : une date de décembre 2025 doit
    /// produire `week=1&year=2026`, et non `year=2025` comme en v1.
    @Test("Une date de fin décembre demande la bonne année")
    func newYearRequest() throws {
        let week = ISOWeek(containing: TestSupport.date("2025-12-31"))
        let endpoint = FlopEndpoints.schedule(dept: "INFO", week: week, trainProg: "BUT1", group: "1A")
        let result = try url(endpoint)
        #expect(result.contains("week=1"))
        #expect(result.contains("year=2026"))
        #expect(!result.contains("year=2025"))
    }

    @Test("L'ordre des paramètres est stable, pour servir de clé de cache")
    func stableOrdering() throws {
        let week = ISOWeek(week: 12, year: 2026)
        let first = FlopEndpoints.schedule(dept: "INFO", week: week, trainProg: "BUT1", group: "1A")
        let second = FlopEndpoints.schedule(dept: "INFO", week: week, trainProg: "BUT1", group: "1A")
        #expect(try url(first) == (try url(second)))
    }

    @Test("Les paramètres sont échappés")
    func escaping() throws {
        let endpoint = FlopEndpoints.schedule(
            dept: "INFO",
            week: ISOWeek(week: 12, year: 2026),
            trainProg: "BUT 1",
            group: "1 A"
        )
        let result = try url(endpoint)
        #expect(result.contains("train_prog=BUT%201"))
        #expect(result.contains("group=1%20A"))
    }

    @Test("Les horaires se demandent sans filtre de département")
    func timeSettingsHasNoQuery() throws {
        // Filtrer côté serveur redirige vers le login : on récupère tout.
        #expect(try url(FlopEndpoints.timeSettings)
            == "https://flopedt.iut-blagnac.fr/fr/api/base/timesettings/")
    }

    @Test("Les autres requêtes du catalogue sont bien formées")
    func catalogue() throws {
        let week = ISOWeek(week: 12, year: 2026)
        #expect(try url(FlopEndpoints.departments).hasSuffix("fetch/alldepts/"))
        #expect(try url(FlopEndpoints.groupTree(dept: "CS")).hasSuffix("groups/structural/tree/?dept=CS"))
        #expect(try url(FlopEndpoints.trainingPrograms(dept: "RT")).hasSuffix("fetch/idtrainprog/?dept=RT"))
        #expect(try url(FlopEndpoints.courseTypes(dept: "GIM")).hasSuffix("courses/type/?dept=GIM"))
        #expect(try url(FlopEndpoints.rooms(dept: "INFO")).hasSuffix("rooms/room/?dept=INFO"))
        #expect(try url(FlopEndpoints.weekInfo(dept: "INFO", week: week))
            .hasSuffix("extra/week-infos/?dept=INFO&week=12&year=2026"))
        #expect(try url(FlopEndpoints.roomUnavailabilities(dept: "INFO", week: week))
            .hasSuffix("fetch/unavailableroom/?dept=INFO&week=12&year=2026"))
        // Sans groupe : la requête large qui alimente les salles libres.
        #expect(try url(FlopEndpoints.departmentSchedule(dept: "INFO", week: week))
            .hasSuffix("fetch/scheduledcourses/?dept=INFO&week=12&year=2026"))
    }
}
