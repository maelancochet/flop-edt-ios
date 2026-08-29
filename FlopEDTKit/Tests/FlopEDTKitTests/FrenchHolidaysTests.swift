import Foundation
import Testing
@testable import FlopEDTKit

@Suite("Jours fériés")
struct FrenchHolidaysTests {

    @Test("Pâques tombe à la bonne date", arguments: [
        (2024, "2024-03-31"), (2025, "2025-04-20"), (2026, "2026-04-05"),
        (2027, "2027-03-28"), (2028, "2028-04-16"), (2030, "2030-04-21")
    ])
    func easterDates(year: Int, expected: String) {
        #expect(TestSupport.day(FrenchHolidays.easter(year: year)) == expected)
    }

    @Test("Les fériés mobiles se déduisent de Pâques")
    func movableHolidays() {
        let holidays = FrenchHolidays.all(year: 2026)
        func date(of name: String) -> String? {
            holidays.first { $0.name == name }.map { TestSupport.day($0.date) }
        }
        #expect(date(of: "Lundi de Pâques") == "2026-04-06")
        #expect(date(of: "Ascension") == "2026-05-14")
        #expect(date(of: "Lundi de Pentecôte") == "2026-05-25")
    }

    @Test("Onze fériés par an, triés")
    func count() {
        for year in 2024...2030 {
            let holidays = FrenchHolidays.all(year: year)
            #expect(holidays.count == 11)
            #expect(holidays.map(\.date) == holidays.map(\.date).sorted())
        }
    }

    @Test("Un jour férié est reconnu, un jour ordinaire non")
    func lookup() {
        #expect(FrenchHolidays.name(on: TestSupport.date("2026-05-01")) == "Fête du Travail")
        #expect(FrenchHolidays.name(on: TestSupport.date("2026-11-11")) == "Armistice 1918")
        #expect(FrenchHolidays.name(on: TestSupport.date("2026-05-14")) == "Ascension")
        #expect(FrenchHolidays.name(on: TestSupport.date("2026-05-15")) == nil)
        #expect(FrenchHolidays.name(on: TestSupport.date("2026-03-16")) == nil)
    }

    /// Le cas concret pour l'affichage : le jeudi de l'Ascension 2026 tombe en
    /// semaine 20, un jour où l'emploi du temps serait sinon présenté comme
    /// ouvré.
    @Test("Un férié se repère dans la semaine affichée")
    func withinDisplayedWeek() {
        let week = ISOWeek(containing: TestSupport.date("2026-05-14"))
        #expect(week == ISOWeek(week: 20, year: 2026))

        let flagged = week.days.filter(FrenchHolidays.isHoliday).map(TestSupport.day)
        #expect(flagged == ["2026-05-14"])
    }
}
