import Foundation
import Testing
@testable import FlopEDTKit

/// Tests contre le serveur réel. Désactivés par défaut : la suite doit rester
/// hors ligne et déterministe. À lancer quand on soupçonne un changement d'API,
/// ou avant une mise en production :
///
/// ```
/// FLOP_LIVE_TESTS=1 swift test --filter Live
/// ```
///
/// Les fixtures du dossier `Fixtures/` viennent de ces mêmes endpoints ; si ces
/// tests passent alors que ceux de décodage échouent, c'est que le serveur a
/// changé de forme et qu'il faut recapturer les fixtures.
/// `.serialized` : ces tests tapent tous le même serveur, qui n'est pas
/// dimensionné pour une rafale. Lancés en parallèle, ils se mettaient
/// mutuellement en échec par expiration de délai.
@Suite(
    "Live — serveur réel",
    .enabled(if: ProcessInfo.processInfo.environment["FLOP_LIVE_TESTS"] != nil),
    .serialized
)
struct LiveAPITests {
    let client = FlopAPIClient()

    /// Une semaine qui porte réellement des cours, et un groupe qui existe.
    ///
    /// Surtout pas une constante : la semaine 12 de 2026 était pleine fin juillet
    /// et vide fin août, l'IUT ayant régénéré l'année entière. Un test live figé
    /// sur une date devient faux tout seul — c'est précisément la maintenance
    /// annuelle que cette v2 cherche à supprimer, et elle s'était réintroduite
    /// ici.
    ///
    /// On part de la semaine courante et on avance jusqu'à en trouver une
    /// garnie, en requêtes filtrées (9,8 Ko) et non départementales (66 Ko).
    func populatedWeek(dept: String = "INFO") async throws -> (week: ISOWeek, group: GroupPath) {
        let tree = GroupTree(roots: try await client.send(FlopEndpoints.groupTree(dept: dept)))
        let group = try #require(tree.allLeafPaths.first, "\(dept) : aucun groupe dans l'arbre")

        var week = ISOWeek.current()
        for _ in 0..<14 {
            let courses = try await client.send(
                FlopEndpoints.schedule(dept: dept, week: week, trainProg: group.promo, group: group.name)
            )
            if !courses.isEmpty { return (week, group) }
            week = week.advanced(by: 1)
        }
        Issue.record("\(dept) : aucune semaine garnie dans les 14 prochaines")
        throw APIError.offline
    }

    /// Exécute `work` sur chaque élément, quatre à la fois.
    ///
    /// Le serveur de l'IUT tient mal une rafale : cinquante requêtes lancées
    /// ensemble expirent toutes. Quatre de front reste rapide sans le brusquer.
    private func mapThrottled<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        limit: Int = 2,
        _ work: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        var results: [Output] = []
        var remaining = inputs[...]

        await withTaskGroup(of: Output.self) { group in
            for _ in 0..<min(limit, inputs.count) {
                guard let next = remaining.popFirst() else { break }
                group.addTask { await work(next) }
            }
            while let finished = await group.next() {
                results.append(finished)
                guard let next = remaining.popFirst() else { continue }
                group.addTask { await work(next) }
            }
        }
        return results
    }

    @Test("Le référentiel se charge en entier")
    func referential() async throws {
        let departments = try await client.send(FlopEndpoints.departments)
        #expect(!departments.isEmpty)

        for department in departments {
            let programs = try await client.send(FlopEndpoints.trainingPrograms(dept: department.abbrev))
            let tree = GroupTree(roots: try await client.send(FlopEndpoints.groupTree(dept: department.abbrev)))
            let types = try await client.send(FlopEndpoints.courseTypes(dept: department.abbrev))

            #expect(!programs.isEmpty, "\(department.abbrev) : aucune promo")
            #expect(!tree.allLeafPaths.isEmpty, "\(department.abbrev) : aucun groupe")
            #expect(!types.isEmpty, "\(department.abbrev) : aucun type de cours")

            // Toute promo présente dans l'arbre doit exister au référentiel,
            // sinon la requête d'emploi du temps partirait avec un `train_prog`
            // inconnu.
            let known = Set(programs.map(\.abbrev))
            for promo in tree.promos {
                #expect(known.contains(promo), "\(department.abbrev) : promo \(promo) absente de idtrainprog")
            }
        }
    }

    @Test("Chaque département a des horaires de journée")
    func timeSettings() async throws {
        let departments = try await client.send(FlopEndpoints.departments)
        let settings = try await client.send(FlopEndpoints.timeSettings)
        let byDepartment = Dictionary(uniqueKeysWithValues: settings.map { ($0.department, $0) })

        for department in departments {
            let entry = try #require(byDepartment[department.id], "\(department.abbrev) sans horaires")
            #expect(entry.dayStartTime < entry.dayFinishTime)
            #expect(!entry.days.isEmpty)
        }
    }

    /// Le filtrage côté serveur doit rester équivalent au filtrage manuel de la
    /// v1 : c'est ce qui autorise à supprimer `GroupHierarchyManager`.
    @Test("lineage=true équivaut au filtrage manuel sur les groupes parents")
    func lineageMatchesManualFiltering() async throws {
        let (week, path) = try await populatedWeek()

        let server = try await client.send(
            FlopEndpoints.schedule(dept: "INFO", week: week, trainProg: path.promo, group: path.name)
        )

        let everything = try await client.send(FlopEndpoints.departmentSchedule(dept: "INFO", week: week))
        let ancestry = Set(path.nodes.map(\.name))
        let manual = everything.filter { course in
            course.course.groups.contains { $0.trainProg == path.promo }
                && course.course.groups.contains { ancestry.contains($0.name) }
        }

        #expect(!server.isEmpty)
        #expect(Set(server.map(\.id)) == Set(manual.map(\.id)))
    }

    /// Le parcours complet d'un lancement, contre le vrai serveur.
    @Test("Le store charge une vraie semaine et relève sa version")
    func storeLoadsRealWeek() async throws {
        let (week, group) = try await populatedWeek()
        let selection = ScheduleSelection(department: "INFO", path: group)
        let store = ScheduleStore(selection: selection, client: client, cache: InMemoryScheduleCache())

        let schedule = try await store.refresh(week)
        #expect(!schedule.isEmpty)
        #expect(schedule.unreadableCourses == 0, "un cours n'a pas pu être lu")
        #expect(schedule.version != nil, "la version doit arriver avec les cours")
        #expect(schedule.courses.allSatisfy { $0.startTime > 0 })

        // Rechargée à l'identique, la semaine ne doit pas être vue comme modifiée.
        #expect(await store.checkForUpdate(week) == .unchanged)
    }

    /// L'écran « salles libres » de bout en bout, sur les cinq départements.
    @Test("Les salles libres se calculent pour chaque département")
    func roomsAcrossDepartments() async throws {
        let week = try await populatedWeek().week
        let rooms = RoomStore(client: client)
        let departments = try await client.send(FlopEndpoints.departments)

        // Sans les autres départements : on vérifie ici la forme du résultat,
        // pas l'exactitude de l'occupation — c'est l'objet du test suivant.
        for department in departments {
            let types = try await client.send(FlopEndpoints.courseTypes(dept: department.abbrev))
            let durations = Dictionary(
                types.map { ($0.name, $0.duration) },
                uniquingKeysWith: { first, _ in first }
            )
            let occupancy = try await rooms.occupancy(
                department: department.abbrev,
                week: week,
                durations: durations
            )

            #expect(!occupancy.rooms.isEmpty, "\(department.abbrev) : aucune salle")

            // Une salle est soit libre soit occupée, jamais les deux ni aucune.
            let free = occupancy.freeRooms(on: .thursday, at: 600).count
            let busy = occupancy.busyRooms(on: .thursday, at: 600).count
            #expect(free + busy == occupancy.rooms.count, "\(department.abbrev)")

            // À 6h du matin, plus personne.
            #expect(occupancy.freeRooms(on: .thursday, at: 360).count == occupancy.rooms.count)
        }
    }

    /// Le trou par lequel est passé le bug le plus grave de l'audit : ces tests
    /// ne regardaient que la semaine 12, alors que `"number": null` n'apparaît
    /// qu'aux semaines 36 et 40 de 2026 — celles de la rentrée. On balaie donc
    /// toute la fenêtre de livraison, sur les cinq départements.
    ///
    /// `skipped` doit rester à zéro : ``Lenient`` empêche désormais un cours mal
    /// formé d'emporter la semaine, mais s'il en écarte un, c'est qu'un champ a
    /// changé de forme et qu'il faut aller voir.
    ///
    /// Cinquante-cinq requêtes lourdes : c'est un contrôle d'avant-livraison,
    /// pas un test de routine. Le serveur de l'IUT répond en 502 si on le
    /// bouscule, d'où le débit volontairement bas et la variable dédiée :
    ///
    /// ```
    /// FLOP_LIVE_TESTS=1 FLOP_LIVE_SWEEP=1 swift test --filter LiveAPITests
    /// ```
    @Test(
        "Aucune semaine de la rentrée n'est illisible",
        .enabled(if: ProcessInfo.processInfo.environment["FLOP_LIVE_SWEEP"] != nil)
    )
    func everyWeekOfTheTermDecodes() async throws {
        let departments = try await client.send(FlopEndpoints.departments).map(\.abbrev)
        let targets = departments.flatMap { department in
            (35...45).map { (department, ISOWeek(week: $0, year: 2026)) }
        }
        let client = self.client

        let problems = await mapThrottled(targets) { target -> String? in
            let (department, week) = target
            do {
                let courses = try await client.send(
                    FlopEndpoints.departmentSchedule(dept: department, week: week)
                )
                guard courses.skipped > 0 else { return nil }
                return "\(department) \(week) : \(courses.skipped) cours illisibles"
            } catch {
                return "\(department) \(week) : \(error)"
            }
        }.compactMap { $0 }

        #expect(
            problems.isEmpty,
            "\(problems.count) semaine(s) en défaut :\n\(problems.sorted().joined(separator: "\n"))"
        )
    }

    /// Le second bug de l'audit, sur les données du jour : tenir compte des
    /// autres départements ne peut qu'*enlever* des salles de la liste des
    /// libres, jamais en ajouter — et sur une semaine de cours, il en enlève.
    ///
    /// Un seul département consulté : chaque appel interroge déjà les cinq, et
    /// boucler dessus multipliait par cinq une requête qui est la plus lourde
    /// de l'app.
    @Test("Les autres départements retirent bien des salles de la liste des libres")
    func sharedRoomsReduceTheFreeList() async throws {
        let week = try await populatedWeek().week
        let departments = try await client.send(FlopEndpoints.departments).map(\.abbrev)
        let store = RoomStore(client: client)

        let types = try await client.send(FlopEndpoints.courseTypes(dept: "INFO"))
        let durations = Dictionary(
            types.map { ($0.name, $0.duration) }, uniquingKeysWith: { first, _ in first }
        )

        let alone = try await store.occupancy(
            department: "INFO", week: week, durations: durations, departments: []
        )
        let complete = try await store.occupancy(
            department: "INFO", week: week, durations: durations, departments: departments
        )

        #expect(complete.missingDepartments.isEmpty)
        #expect(alone.rooms == complete.rooms, "les salles proposées ne changent pas")

        // Tenir compte des autres départements ne peut qu'enlever des salles de
        // la liste des libres, jamais en ajouter — et sur une semaine de cours,
        // il s'en trouve forcément un moment où il en enlève.
        var reduced = 0
        for day in [Weekday.monday, .tuesday, .wednesday, .thursday, .friday] {
            for minute in stride(from: 480, through: 1080, by: 30) {
                let freeAlone = Set(alone.freeRooms(on: day, at: minute).map(\.room))
                let freeComplete = Set(complete.freeRooms(on: day, at: minute).map(\.room))
                #expect(freeComplete.isSubset(of: freeAlone), "\(day) \(minute) : une salle ne peut pas se libérer")
                if freeComplete.count < freeAlone.count { reduced += 1 }
            }
        }
        #expect(reduced > 0, "aucun créneau où un autre département occupe une salle partagée")
    }

    /// Fournir `group` sans `train_prog` doit remonter le message du serveur, et
    /// non une erreur de décodage.
    @Test("Une requête mal formée remonte le message du serveur")
    func serverErrorSurfaces() async throws {
        let endpoint = Endpoint<[ScheduledCourse]>(
            path: "fetch/scheduledcourses/",
            query: ["dept": "INFO", "week": "12", "year": "2026", "group": "1A"]
        )
        await #expect(throws: APIError.self) {
            try await client.send(endpoint)
        }
    }
}
