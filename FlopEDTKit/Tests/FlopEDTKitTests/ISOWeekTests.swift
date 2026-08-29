import Foundation
import Testing
@testable import FlopEDTKit

@Suite("Semaines ISO")
struct ISOWeekTests {

    /// La régression de la v1 : `component(.year)` renvoie 2025 pour une date de
    /// décembre appartenant à la semaine ISO 1 de 2026. L'app demandait donc la
    /// semaine 1 de 2025 et affichait une semaine vide, chaque année.
    @Test("Le passage au nouvel an donne l'année ISO, pas l'année civile", arguments: [
        ("2025-12-29", 1, 2026),
        ("2025-12-31", 1, 2026),
        ("2026-01-01", 1, 2026),
        ("2026-01-04", 1, 2026)
    ])
    func newYearBoundary(iso: String, week: Int, year: Int) {
        let result = ISOWeek(containing: TestSupport.date(iso))
        #expect(result == ISOWeek(week: week, year: year))
    }

    @Test("La semaine 52 de 2025 reste en 2025")
    func lastWeekOfPreviousYear() {
        #expect(ISOWeek(containing: TestSupport.date("2025-12-28")) == ISOWeek(week: 52, year: 2025))
    }

    /// 2026 compte 53 semaines ISO : le 1er janvier 2027 appartient encore à
    /// 2026. Un calcul naïf produirait la semaine 1 de 2027.
    @Test("Les années à 53 semaines débordent sur janvier suivant", arguments: [
        ("2026-12-31", 53, 2026),
        ("2027-01-01", 53, 2026),
        ("2027-01-03", 53, 2026),
        ("2027-01-04", 1, 2027)
    ])
    func fiftyThreeWeekYear(iso: String, week: Int, year: Int) {
        #expect(ISOWeek(containing: TestSupport.date(iso)) == ISOWeek(week: week, year: year))
    }

    @Test("Le lundi de la semaine est correct", arguments: [
        ("2026-01-01", "2025-12-29"),
        ("2026-03-16", "2026-03-16"),
        ("2027-01-01", "2026-12-28"),
        ("2026-09-07", "2026-09-07")
    ])
    func mondayOfWeek(iso: String, expected: String) {
        let monday = ISOWeek(containing: TestSupport.date(iso)).monday
        #expect(TestSupport.day(monday) == expected)
    }

    @Test("Une semaine contient sept jours, du lundi au dimanche")
    func sevenDays() {
        let days = ISOWeek(week: 12, year: 2026).days
        #expect(days.count == 7)
        #expect(TestSupport.day(days[0]) == "2026-03-16")
        #expect(TestSupport.day(days[6]) == "2026-03-22")
        #expect(Weekday(date: days[0]) == .monday)
        #expect(Weekday(date: days[6]) == .sunday)
    }

    @Test("Se décaler franchit les frontières d'année")
    func advancing() {
        let december = ISOWeek(week: 52, year: 2025)
        #expect(december.advanced(by: 1) == ISOWeek(week: 1, year: 2026))
        #expect(december.advanced(by: -1) == ISOWeek(week: 51, year: 2025))

        // 2026 ayant 53 semaines, on ne passe en 2027 qu'après la 53e.
        let end = ISOWeek(week: 52, year: 2026)
        #expect(end.advanced(by: 1) == ISOWeek(week: 53, year: 2026))
        #expect(end.advanced(by: 2) == ISOWeek(week: 1, year: 2027))
    }

    @Test("Se décaler puis revenir redonne la semaine de départ")
    func advancingRoundTrip() {
        for offset in [-60, -13, -1, 0, 1, 13, 60] {
            let start = ISOWeek(week: 37, year: 2026)
            #expect(start.advanced(by: offset).advanced(by: -offset) == start)
        }
    }

    @Test("La distance entre deux semaines se compte en semaines")
    func distance() {
        #expect(ISOWeek(week: 52, year: 2025).distance(to: ISOWeek(week: 1, year: 2026)) == 1)
        #expect(ISOWeek(week: 52, year: 2026).distance(to: ISOWeek(week: 1, year: 2027)) == 2)
        #expect(ISOWeek(week: 12, year: 2026).distance(to: ISOWeek(week: 12, year: 2026)) == 0)
    }

    @Test("Une semaine reconnaît ses propres jours")
    func containment() {
        let week = ISOWeek(week: 12, year: 2026)
        #expect(week.days.allSatisfy(week.contains))
        #expect(!week.contains(TestSupport.date("2026-03-23")))
        #expect(!week.contains(TestSupport.date("2026-03-15")))
    }

    @Test("Les semaines se trient chronologiquement")
    func ordering() {
        #expect(ISOWeek(week: 52, year: 2025) < ISOWeek(week: 1, year: 2026))
        #expect(ISOWeek(week: 1, year: 2026) < ISOWeek(week: 2, year: 2026))
    }

    @Test("Reconstruire une semaine depuis son lundi est stable")
    func roundTripThroughMonday() {
        for week in 1...52 {
            let original = ISOWeek(week: week, year: 2026)
            #expect(ISOWeek(containing: original.monday) == original)
        }
        let fiftyThird = ISOWeek(week: 53, year: 2026)
        #expect(ISOWeek(containing: fiftyThird.monday) == fiftyThird)
    }
}
