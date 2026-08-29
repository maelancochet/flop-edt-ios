import Foundation
import Testing
@testable import FlopEDTKit

/// Les bugs relevés à l'audit du 28/08/2026, chacun avec le scénario réel qui
/// le produisait. Les données viennent de la production, pas de JSON écrit à la
/// main : si le serveur reprend une de ces formes, le test le dira.
@Suite("Régressions de l'audit")
struct AuditRegressionTests {

    // MARK: Décodage

    /// Le bug le plus grave, et le plus discret. Le serveur renvoie
    /// `"number": null` sur certains TP — relevé sur CS1/1GB2 aux semaines 36 et
    /// 40 de 2026, c'est-à-dire la rentrée. Avec un `Int` non optionnel,
    /// `JSONDecoder` échouait sur *tout le tableau* : l'étudiant voyait une
    /// semaine vide et « Réponse illisible du serveur », indéfiniment.
    @Test("Un `number` nul n'emporte plus la semaine entière")
    func nullCourseNumberIsTolerated() throws {
        let courses = try TestSupport.decode(
            Lenient<ScheduledCourse>.self, from: "courses-CS-BUT1-1GB2-S36"
        )
        #expect(courses.skipped == 0)
        #expect(courses.count == 12)

        let affected = try #require(courses.first { $0.id == 616313 })
        #expect(affected.number == nil)
        #expect(affected.room.name == "C004")
        #expect(affected.course.module.abbrev == "UNUM1")
    }

    /// Le garde-fou général : quoi qu'invente le serveur sur un cours, les
    /// autres doivent arriver. C'est la différence entre « il manque un cours »
    /// et « la semaine est vide ».
    @Test("Un objet illisible est écarté, pas la liste entière")
    func lenientArraySkipsOnlyTheBadElement() throws {
        let json = Data("""
        [
          {"id": 1, "start_time": 480, "day": "m",
           "course": {"id": 10, "type": "TD", "module": {"name": "Algo", "abbrev": "Algo",
                      "display": {"color_bg": "#fff", "color_txt": "#000"}}},
           "room": {"id": 5, "name": "B101"}},
          {"id": 2, "start_time": null, "day": "tu",
           "course": {"id": 11, "type": "TP", "module": {"name": "Reseau", "abbrev": "R",
                      "display": {"color_bg": "#fff", "color_txt": "#000"}}},
           "room": {"id": 6, "name": "B102"}},
          {"id": 3, "start_time": 600, "day": "w",
           "course": {"id": 12, "type": "CM", "module": {"name": "Maths", "abbrev": "M",
                      "display": {"color_bg": "#fff", "color_txt": "#000"}}},
           "room": {"id": 7, "name": "B103"}}
        ]
        """.utf8)

        let decoded = try FlopJSON.decoder.decode(Lenient<ScheduledCourse>.self, from: json)
        #expect(decoded.map(\.id) == [1, 3])
        #expect(decoded.skipped == 1)
    }

    /// Un tableau vide ne doit pas être confondu avec un tableau illisible.
    @Test("Un tableau vide reste un tableau vide")
    func lenientArrayHandlesEmpty() throws {
        let decoded = try FlopJSON.decoder.decode(
            Lenient<ScheduledCourse>.self, from: Data("[]".utf8)
        )
        #expect(decoded.isEmpty)
        #expect(decoded.skipped == 0)
    }

    /// L'API renvoie `{"username": …}`, jamais `{"name": …}` : le décodeur
    /// retombait donc sur la chaîne vide en silence.
    @Test("Un enseignant supplémentaire est lu quelle que soit la clé")
    func supplementaryTutorAcceptsEveryShape() throws {
        struct Wrapper: Decodable { let suppTutor: [SupplementaryTutor] }
        let json = Data(#"{"supp_tutor": [{"username": "mcochet"}, {"name": "dupont"}, "martin"]}"#.utf8)
        let decoded = try FlopJSON.decoder.decode(Wrapper.self, from: json)
        #expect(decoded.suppTutor.map(\.name) == ["mcochet", "dupont", "martin"])
    }

    /// Même fragilité que ``Referential`` : une valeur par défaut ne rend pas la
    /// clé facultative. Sans décodage tolérant, ajouter un champ ici rendait
    /// illisible tout le cache de semaines — donc l'affichage hors ligne.
    @Test("Une semaine en cache écrite par une version antérieure reste lisible")
    func weekScheduleToleratesOlderCacheFormat() throws {
        let legacy = Data("""
        {
          "week": {"week": 12, "year": 2026},
          "selection": {"department": "INFO", "promo": "BUT1", "group": "1A"},
          "courses": [],
          "fetched_at": "2026-08-01T10:00:00Z"
        }
        """.utf8)

        let schedule = try FlopJSON.decoder.decode(WeekSchedule.self, from: legacy)
        #expect(schedule.week == ISOWeek(week: 12, year: 2026))
        #expect(schedule.version == nil)
        #expect(schedule.unreadableCourses == 0)
        #expect(schedule.fetchedAt != .distantPast)
    }

    // MARK: Salles partagées

    /// Le calcul ne regardait que le département de l'utilisateur, alors que les
    /// salles de l'IUT sont partagées. Sur les données réelles de la semaine 12,
    /// jeudi 10h00, quatre des quinze salles annoncées libres à un étudiant
    /// d'INFO étaient occupées par CS ou GIM.
    @Test("Les salles prises par un autre département ne sont plus annoncées libres")
    func occupancyAccountsForOtherDepartments() throws {
        func source(_ department: String, rooms: String, courses: String, types: String) throws
            -> RoomOccupancy.Source {
            let types = try TestSupport.decode([CourseType].self, from: types)
            return RoomOccupancy.Source(
                department: department,
                rooms: try TestSupport.decode([Room].self, from: rooms),
                courses: try TestSupport.decode(Lenient<ScheduledCourse>.self, from: courses).values,
                durations: Dictionary(types.map { ($0.name, $0.duration) }, uniquingKeysWith: { a, _ in a })
            )
        }

        let info = try source("INFO", rooms: "rooms-INFO", courses: "courses-INFO-all", types: "coursetypes-INFO")
        let cs = try source("CS", rooms: "rooms-CS", courses: "courses-CS-all", types: "coursetypes-CS")
        let gim = try source("GIM", rooms: "rooms-GIM", courses: "courses-GIM-all", types: "coursetypes-GIM")

        // Ce que faisait l'app : INFO seul.
        let alone = RoomOccupancy(offering: info.rooms, sources: [info])
        // Ce qu'elle fait maintenant.
        let complete = RoomOccupancy(offering: info.rooms, sources: [info, cs, gim])

        #expect(alone.rooms == complete.rooms)
        #expect(alone.rooms.count == 24)

        let freeAlone = Set(alone.freeRooms(on: .thursday, at: 600).map(\.room))
        let freeComplete = Set(complete.freeRooms(on: .thursday, at: 600).map(\.room))

        #expect(freeAlone.count == 15)
        #expect(freeComplete.count == 11)
        // Les quatre salles que l'app proposait à tort.
        #expect(freeAlone.subtracting(freeComplete) == ["B006", "B113", "C004", "C006"])
        // Et rien n'est devenu libre au passage.
        #expect(freeComplete.subtracting(freeAlone).isEmpty)
    }

    /// Chaque département a son propre barème : un « TD » ne dure pas forcément
    /// la même chose partout. Utiliser celui de l'utilisateur pour les cours des
    /// autres décalerait les fins d'occupation.
    @Test("Chaque source applique le barème de durées de son département")
    func eachSourceUsesItsOwnDurations() {
        let room = Room(id: 1, name: "B101", subroomOf: [], departments: [], isBasic: true,
                        basicRooms: [RoomRef(id: 1, name: "B101")])
        func course(start: Int) -> ScheduledCourse {
            ScheduledCourse(
                id: start, room: RoomRef(id: 1, name: "B101"), startTime: start, day: .monday,
                course: Course(id: 1, type: "TD",
                               module: Module(name: "M", abbrev: "M",
                                              display: ModuleDisplay(colorBg: "#fff", colorTxt: "#000")))
            )
        }
        let occupancy = RoomOccupancy(
            offering: [room],
            sources: [
                .init(department: "INFO", rooms: [room], courses: [course(start: 480)], durations: ["TD": 90]),
                .init(department: "CS", rooms: [room], courses: [course(start: 600)], durations: ["TD": 120])
            ]
        )
        // 8h00 + 90 = 9h30 pour INFO ; 10h00 + 120 = 12h00 pour CS.
        #expect(occupancy.status(of: "B101", on: .monday, at: 500).remaining(from: 500) == 70)
        #expect(occupancy.status(of: "B101", on: .monday, at: 580) == .free(until: 600))
        guard case .busy(let until, _) = occupancy.status(of: "B101", on: .monday, at: 660) else {
            Issue.record("la salle devait être occupée par le cours de CS")
            return
        }
        #expect(until == 720)
    }

    /// Une salle composite peut n'être déclarée que dans la table d'un autre
    /// département tout en bloquant nos salles de base.
    @Test("Une salle composite déclarée ailleurs bloque quand même nos salles")
    func compositeFromAnotherDepartmentStillBlocks() {
        let b112 = Room(id: 1, name: "B112", subroomOf: [], departments: [], isBasic: true,
                        basicRooms: [RoomRef(id: 1, name: "B112")])
        let b113 = Room(id: 2, name: "B113", subroomOf: [], departments: [], isBasic: true,
                        basicRooms: [RoomRef(id: 2, name: "B113")])
        let composite = Room(id: 3, name: "B112+B113", subroomOf: [], departments: [], isBasic: false,
                             basicRooms: [RoomRef(id: 1, name: "B112"), RoomRef(id: 2, name: "B113")])

        let course = ScheduledCourse(
            id: 1, room: RoomRef(id: 3, name: "B112+B113"), startTime: 480, day: .monday,
            course: Course(id: 1, type: "TD",
                           module: Module(name: "M", abbrev: "M",
                                          display: ModuleDisplay(colorBg: "#fff", colorTxt: "#000")))
        )

        let occupancy = RoomOccupancy(
            offering: [b112, b113],                                   // INFO ne connaît pas la composite
            sources: [
                .init(department: "INFO", rooms: [b112, b113], durations: ["TD": 90]),
                .init(department: "GIM", rooms: [composite], courses: [course], durations: ["TD": 90])
            ]
        )
        #expect(occupancy.freeRooms(on: .monday, at: 500).isEmpty)
    }

    // MARK: Passage de minuit

    /// L'app restait sur la veille : la semaine était bien retéléchargée, mais
    /// le jour sélectionné ne bougeait pas — et comme c'est la même semaine ISO,
    /// le bouton « Aujourd'hui » ne s'affichait même pas.
    @Test("Le retour au premier plan ramène à aujourd'hui quand la nuit est passée")
    func resumeMovesToTodayAfterMidnight() {
        let monday = TestSupport.date("2026-03-16")
        let tuesday = TestSupport.date("2026-03-17")

        let moved = FlopCalendar.dateAfterResume(
            selected: FlopCalendar.today(now: monday), lastActive: monday, now: tuesday
        )
        #expect(moved == FlopCalendar.today(now: tuesday))
    }

    /// Mais pas au point de déranger quelqu'un qui consultait autre chose.
    @Test("Le retour au premier plan ne déplace pas une consultation en cours")
    func resumeLeavesADeliberateSelectionAlone() {
        let monday = TestSupport.date("2026-03-16")
        let tuesday = TestSupport.date("2026-03-17")
        let nextWeek = TestSupport.date("2026-03-24")

        // L'utilisateur regardait la semaine prochaine : on ne touche à rien.
        #expect(FlopCalendar.dateAfterResume(selected: nextWeek, lastActive: monday, now: tuesday) == nil)
        // Même jour : rien à faire non plus.
        #expect(FlopCalendar.dateAfterResume(
            selected: FlopCalendar.today(now: monday),
            lastActive: monday,
            now: monday.addingTimeInterval(3600)
        ) == nil)
    }

    // MARK: Classement des erreurs

    /// Une annulation remontait sous forme de `http(status: -999)` : un
    /// changement de groupe affichait un bandeau d'erreur incompréhensible.
    @Test("Une annulation est silencieuse, une panne de transport est réessayable")
    func errorClassification() {
        #expect(APIError.cancelled.isSilent)
        #expect(!APIError.cancelled.isRetryable)
        #expect(APIError.cancelled.errorDescription == nil)

        #expect(APIError.transport(code: -1004, detail: nil).isRetryable)
        #expect(!APIError.offline.isSilent)
    }
}
