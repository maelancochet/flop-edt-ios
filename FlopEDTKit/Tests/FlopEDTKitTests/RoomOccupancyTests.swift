import Foundation
import Testing
@testable import FlopEDTKit

@Suite("Salles libres")
struct RoomOccupancyTests {

    // MARK: Fabriques

    private func room(_ name: String, basic: [String]? = nil) -> Room {
        let contents = basic ?? [name]
        return Room(
            id: abs(name.hashValue % 10_000),
            name: name,
            subroomOf: [],
            departments: [103],
            isBasic: basic == nil,
            basicRooms: contents.map { RoomRef(id: abs($0.hashValue % 10_000), name: $0) }
        )
    }

    private func course(
        _ room: String,
        day: Weekday = .monday,
        start: Int,
        type: String = "CM",
        module: String = "Algo"
    ) -> ScheduledCourse {
        ScheduledCourse(
            id: Int.random(in: 1...1_000_000),
            room: RoomRef(id: 1, name: room),
            startTime: start,
            day: day,
            course: Course(
                id: 1,
                type: type,
                roomType: "M",
                week: 12,
                year: 2026,
                groups: [],
                suppTutor: [],
                module: Module(
                    name: module,
                    abbrev: module,
                    display: ModuleDisplay(colorBg: "#ffffff", colorTxt: "#000000")
                ),
                payModule: nil,
                isGraded: false
            ),
            tutor: nil,
            idVisio: nil,
            number: 1
        )
    }

    private let durations = ["CM": 90, "TD": 90, "TP": 120]

    // MARK: Chevauchement des salles

    /// Le piège central : réserver une salle composite en occupe plusieurs.
    /// Sans cette expansion, l'app proposerait des salles en réalité prises.
    @Test("Une salle composite occupe ses salles de base")
    func compositeRoomBlocksItsParts() {
        let occupancy = RoomOccupancy(
            rooms: [room("B101"), room("B102"), room("B103"),
                    room("B101-B102", basic: ["B101", "B102"])],
            courses: [course("B101-B102", start: 600)],
            durations: durations
        )

        #expect(!occupancy.status(of: "B101", on: .monday, at: 630).isFree)
        #expect(!occupancy.status(of: "B102", on: .monday, at: 630).isFree)
        #expect(occupancy.status(of: "B103", on: .monday, at: 630).isFree)
        // Seules les salles de base sont proposées.
        #expect(occupancy.rooms == ["B101", "B102", "B103"])
    }

    @Test("Une salle englobante en bloque sept d'un coup")
    func floorWideRoomBlocksEverything() throws {
        let parts = ["B101", "B102", "B103", "B104", "B105", "B106", "B219"]
        let occupancy = RoomOccupancy(
            rooms: parts.map { room($0) } + [room("1er Etage + B219", basic: parts)],
            courses: [course("1er Etage + B219", start: 480, type: "TP")],
            durations: durations
        )

        let free = occupancy.freeRooms(on: .monday, at: 500)
        #expect(free.isEmpty)
    }

    @Test("Une salle inconnue de la table se représente elle-même")
    func unknownRoomStillCounts() {
        let occupancy = RoomOccupancy(
            rooms: [room("B004")],
            courses: [course("SalleMystere", start: 600), course("B004", start: 600)],
            durations: durations
        )
        #expect(!occupancy.status(of: "B004", on: .monday, at: 610).isFree)
        // La salle inconnue ne fait pas partie des salles proposées, mais son
        // cours n'a pas fait tomber le calcul.
        #expect(occupancy.rooms == ["B004"])
    }

    // MARK: Bornes horaires

    /// Une salle libérée à 10h00 doit être proposée à 10h00.
    @Test("La borne de fin est exclue")
    func endBoundIsExclusive() {
        let occupancy = RoomOccupancy(
            rooms: [room("B004")],
            courses: [course("B004", start: 480)], // 8h00 – 9h30
            durations: durations
        )
        #expect(!occupancy.status(of: "B004", on: .monday, at: 479 + 1).isFree)
        #expect(!occupancy.status(of: "B004", on: .monday, at: 569).isFree)
        #expect(occupancy.status(of: "B004", on: .monday, at: 570).isFree)
        #expect(occupancy.status(of: "B004", on: .monday, at: 479).isFree)
    }

    /// Entre deux cours qui s'enchaînent, la salle n'est pas réellement rendue.
    @Test("Des cours consécutifs comptent pour une seule occupation")
    func contiguousCoursesMerge() {
        let occupancy = RoomOccupancy(
            rooms: [room("B004")],
            courses: [
                course("B004", start: 480),  // 8h00 – 9h30
                course("B004", start: 570)   // 9h30 – 11h00
            ],
            durations: durations
        )

        guard case .busy(let until, _) = occupancy.status(of: "B004", on: .monday, at: 500) else {
            Issue.record("la salle devait être occupée")
            return
        }
        #expect(until == 660) // 11h00, et non 9h30
    }

    @Test("Le jour est pris en compte")
    func daysAreIndependent() {
        let occupancy = RoomOccupancy(
            rooms: [room("B004")],
            courses: [course("B004", day: .tuesday, start: 600)],
            durations: durations
        )
        #expect(!occupancy.status(of: "B004", on: .tuesday, at: 610).isFree)
        #expect(occupancy.status(of: "B004", on: .monday, at: 610).isFree)
    }

    @Test("On sait jusqu'à quand une salle reste libre")
    func reportsRemainingFreeTime() {
        let occupancy = RoomOccupancy(
            rooms: [room("B004"), room("B005")],
            courses: [course("B004", start: 660)], // libre jusqu'à 11h00
            durations: durations
        )

        let atTen = occupancy.status(of: "B004", on: .monday, at: 600)
        #expect(atTen == .free(until: 660))
        #expect(atTen.remaining(from: 600) == 60)

        // Aucun cours de la journée : rien ne borne la disponibilité.
        let other = occupancy.status(of: "B005", on: .monday, at: 600)
        #expect(other == .free(until: nil))
        #expect(other.remaining(from: 600) == nil)
    }

    /// « Où puis-je m'installer sans être délogé dans dix minutes ? »
    @Test("Les salles libres le plus longtemps viennent en tête")
    func sortsByRemainingTime() {
        let occupancy = RoomOccupancy(
            rooms: [room("B004"), room("B005"), room("B006")],
            courses: [
                course("B004", start: 630), // libre 30 min
                course("B005", start: 720)  // libre 2 h
            ],
            durations: durations
        )

        let free = occupancy.freeRooms(on: .monday, at: 600).map(\.room)
        #expect(free == ["B006", "B005", "B004"])
    }

    // MARK: Indisponibilités

    @Test("Une indisponibilité déclarée occupe la salle")
    func unavailabilityBlocksRoom() {
        let occupancy = RoomOccupancy(
            rooms: [room("Amphi1")],
            courses: [],
            unavailabilities: [
                RoomUnavailability(room: "Amphi1", day: .monday, startTime: 780, duration: 75, value: 0)
            ],
            durations: durations
        )

        guard case .busy(let until, let reason) = occupancy.status(of: "Amphi1", on: .monday, at: 800) else {
            Issue.record("la salle devait être occupée")
            return
        }
        #expect(until == 855)
        #expect(reason == .unavailable)
    }

    /// Une valeur non nulle exprime une préférence, pas un blocage : la traiter
    /// comme une occupation masquerait des salles utilisables.
    @Test("Une valeur non nulle n'est pas un blocage")
    func nonZeroValueIsIgnored() {
        let occupancy = RoomOccupancy(
            rooms: [room("Amphi1")],
            courses: [],
            unavailabilities: [
                RoomUnavailability(room: "Amphi1", day: .monday, startTime: 780, duration: 75, value: 5)
            ],
            durations: durations
        )
        #expect(occupancy.status(of: "Amphi1", on: .monday, at: 800).isFree)
    }

    @Test("Une indisponibilité sur une salle composite se propage")
    func unavailabilityExpandsToBasicRooms() {
        let occupancy = RoomOccupancy(
            rooms: [room("B010"), room("B115"), room("B005"),
                    room("Entretien", basic: ["B010", "B115", "B005"])],
            courses: [],
            unavailabilities: [
                RoomUnavailability(room: "Entretien", day: .thursday, startTime: 810, duration: 210, value: 0)
            ],
            durations: durations
        )
        #expect(occupancy.freeRooms(on: .thursday, at: 900).isEmpty)
    }

    // MARK: Données réelles

    /// Le résultat de bout en bout, sur la semaine 12 d'INFO réellement
    /// téléchargée. Ces listes ont été obtenues indépendamment lors de la phase
    /// d'analyse : elles valident l'implémentation Swift contre un calcul
    /// distinct, pas contre elle-même.
    @Test("Sur les données réelles, jeudi 10h00")
    func realDataThursdayMorning() throws {
        let rooms = try TestSupport.decode([Room].self, from: "rooms-INFO")
        let courses = try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-all")
        let unavailabilities = try TestSupport.decode([RoomUnavailability].self, from: "roomunavail-INFO")
        let types = try TestSupport.decode([CourseType].self, from: "coursetypes-INFO")
        let durations = Dictionary(types.map { ($0.name, $0.duration) }, uniquingKeysWith: { first, _ in first })

        let occupancy = RoomOccupancy(
            rooms: rooms,
            courses: courses,
            unavailabilities: unavailabilities,
            durations: durations
        )

        #expect(occupancy.rooms.count == 24)

        let free = occupancy.freeRooms(on: .thursday, at: 600).map(\.room).sorted()
        let busy = occupancy.busyRooms(on: .thursday, at: 600).map(\.room).sorted()

        #expect(busy == ["A011", "B005", "B007", "B008", "B009",
                         "B101", "B102", "B104", "B105", "Labo"])
        #expect(free == ["Amphi1", "Amphi2", "Amphi3", "B004", "B006", "B010", "B103",
                         "B106", "B113", "B115", "B219", "C004", "C006", "EXT"])
        #expect(free.count + busy.count == occupancy.rooms.count)
    }

    @Test("Sur les données réelles, une salle occupée dit par quoi")
    func realDataExplainsOccupancy() throws {
        let rooms = try TestSupport.decode([Room].self, from: "rooms-INFO")
        let courses = try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-all")
        let types = try TestSupport.decode([CourseType].self, from: "coursetypes-INFO")
        let durations = Dictionary(types.map { ($0.name, $0.duration) }, uniquingKeysWith: { first, _ in first })

        let occupancy = RoomOccupancy(rooms: rooms, courses: courses, durations: durations)

        guard case .busy(_, let reason) = occupancy.status(of: "B007", on: .thursday, at: 600) else {
            Issue.record("B007 devait être occupée")
            return
        }
        guard case .course(let module, let type) = reason else {
            Issue.record("l'occupation devait venir d'un cours")
            return
        }
        #expect(!module.isEmpty)
        #expect(!type.isEmpty)
    }

    /// Hors des heures de cours, tout doit être libre.
    @Test("Sur les données réelles, tout est libre à 7h00")
    func realDataEarlyMorning() throws {
        let rooms = try TestSupport.decode([Room].self, from: "rooms-INFO")
        let courses = try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-all")
        let types = try TestSupport.decode([CourseType].self, from: "coursetypes-INFO")
        let durations = Dictionary(types.map { ($0.name, $0.duration) }, uniquingKeysWith: { first, _ in first })

        let occupancy = RoomOccupancy(rooms: rooms, courses: courses, durations: durations)
        #expect(occupancy.freeRooms(on: .monday, at: 420).count == 24)
        // Et le week-end aussi.
        #expect(occupancy.freeRooms(on: .sunday, at: 600).count == 24)
    }

    @Test("L'état se calcule aussi depuis une date")
    func availabilityFromDate() throws {
        let rooms = try TestSupport.decode([Room].self, from: "rooms-INFO")
        let courses = try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-all")
        let types = try TestSupport.decode([CourseType].self, from: "coursetypes-INFO")
        let durations = Dictionary(types.map { ($0.name, $0.duration) }, uniquingKeysWith: { first, _ in first })

        let occupancy = RoomOccupancy(rooms: rooms, courses: courses, durations: durations)

        // Jeudi 19 mars 2026 à 10h00, heure de Blagnac.
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 19
        components.hour = 10
        let date = try #require(FlopCalendar.iso.date(from: components))

        #expect(Weekday(date: date) == .thursday)
        let byDate = occupancy.freeRooms(at: date).map(\.room)
        let byMinute = occupancy.freeRooms(on: .thursday, at: 600).map(\.room)
        #expect(byDate == byMinute)
    }
}
