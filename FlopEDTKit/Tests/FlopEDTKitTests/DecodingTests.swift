import Foundation
import Testing
@testable import FlopEDTKit

/// Ces tests décodent des réponses réellement capturées sur
/// `flopedt.iut-blagnac.fr` le 31/07/2026, et non des JSON écrits à la main.
/// Si le serveur change de forme, c'est ici que ça se voit.
@Suite("Décodage des réponses du serveur")
struct DecodingTests {

    @Test("Départements")
    func departments() throws {
        let departments = try TestSupport.decode([Department].self, from: "departments")
        #expect(departments.count == 5)
        #expect(departments.map(\.abbrev) == ["INFO", "CS", "GIM", "RT", "LPMA"])
        #expect(departments.first?.id == 103)
    }

    /// RT expose cinq promos dont deux en alternance. La v1 les rangeait sous
    /// « 1re / 2e / 3e année » et perdait donc `BUT2A` et `BUT3A`.
    @Test("Promos, y compris les parcours en alternance")
    func trainingPrograms() throws {
        let programs = try TestSupport.decode([TrainingProgram].self, from: "trainprogs-RT")
        #expect(programs.map(\.abbrev) == ["BUT1", "BUT2", "BUT2A", "BUT3", "BUT3A"])
        #expect(programs.first { $0.abbrev == "BUT2A" }?.name == "BUT R&T deuxième année par alternance")
    }

    @Test("Types de cours et durées")
    func courseTypes() throws {
        let types = try TestSupport.decode([CourseType].self, from: "coursetypes-INFO")
        let byName = Dictionary(uniqueKeysWithValues: types.map { ($0.name, $0.duration) })
        #expect(byName["CM"] == 85)
        #expect(byName["QCM"] == 20)
        #expect(byName["Conf 2h"] == 120)
    }

    @Test("Horaires de journée")
    func timeSettings() throws {
        let settings = try TestSupport.decode([TimeSettings].self, from: "timesettings")
        let info = try #require(settings.first { $0.department == 103 })
        #expect(info.dayStartTime == 480)   // 08h00
        #expect(info.dayFinishTime == 1125) // 18h45
        #expect(info.days == [.monday, .tuesday, .wednesday, .thursday, .friday])

        // Les amplitudes diffèrent réellement d'un département à l'autre : c'est
        // ce que les constantes 8h–20h de la v1 écrasaient.
        //
        // L'identifiant de LPMA est passé de 119 à 134 entre juillet et août
        // 2026. La fixture le reflète, et le test croise désormais par abrégé :
        // c'est ce que fait l'app, et c'est bien pour cela qu'elle le fait.
        let departments = try TestSupport.decode([Department].self, from: "departments")
        let lpmaID = try #require(departments.first { $0.abbrev == "LPMA" }?.id)
        let lpma = try #require(settings.first { $0.department == lpmaID })
        #expect(lpma.dayFinishTime == 1140) // 19h00
        #expect(lpma.dayFinishTime != info.dayFinishTime)
    }

    @Test("Informations de semaine")
    func weekInfo() throws {
        let info = try TestSupport.decode(WeekInfo.self, from: "weekinfo-INFO")
        #expect(info.version == 270)
        #expect(info.regen == "N, 444")
        #expect(!info.looksUngenerated)
    }

    @Test("Emploi du temps d'un groupe")
    func schedule() throws {
        let courses = try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-BUT1-1A")
        #expect(courses.count == 22)

        let friday = courses.filter { $0.day == .friday }.sorted { $0.startTime < $1.startTime }
        let first = try #require(friday.first)
        #expect(first.startTime == 480)
        #expect(first.room.name == "B103")
        #expect(first.course.module.abbrev == "Equipe")
        #expect(first.course.type == "Projet")
        #expect(first.course.module.display.colorBg.hasPrefix("#"))

        // `lineage=true` : la réponse mêle le sous-groupe et ses parents.
        let groups = Set(courses.flatMap { $0.course.groups.map(\.name) })
        #expect(groups.contains("1A"))
        #expect(groups.contains("1"))
    }

    @Test("La durée d'un cours vient du référentiel, avec repli")
    func courseDuration() throws {
        let courses = try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-BUT1-1A")
        let types = try TestSupport.decode([CourseType].self, from: "coursetypes-INFO")
        let table = Dictionary(uniqueKeysWithValues: types.map { ($0.name, $0.duration) })

        let course = try #require(courses.first { $0.course.type == "Projet" })
        #expect(course.duration(using: table) == 85)
        #expect(course.endTime(using: table) == course.startTime + 85)

        // Un type inconnu ne doit pas faire disparaître le créneau.
        #expect(course.duration(using: [:]) == 90)
    }

    @Test("Salles, avec leurs salles de base")
    func rooms() throws {
        let rooms = try TestSupport.decode([Room].self, from: "rooms-INFO")
        #expect(!rooms.isEmpty)

        let composite = try #require(rooms.first { $0.name == "B101-B102" })
        #expect(Set(composite.basicRooms.map(\.name)) == ["B101", "B102"])

        let floor = try #require(rooms.first { $0.name == "1er Etage + B219" })
        #expect(floor.basicRooms.count == 7)
    }

    @Test("Indisponibilités de salles")
    func roomUnavailabilities() throws {
        let entries = try TestSupport.decode([RoomUnavailability].self, from: "roomunavail-INFO")
        let first = try #require(entries.first)
        #expect(first.room == "Amphi1")
        #expect(first.day == .monday)
        #expect(first.endTime == first.startTime + first.duration)
    }
}
