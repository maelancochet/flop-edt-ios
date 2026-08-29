import Foundation
import Testing
@testable import FlopEDTKit

extension StubbedNetwork {
    @Suite("Chargement du référentiel")
    struct ReferentialLoaderTests {

        /// Branche le faux réseau sur les fixtures réelles.
        private func stubEverything() throws {
            StubURLProtocol.reset()
            try StubURLProtocol.stub("alldepts", fixture: "departments")
            try StubURLProtocol.stub("timesettings", fixture: "timesettings")
            try StubURLProtocol.stub("idtrainprog/?dept=RT", fixture: "trainprogs-RT")
            try StubURLProtocol.stub("idtrainprog", fixture: "trainprogs-RT")
            try StubURLProtocol.stub("structural/tree/?dept=INFO", fixture: "grouptree-INFO")
            try StubURLProtocol.stub("structural/tree", fixture: "grouptree-CS")
            try StubURLProtocol.stub("courses/type", fixture: "coursetypes-INFO")
        }

        private func loader(
            storage: any ReferentialStorage,
            bundled: Referential? = nil,
            now: @escaping @Sendable () -> Date = { .now },
            maxAttempts: Int = 1
        ) -> ReferentialLoader {
            ReferentialLoader(
                client: StubURLProtocol.makeClient(maxAttempts: maxAttempts),
                storage: storage,
                bundled: { bundled },
                now: now
            )
        }

        // MARK: Démarrage

        /// Le scénario de la toute première installation avec le serveur de l'IUT
        /// injoignable : l'utilisateur doit quand même pouvoir choisir son
        /// département.
        @Test("Sans cache ni réseau, l'instantané embarqué prend le relais")
        func fallsBackToBundledSnapshot() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.stubOffline()

            let snapshot = try #require(BundledReferential.load())
            let subject = loader(storage: InMemoryReferentialStorage(), bundled: snapshot)

            let local = await subject.loadLocal()
            #expect(!local.isEmpty)
            #expect(local.departments.count == 5)
            #expect(local.data(forDepartment: "INFO") != nil)

            // Le réseau échoue, mais on garde de quoi afficher.
            let outcome = await subject.refreshIfNeeded()
            #expect(outcome == .failed(.offline))
            #expect(await subject.hasUsableData)
        }

        @Test("Le cache disque prime sur l'instantané embarqué")
        func diskWinsOverBundle() async throws {
            StubURLProtocol.reset()
            let stored = Referential(
                departments: [Department(id: 1, abbrev: "NOUVEAU")],
                fetchedAt: .now
            )
            let bundled = Referential(
                departments: [Department(id: 103, abbrev: "INFO")],
                fetchedAt: .distantPast
            )
            let subject = loader(storage: InMemoryReferentialStorage(initial: stored), bundled: bundled)

            let local = await subject.loadLocal()
            #expect(local.departments.map(\.abbrev) == ["NOUVEAU"])
        }

        @Test("Un cache vide n'écrase pas l'instantané embarqué")
        func emptyDiskIsIgnored() async throws {
            StubURLProtocol.reset()
            let bundled = Referential(departments: [Department(id: 103, abbrev: "INFO")], fetchedAt: .now)
            let subject = loader(storage: InMemoryReferentialStorage(initial: Referential()), bundled: bundled)

            #expect(await subject.loadLocal().departments.map(\.abbrev) == ["INFO"])
        }

        // MARK: Rafraîchissement

        @Test("Le socle se recharge et se persiste")
        func refreshesAndPersists() async throws {
            try stubEverything()
            let storage = InMemoryReferentialStorage()
            let subject = loader(storage: storage)

            let result = try await subject.refreshBase()
            #expect(result.departments.count == 5)
            #expect(result.timeSettings(forDepartment: "INFO").dayFinishTime == 1125)

            let persisted = try #require(try storage.read())
            #expect(persisted.departments.count == 5)
        }

        /// Un rafraîchissement du socle ne doit pas faire retélécharger les
        /// départements déjà en main.
        @Test("Recharger le socle conserve les départements déjà chargés")
        func refreshingBaseKeepsDepartments() async throws {
            try stubEverything()
            let subject = loader(storage: InMemoryReferentialStorage())

            _ = try await subject.department("INFO")
            #expect(await subject.referential.data(forDepartment: "INFO") != nil)

            _ = try await subject.refreshBase()
            let after = await subject.referential
            #expect(after.departments.count == 5)
            #expect(after.data(forDepartment: "INFO") != nil)
        }

        @Test("Un référentiel frais ne déclenche aucune requête")
        func freshDataSkipsNetwork() async throws {
            try stubEverything()
            let stored = Referential(
                departments: [Department(id: 103, abbrev: "INFO")],
                fetchedAt: .now
            )
            let subject = loader(storage: InMemoryReferentialStorage(initial: stored))

            #expect(await subject.refreshIfNeeded() == .upToDate)
            #expect(StubURLProtocol.totalRequests == 0)
        }

        @Test("Un référentiel périmé est revalidé")
        func staleDataTriggersRefresh() async throws {
            try stubEverything()
            let stored = Referential(
                departments: [Department(id: 103, abbrev: "INFO")],
                fetchedAt: Date(timeIntervalSinceNow: -48 * 3600)
            )
            let subject = loader(storage: InMemoryReferentialStorage(initial: stored))

            #expect(await subject.refreshIfNeeded() == .updated)
            #expect(await subject.referential.departments.count == 5)
        }

        // MARK: Départements

        @Test("Un département frais est servi depuis le cache")
        func cachedDepartmentSkipsNetwork() async throws {
            try stubEverything()
            let subject = loader(storage: InMemoryReferentialStorage())

            _ = try await subject.department("INFO")
            let firstCount = StubURLProtocol.requestCount("structural/tree/?dept=INFO")

            _ = try await subject.department("INFO")
            #expect(StubURLProtocol.requestCount("structural/tree/?dept=INFO") == firstCount)
        }

        /// Un arbre de groupes de l'an dernier vaut mieux qu'un écran vide : il sera
        /// corrigé au prochain rafraîchissement réussi.
        @Test("Si le réseau tombe, un département périmé est quand même rendu")
        func staleDepartmentSurvivesNetworkFailure() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.stubOffline()

            let old = DepartmentReferential(
                trainingPrograms: [TrainingProgram(id: 189, abbrev: "BUT1", name: "BUT1")],
                groupTree: GroupTree(roots: []),
                courseTypes: [],
                fetchedAt: Date(timeIntervalSinceNow: -365 * 24 * 3600)
            )
            let stored = Referential(
                departments: [Department(id: 103, abbrev: "INFO")],
                departmentData: ["INFO": old],
                fetchedAt: .now
            )
            let subject = loader(storage: InMemoryReferentialStorage(initial: stored))

            let result = try await subject.department("INFO")
            #expect(result.trainingPrograms.map(\.abbrev) == ["BUT1"])
        }

        @Test("Sans cache ni réseau, la demande d'un département échoue franchement")
        func missingDepartmentThrows() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.stubOffline()
            let subject = loader(storage: InMemoryReferentialStorage())

            await #expect(throws: APIError.offline) {
                try await subject.department("INFO")
            }
        }

        /// L'écran de sélection peut demander deux fois le même département presque
        /// simultanément. Une seule requête doit partir.
        @Test("Deux demandes concurrentes partagent la même requête")
        func concurrentRequestsAreShared() async throws {
            StubURLProtocol.reset()
            try StubURLProtocol.stub("idtrainprog", fixture: "trainprogs-RT")
            StubURLProtocol.stub("structural/tree", StubURLProtocol.Stub(
                body: try TestSupport.fixture("grouptree-INFO"),
                delay: 0.2
            ))
            try StubURLProtocol.stub("courses/type", fixture: "coursetypes-INFO")

            let subject = loader(storage: InMemoryReferentialStorage())

            async let first = subject.department("INFO")
            async let second = subject.department("INFO")
            let (left, right) = try await (first, second)

            #expect(left == right)
            #expect(StubURLProtocol.requestCount("structural/tree") == 1)
        }

        @Test("Remettre à zéro vide le cache")
        func resetClearsStorage() async throws {
            try stubEverything()
            let storage = InMemoryReferentialStorage()
            let subject = loader(storage: storage)

            _ = try await subject.refreshBase()
            #expect(try storage.read() != nil)

            try await subject.reset()
            #expect(try storage.read() == nil)
            #expect(await !subject.hasUsableData)
        }
    }

}
