import Foundation
import Testing
@testable import FlopEDTKit

extension StubbedNetwork {

    /// Les régressions de l'audit qui se constatent au nombre de requêtes.
    @Suite("Régressions de l'audit — réseau")
    struct AuditNetworkRegressionTests {

        private func stubReferential() throws {
            StubURLProtocol.reset()
            try StubURLProtocol.stub("alldepts", fixture: "departments")
            try StubURLProtocol.stub("timesettings", fixture: "timesettings")
            try StubURLProtocol.stub("groups/types", fixture: "grouptypes")
            try StubURLProtocol.stub("idtrainprog", fixture: "trainprogs-RT")
            try StubURLProtocol.stub("structural/tree", fixture: "grouptree-INFO")
            try StubURLProtocol.stub("groups/structural/?", fixture: "structuralgroups-INFO")
            try StubURLProtocol.stub("courses/type", fixture: "coursetypes-INFO")
        }

        /// Le bouton « Actualiser départements et groupes » passait par le garde
        /// de fraîcheur de 24 h. Le référentiel venant d'être revalidé au
        /// lancement, il ne lançait donc **aucune requête** : le compteur
        /// tournait et rien ne se passait.
        @Test("Le bouton des réglages relance vraiment les requêtes")
        func forceRefreshIgnoresFreshness() async throws {
            try stubReferential()
            let stored = Referential(
                departments: [Department(id: 103, abbrev: "INFO")],
                fetchedAt: .now
            )
            let subject = ReferentialLoader(
                client: StubURLProtocol.makeClient(),
                storage: InMemoryReferentialStorage(initial: stored),
                bundled: { nil }
            )

            // Ce que faisait le bouton : rien.
            #expect(await subject.refreshIfNeeded() == .upToDate)
            #expect(StubURLProtocol.totalRequests == 0)

            // Ce qu'il fait maintenant.
            #expect(await subject.forceRefresh(departments: ["INFO"]) == .updated)
            #expect(StubURLProtocol.requestCount("alldepts") == 1)
            #expect(StubURLProtocol.requestCount("structural/tree") == 1)
        }

        /// L'instantané embarqué livre les cinq départements. Comme le
        /// rafraîchissement revalidait « tous les départements déjà chargés »,
        /// le premier lancement partait sur 23 requêtes — et tous les suivants
        /// aussi, puisque les cinq restaient en place. L'app ne doit revalider
        /// que le département suivi.
        @Test("Le lancement ne revalide que le département suivi")
        func refreshIsScopedToTheSelectedDepartment() async throws {
            try stubReferential()

            let everywhere = DepartmentReferential(
                trainingPrograms: [], groupTree: GroupTree(roots: []), courseTypes: []
            )
            let stored = Referential(
                departments: [Department(id: 103, abbrev: "INFO")],
                departmentData: ["INFO": everywhere, "CS": everywhere, "GIM": everywhere,
                                 "RT": everywhere, "LPMA": everywhere],
                fetchedAt: .distantPast
            )
            let subject = ReferentialLoader(
                client: StubURLProtocol.makeClient(),
                storage: InMemoryReferentialStorage(initial: stored),
                bundled: { nil }
            )

            #expect(await subject.refreshIfNeeded(departments: ["INFO"]) == .updated)

            // Le socle, plus un seul département : 3 + 4 requêtes.
            #expect(StubURLProtocol.requestCount("idtrainprog") == 1)
            #expect(StubURLProtocol.requestCount("structural/tree") == 1)
            #expect(StubURLProtocol.requestCount("courses/type") == 1)
            #expect(StubURLProtocol.totalRequests == 7)
        }

        /// Sans argument, on retombe sur l'ancien comportement — c'est ce que
        /// font les tests existants, et ce qu'il faut pour un rafraîchissement
        /// global explicite.
        @Test("Sans précision, tous les départements connus sont revalidés")
        func refreshWithoutScopeKeepsEveryDepartment() async throws {
            try stubReferential()
            let data = DepartmentReferential(
                trainingPrograms: [], groupTree: GroupTree(roots: []), courseTypes: []
            )
            let stored = Referential(
                departments: [Department(id: 103, abbrev: "INFO")],
                departmentData: ["INFO": data, "CS": data],
                fetchedAt: .distantPast
            )
            let subject = ReferentialLoader(
                client: StubURLProtocol.makeClient(),
                storage: InMemoryReferentialStorage(initial: stored),
                bundled: { nil }
            )

            #expect(await subject.refreshIfNeeded() == .updated)
            #expect(StubURLProtocol.requestCount("structural/tree") == 2)
        }

        // MARK: Salles

        /// `RoomStore` n'interrogeait que le département de l'utilisateur. Les
        /// salles étant partagées, il faut lire l'occupation de tous.
        @Test("Les salles libres interrogent tous les départements")
        func roomStoreQueriesEveryDepartment() async throws {
            StubURLProtocol.reset()
            try StubURLProtocol.stub("rooms/room/?dept=INFO", fixture: "rooms-INFO")
            try StubURLProtocol.stub("rooms/room/?dept=CS", fixture: "rooms-CS")
            try StubURLProtocol.stub("rooms/room/?dept=GIM", fixture: "rooms-GIM")
            try StubURLProtocol.stub("courses/type/?dept=CS", fixture: "coursetypes-CS")
            try StubURLProtocol.stub("courses/type/?dept=GIM", fixture: "coursetypes-GIM")
            try StubURLProtocol.stub("scheduledcourses/?dept=INFO", fixture: "courses-INFO-all")
            try StubURLProtocol.stub("scheduledcourses/?dept=CS", fixture: "courses-CS-all")
            try StubURLProtocol.stub("scheduledcourses/?dept=GIM", fixture: "courses-GIM-all")
            StubURLProtocol.stub("unavailableroom", json: "[]")

            let types = try TestSupport.decode([CourseType].self, from: "coursetypes-INFO")
            let durations = Dictionary(types.map { ($0.name, $0.duration) }, uniquingKeysWith: { a, _ in a })

            let store = RoomStore(client: StubURLProtocol.makeClient())
            let occupancy = try await store.occupancy(
                department: "INFO",
                week: ISOWeek(week: 12, year: 2026),
                durations: durations,
                departments: ["INFO", "CS", "GIM"]
            )

            #expect(occupancy.missingDepartments.isEmpty)
            #expect(occupancy.rooms.count == 24)
            // Les quatre salles que le calcul limité à INFO annonçait libres.
            let free = Set(occupancy.freeRooms(on: .thursday, at: 600).map(\.room))
            #expect(free.count == 11)
            #expect(!free.contains("B006"))
            #expect(!free.contains("B113"))
            #expect(!free.contains("C004"))
            #expect(!free.contains("C006"))

            #expect(StubURLProtocol.requestCount("scheduledcourses/?dept=CS") == 1)
            #expect(StubURLProtocol.requestCount("scheduledcourses/?dept=GIM") == 1)
        }

        /// Un département injoignable ne doit pas vider l'écran — mais le
        /// résultat devient optimiste, et l'app doit pouvoir le dire.
        @Test("Un département injoignable est signalé, pas ignoré")
        func unreachableDepartmentIsReported() async throws {
            StubURLProtocol.reset()
            try StubURLProtocol.stub("rooms/room/?dept=INFO", fixture: "rooms-INFO")
            try StubURLProtocol.stub("scheduledcourses/?dept=INFO", fixture: "courses-INFO-all")
            StubURLProtocol.stub("unavailableroom", json: "[]")
            // Tout ce qui concerne CS échoue.
            StubURLProtocol.stub("dept=CS", StubURLProtocol.Stub(status: 503, body: Data("{}".utf8)))

            let types = try TestSupport.decode([CourseType].self, from: "coursetypes-INFO")
            let durations = Dictionary(types.map { ($0.name, $0.duration) }, uniquingKeysWith: { a, _ in a })

            let store = RoomStore(client: StubURLProtocol.makeClient())
            let occupancy = try await store.occupancy(
                department: "INFO",
                week: ISOWeek(week: 12, year: 2026),
                durations: durations,
                departments: ["INFO", "CS"]
            )

            #expect(occupancy.missingDepartments == ["CS"])
            // L'écran reste affichable avec ce qu'on a.
            #expect(occupancy.rooms.count == 24)
        }

        /// Le département consulté, lui, ne peut pas être facultatif : sans ses
        /// cours il n'y a rien à afficher, et un écran vide vaut mieux qu'un
        /// écran faux.
        @Test("L'échec du département consulté reste une erreur")
        func ownDepartmentFailureThrows() async throws {
            StubURLProtocol.reset()
            try StubURLProtocol.stub("rooms/room/?dept=INFO", fixture: "rooms-INFO")
            StubURLProtocol.stub("scheduledcourses", StubURLProtocol.Stub(status: 503, body: Data("{}".utf8)))
            StubURLProtocol.stub("", StubURLProtocol.Stub(body: Data("[]".utf8)))

            let store = RoomStore(client: StubURLProtocol.makeClient())
            // Et c'est bien l'erreur du serveur qui remonte, pas un « hors
            // ligne » inventé : le message compte, l'utilisateur le lit.
            await #expect(throws: APIError.http(status: 503, detail: nil)) {
                try await store.occupancy(
                    department: "INFO",
                    week: ISOWeek(week: 12, year: 2026),
                    durations: [:],
                    departments: ["INFO", "CS"]
                )
            }
        }
    }
}
