import Foundation
import Testing
@testable import FlopEDTKit

@Suite("Jours de la semaine")
struct WeekdayTests {

    /// La régression de HCalendarView. `HorizontalCalendar.swift:168` déduisait
    /// la position d'un jour de `component(.weekday) - 1`, numéroté à partir du
    /// dimanche, alors que le tableau affiché commence à `firstWeekday`. Les deux
    /// ne coïncident qu'aux États-Unis ; sur un iPhone français la sélection
    /// glissait d'un jour à chaque changement de semaine.
    @Test("Le jour se déduit de la date, quelle que soit la locale", arguments: [
        ("2026-03-16", Weekday.monday),
        ("2026-03-17", .tuesday),
        ("2026-03-18", .wednesday),
        ("2026-03-19", .thursday),
        ("2026-03-20", .friday),
        ("2026-03-21", .saturday),
        ("2026-03-22", .sunday)
    ])
    func weekdayFromDate(iso: String, expected: Weekday) {
        #expect(Weekday(date: TestSupport.date(iso)) == expected)
    }

    @Test("Le décalage depuis lundi correspond à l'ordre d'affichage")
    func offsets() {
        #expect(Weekday.allCases.map(\.offsetFromMonday) == Array(0...6))
    }

    @Test("Un jour retrouvé dans sa semaine est bien celui attendu")
    func dateOfWeekdayInWeek() {
        let week = ISOWeek(week: 12, year: 2026)
        for day in Weekday.allCases {
            let date = try! #require(week.date(of: day))
            #expect(Weekday(date: date) == day)
        }
        #expect(TestSupport.day(week.date(of: .friday)!) == "2026-03-20")
        #expect(TestSupport.day(week.date(of: .sunday)!) == "2026-03-22")
    }

    /// Le scénario exact reproduit sur l'iPhone de l'utilisateur : avancer d'une
    /// semaine doit conserver le jour de la semaine sélectionné.
    @Test("Changer de semaine conserve le jour sélectionné", arguments: [
        "2026-07-27", "2026-07-30", "2026-08-01", "2026-08-02"
    ])
    func weekChangeKeepsWeekday(iso: String) {
        let selected = TestSupport.date(iso)
        let day = Weekday(date: selected)
        let nextWeek = ISOWeek(containing: selected).advanced(by: 1)

        let moved = try! #require(nextWeek.date(of: day))
        #expect(Weekday(date: moved) == day)

        let expected = FlopCalendar.iso.date(byAdding: .day, value: 7, to: FlopCalendar.iso.startOfDay(for: selected))!
        #expect(TestSupport.day(moved) == TestSupport.day(expected))
    }

    @Test("Les codes correspondent à ceux de l'API")
    func rawValues() {
        #expect(Weekday.allCases.map(\.rawValue) == ["m", "tu", "w", "th", "f", "sa", "su"])
    }
}
